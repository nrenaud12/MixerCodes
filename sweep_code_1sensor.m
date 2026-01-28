%% sweep_IF_power_P12.m
% RF source @ GPIB 15, LO source @ GPIB 19, IF power sensor @ GPIB 12
clear; clc;

%% ---------------- USER SETTINGS ----------------
VENDOR = 'KEYSIGHT';
BOARD  = 7;              % <-- must match what works on your machine
timeout_s = 1;

ADDR_RF = 15;            % RF sweeper/source
ADDR_LO = 19;            % LO sweeper/source
ADDR_IFSENSOR = 13;      % P12 = IF power sensor

% Mixer relationship
IF_Hz   = 1e9;           % fixed IF

% Source setpoints
PRF_dBm = -10;           % RF generator power setting
PLO_dBm = 10;            % LO generator power setting

% Sweep configuration
sweepWhat = 'RF';        % 'RF' or 'LO'
side      = 'high';      % 'high' => fLO = fRF + IF ; 'low' => fLO = fRF - IF

f_start_GHz = 6.0;
f_stop_GHz  = 12.0;
Npts        = 81;

settle_s = 0.20;         % increase if needed

% Tell sensor the IF frequency once (recommended)
set_sensor_freq = true;

% Debug / robustness knobs
do_source_reset  = false;  % some sweepers hate *RST
do_sensor_reset  = false;  % your earlier working P12 read did NOT reset hard
print_syst_err   = true;   % print instrument error queue messages if supported

% Treat absurd P12 readings as "invalid" (many meters return ~9.9E37)
invalid_abs_threshold = 1e20;

%% ---------------- CONNECT INSTRUMENTS ----------------
rf_src = open_gpib(VENDOR, BOARD, ADDR_RF, timeout_s);
lo_src = open_gpib(VENDOR, BOARD, ADDR_LO, timeout_s);
p12    = open_gpib(VENDOR, BOARD, ADDR_IFSENSOR, timeout_s);

cleanupObj = onCleanup(@() close_all({rf_src, lo_src, p12})); %#ok<NASGU>

% Optional sanity check:
% disp(['RF : ' strtrim(scpi_query(rf_src,'*IDN?'))]);
% disp(['LO : ' strtrim(scpi_query(lo_src,'*IDN?'))]);
% disp(['P12: ' strtrim(scpi_query(p12,   '*IDN?'))]);

%% ---------------- CONFIGURE SOURCES ----------------
if do_source_reset
    src_rst(rf_src);
    src_rst(lo_src);
end

src_set_power_dBm(rf_src, PRF_dBm, print_syst_err, 'RF');
src_set_power_dBm(lo_src, PLO_dBm, print_syst_err, 'LO');

src_output_on(rf_src, true, print_syst_err, 'RF');
src_output_on(lo_src, true, print_syst_err, 'LO');

%% ---------------- CONFIGURE IF POWER SENSOR (P12) ----------------
pwr_sensor_preset(p12, do_sensor_reset);

if set_sensor_freq
    % Tell sensor the frequency it is measuring (IF). Improves accuracy.
    pwr_set_freq_Hz(p12, IF_Hz);
end

%% ---------------- SWEEP ----------------
f_sweep_Hz = linspace(f_start_GHz*1e9, f_stop_GHz*1e9, Npts);

fRF_Hz     = nan(1, Npts);
fLO_Hz     = nan(1, Npts);
PIF_dBm    = nan(1, Npts);     % P12 reading at IF

for k = 1:Npts
    f = f_sweep_Hz(k);

    % Determine fRF/fLO keeping IF fixed
    switch upper(sweepWhat)
        case 'RF'
            fRF = f;
            if strcmpi(side,'high')
                fLO = fRF + IF_Hz;
            else
                fLO = fRF - IF_Hz;
            end
        case 'LO'
            fLO = f;
            if strcmpi(side,'high')
                fRF = fLO - IF_Hz;
            else
                fRF = fLO + IF_Hz;
            end
        otherwise
            error('sweepWhat must be ''RF'' or ''LO''.');
    end

    fRF_Hz(k) = fRF;
    fLO_Hz(k) = fLO;

    % Program sources (unit-formatted commands, avoids e-notation issues)
    src_set_freq_Hz(rf_src, fRF, print_syst_err, 'RF');
    src_set_freq_Hz(lo_src, fLO, print_syst_err, 'LO');

    pause(settle_s);

    % Read IF power on P12 (with raw capture)
    [p_read, raw] = pwr_read_dBm(p12);

    if ~isfinite(p_read) || abs(p_read) > invalid_abs_threshold
        PIF_dBm(k) = NaN;
        fprintf('k=%3d/%3d | fRF=%.6f GHz | fLO=%.6f GHz | P12(IF)=INVALID | raw="%s"\n', ...
            k, Npts, fRF/1e9, fLO/1e9, raw);
    else
        PIF_dBm(k) = p_read;
        fprintf('k=%3d/%3d | fRF=%.6f GHz | fLO=%.6f GHz | P12(IF)=%.2f dBm\n', ...
            k, Npts, fRF/1e9, fLO/1e9, p_read);
    end
end

%% ---------------- PLOTS ----------------
switch upper(sweepWhat)
    case 'RF'
        xGHz = fRF_Hz/1e9;
        xlab = 'RF Frequency (GHz)';
    case 'LO'
        xGHz = fLO_Hz/1e9;
        xlab = 'LO Frequency (GHz)';
end

figure;
plot(xGHz, PIF_dBm, '-o');
grid on;
xlabel(xlab);
ylabel('IF Power at P12 (dBm)');
title(sprintf('IF Power vs Sweep (%s-side, IF=%.3f GHz)', side, IF_Hz/1e9));

