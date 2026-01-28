%% signal_gen_single_test.m
% Open signal generator, set a single frequency/power, then exit.
clear; clc;

%% ---- user settings ----
VENDOR = 'KEYSIGHT';
BOARD  = 7;     % GPIB board index
ADDR   = 15;    % signal generator GPIB address
timeout_s = 3;

f_GHz = 1.000;  % target frequency
p_dBm = -10;    % target power

settle_s = 0.1;

%% ---- open signal generator ----
gen = gpib(VENDOR, BOARD, ADDR);
gen.Timeout = timeout_s;
fopen(gen);
cleanupObj = onCleanup(@() close_one(gen)); %#ok<NASGU>

idn = safe_idn(gen);
if idn == ""
    fprintf('Signal generator opened (no IDN response).\n');
else
    fprintf('Signal generator IDN: %s\n', idn);
end

%% ---- configure output ----
src_set_freq_mode_cw(gen);
src_set_freq_Hz_units(gen, f_GHz * 1e9);
src_set_power_unit_dbm(gen);
src_set_power_dBm(gen, p_dBm);
src_output_on(gen, true);
pause(settle_s);

fprintf('Set: f=%.6f GHz, P=%.1f dBm. Exiting now.\n', f_GHz, p_dBm);

%% ================= helpers =================
function out = safe_idn(dev)
    out = "";
    try
        fprintf(dev, '*IDN?');
        out = strtrim(fscanf(dev));
    catch
    end
end

function close_one(inst)
    try
        if ~isempty(inst) && strcmpi(inst.Status,'open')
            fclose(inst);
        end
    catch
    end
    try, delete(inst); catch, end
end

function scpi_try_soft(inst, cmdList)
    if ischar(cmdList), cmdList = {cmdList}; end
    for i = 1:numel(cmdList)
        try, fprintf(inst, cmdList{i}); return; catch, end
    end
end

function src_output_on(dev, onoff)
    if onoff
        scpi_try_soft(dev, {':OUTP ON','OUTP ON',':OUTP:STAT ON','OUTP:STAT ON'});
    else
        scpi_try_soft(dev, {':OUTP OFF','OUTP OFF',':OUTP:STAT OFF','OUTP:STAT OFF'});
    end
end

function src_set_freq_mode_cw(dev)
    scpi_try_soft(dev, {':FREQ:MODE CW','FREQ:MODE CW',':SOUR:FREQ:MODE CW','SOUR:FREQ:MODE CW'});
end

function src_set_power_unit_dbm(dev)
    scpi_try_soft(dev, {':POW:UNIT DBM','POW:UNIT DBM',':SOUR:POW:UNIT DBM','SOUR:POW:UNIT DBM'});
end

function src_set_power_dBm(dev, p_dBm)
    scpi_try_soft(dev, {
        sprintf(':POW %.3f', p_dBm)
        sprintf('POW %.3f', p_dBm)
        sprintf(':POW:LEV %.3f', p_dBm)
        sprintf('POW:LEV %.3f', p_dBm)
        sprintf(':SOUR:POW %.3f', p_dBm)
        sprintf('SOUR:POW %.3f', p_dBm)
        sprintf(':SOUR:POW:LEV %.3f', p_dBm)
        sprintf('SOUR:POW:LEV %.3f', p_dBm)
    });
end

function src_set_freq_Hz_units(dev, fHz)
    fGHz = fHz/1e9; fMHz = fHz/1e6; fInt = round(fHz);
    cmdList = {
        sprintf('FREQ:CW %.6f GHZ', fGHz)
        sprintf('FREQ %.6f GHZ',    fGHz)
        sprintf(':FREQ:CW %.6f GHZ', fGHz)
        sprintf(':FREQ %.6f GHZ',    fGHz)
        sprintf('SOUR:FREQ:CW %.6f GHZ', fGHz)
        sprintf(':SOUR:FREQ:CW %.6f GHZ', fGHz)
        sprintf('SOUR:FREQ %.6f GHZ',    fGHz)
        sprintf(':SOUR:FREQ %.6f GHZ',    fGHz)
        sprintf('FREQ:CW %.3f MHZ', fMHz)
        sprintf('FREQ %.3f MHZ',    fMHz)
        sprintf('FREQ:CW %d HZ',    fInt)
        sprintf('FREQ %d HZ',       fInt)
        sprintf(':FREQ:CW %d',      fInt)
        sprintf(':FREQ %d',         fInt)
        sprintf('SOUR:FREQ:CW %d',  fInt)
        sprintf(':SOUR:FREQ:CW %d', fInt)
        sprintf('SOUR:FREQ %d',     fInt)
        sprintf(':SOUR:FREQ %d',    fInt)
    };
    for i = 1:numel(cmdList)
        try
            fprintf(dev, cmdList{i});
            pause(0.02);
            return;
        catch
        end
    end
end