%% ========================================================================
%% ---- helpers ----

function inst = open_gpib(vendor, board, primaryAddr, timeout_s)
    inst = instrfind('Type','gpib','BoardIndex',board,'PrimaryAddress',primaryAddr,'Tag','');
    if isempty(inst)
        inst = gpib(vendor, board, primaryAddr);
    else
        fclose(inst);
        inst = inst(1);
    end
    inst.Timeout = timeout_s;
    fopen(inst);
end

function close_all(instList)
    for i = 1:numel(instList)
        inst = instList{i};
        try
            if ~isempty(inst) && strcmpi(inst.Status,'open')
                fclose(inst);
            end
        catch
        end
        try, delete(inst); catch, end
    end
end

function src_rst(src)
    scpi_try_soft(src, { '*RST', ':SYST:PRES', 'SYST:PRES' });
end

function src_output_on(src, onoff, printErr, tag)
    if onoff
        scpi_try_soft(src, { ':OUTP ON', 'OUTP ON', ':OUTP:STAT ON', 'OUTP:STAT ON' });
    else
        scpi_try_soft(src, { ':OUTP OFF', 'OUTP OFF', ':OUTP:STAT OFF', 'OUTP:STAT OFF' });
    end
    if printErr, syst_err_soft(src, tag); end
end

function src_set_freq_Hz(src, fHz, printErr, tag)
    % Many sweepers reject scientific notation. Try unit-formatted commands first.
    fGHz = fHz/1e9;
    fMHz = fHz/1e6;
    fInt = round(fHz);

    cmdList = {
        % GHZ forms
        sprintf('FREQ:CW %.6f GHZ', fGHz)
        sprintf('FREQ:CW %.6fGHZ',  fGHz)
        sprintf('FREQ %.6f GHZ',    fGHz)
        sprintf('FREQ %.6fGHZ',     fGHz)
        sprintf(':FREQ:CW %.6f GHZ', fGHz)
        sprintf(':FREQ %.6f GHZ',    fGHz)

        % MHZ forms
        sprintf('FREQ:CW %.3f MHZ', fMHz)
        sprintf('FREQ %.3f MHZ',    fMHz)
        sprintf(':FREQ:CW %.3f MHZ', fMHz)
        sprintf(':FREQ %.3f MHZ',    fMHz)

        % Integer Hz forms (no exponent)
        sprintf('FREQ:CW %d HZ', fInt)
        sprintf('FREQ %d HZ',    fInt)
        sprintf(':FREQ:CW %d',   fInt)
        sprintf(':FREQ %d',      fInt)
    };

    for i = 1:numel(cmdList)
        try
            fprintf(src, cmdList{i});
            pause(0.02);
            if printErr
                err = syst_err_soft(src, tag);
                % If error queue returns 0/no error, assume command accepted
                if isempty(err) || startsWith(err,'+0') || startsWith(err,'0')
                    return;
                end
            else
                return;
            end
        catch
        end
    end
end

function src_set_power_dBm(src, p_dBm, printErr, tag)
    scpi_try_soft(src, {
        sprintf(':POW %.6f dBm', p_dBm)
        sprintf('POW %.6f dBm', p_dBm)
        sprintf(':POW:LEV %.6f dBm', p_dBm)
        sprintf('POW:LEV %.6f dBm', p_dBm)
        });
    if printErr, syst_err_soft(src, tag); end
end

function pwr_sensor_preset(pwr, doReset)
    if doReset
        scpi_try_soft(pwr, { '*RST' });
    end
    scpi_try_soft(pwr, { ':UNIT:POW DBM','UNIT:POW DBM',':SENS:UNIT:POW DBM','SENS:UNIT:POW DBM' });
end

function pwr_set_freq_Hz(pwr, fHz)
    % Avoid exponent here too
    fInt = round(fHz);
    scpi_try_soft(pwr, {
        sprintf(':SENS:FREQ %d', fInt)
        sprintf('SENS:FREQ %d',  fInt)
        sprintf(':FREQ %d',      fInt)
        sprintf('FREQ %d',       fInt)
        });
end

function [p_dBm, raw] = pwr_read_dBm(pwr)
    % Trigger (safe if unsupported)
    scpi_try_soft(pwr, { ':INIT:IMM','INIT:IMM',':INIT','INIT' });

    % Read value; capture raw so we can debug sentinel/invalid outputs
    cmdList = {':FETC?','FETC?',':READ?','READ?',':MEAS:POW?','MEAS:POW?',':MEAS?','MEAS?'};
    raw = '';
    for i = 1:numel(cmdList)
        try
            fprintf(pwr, cmdList{i});
            raw = strtrim(fscanf(pwr));
            break;
        catch
        end
    end

    tmp = sscanf(raw, '%f', 1);   % handles "-12.34 dBm" and "9.9E37"
    if isempty(tmp) || isnan(tmp)
        p_dBm = NaN;
    else
        p_dBm = tmp;
    end
end

function scpi_try_soft(inst, cmdList)
    if ischar(cmdList), cmdList = {cmdList}; end
    for i = 1:numel(cmdList)
        try, fprintf(inst, cmdList{i}); return; catch, end
    end
end

function out = scpi_query(inst, cmd)
    fprintf(inst, cmd);
    out = fscanf(inst);
end

function err = syst_err_soft(inst, tag)
    err = '';
    try
        fprintf(inst, 'SYST:ERR?');
        err = strtrim(fscanf(inst));
        % Only print non-zero errors
        if ~isempty(err) && ~startsWith(err,'+0') && ~startsWith(err,'0')
            fprintf('[%s] SYST:ERR? -> %s\n', tag, err);
        end
    catch
        % instrument might not support SYST:ERR?
    end
end
