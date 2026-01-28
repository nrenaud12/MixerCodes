
clear; clc;

%% ---------------- USER SETTINGS ----------------
VENDOR = 'KEYSIGHT';   
BOARD  = 0;            

ADDR_LO = 10;
ADDR_RF = 19;
ADDR_SA = 18;

ADDR_PWRS_RF = 12;
ADDR_PWRS_LO = 13;
ADDR_PWRS_IF = 17;     % optional IF sensor

% Mixer test settings
IF_Hz      = 1e9;
PLO_dBm    = 18;       % LO source setting (generator)
PRF_dBm    = -10;      % RF source setting (generator)

% Reference-plane offsets (set to 0 if your sensors already read at DUT plane)
% if sensor is on a -20 dB coupler coupled port, add +20 dB to infer mainline power.
RF_sensor_offset_dB = 20;   % add to sensor reading to estimate RF power at DUT plane
LO_sensor_offset_dB = 20;   % add to sensor reading to estimate LO power at DUT plane
IF_sensor_offset_dB = 0;   % add to sensor reading to estimate IF power at DUT plane (if using IF sensor)

% Sweep configuration
sweepWhat = 'RF';      % 'RF' or 'LO'
side      = 'high';    % 'high' => fLO = fRF + IF ; 'low' => fLO = fRF - IF

f_start_GHz = 2.0;
f_stop_GHz  = 6.0;
Npts        = 81;

settle_s = 0.20;       % increase if readings jump around

% IF output measurement choice:
use_if_power_sensor = false;  % true => use GPIB17 for IF power, false => use spectrum analyzer marker

% Spectrum analyzer settings (used when use_if_power_sensor=false)
SA_span_Hz = 20e6;     % span around IF
SA_rbw_Hz  = 10e3;
SA_vbw_Hz  = 10e3;
SA_ref_dBm = 0;        % adjust so IF tone is on-screen and not compressed
SA_att_dB  = 10;       % adjust to avoid overload

%% ---------------- CONNECT INSTRUMENTS ----------------
lo_src  = open_gpib(VENDOR, BOARD, ADDR_LO,  30);
rf_src  = open_gpib(VENDOR, BOARD, ADDR_RF,  30);
specan  = open_gpib(VENDOR, BOARD, ADDR_SA,  30);

pwr_rf  = open_gpib(VENDOR, BOARD, ADDR_PWRS_RF, 30);
pwr_lo  = open_gpib(VENDOR, BOARD, ADDR_PWRS_LO, 30);

if use_if_power_sensor
    pwr_if = open_gpib(VENDOR, BOARD, ADDR_PWRS_IF, 30);
else
    pwr_if = [];
end

% IDN prints 
% disp(['LO : ' strtrim(scpi_query(lo_src,'*IDN?'))]);
% disp(['RF : ' strtrim(scpi_query(rf_src,'*IDN?'))]);
% disp(['SA : ' strtrim(scpi_query(specan,'*IDN?'))]);
% disp(['P_RF: ' strtrim(scpi_query(pwr_rf,'*IDN?'))]);
% disp(['P_LO: ' strtrim(scpi_query(pwr_lo,'*IDN?'))]);
% if use_if_power_sensor, disp(['P_IF: ' strtrim(scpi_query(pwr_if,'*IDN?'))]); end

%% ---------------- CONFIGURE SOURCES ----------------
src_rst(lo_src);
src_rst(rf_src);

src_set_power_dBm(lo_src, PLO_dBm);
src_set_power_dBm(rf_src, PRF_dBm);

src_output_on(lo_src, true);
src_output_on(rf_src, true);

%% ---------------- CONFIGURE POWER SENSORS ----------------
pwr_sensor_preset(pwr_rf);
pwr_sensor_preset(pwr_lo);
if use_if_power_sensor
    pwr_sensor_preset(pwr_if);
end

%% ---------------- CONFIGURE SPECTRUM ANALYZER ----------------
if ~use_if_power_sensor
    sa_preset(specan);
    sa_config_if_marker(specan, IF_Hz, SA_span_Hz, SA_rbw_Hz, SA_vbw_Hz, SA_ref_dBm, SA_att_dB);
end

%% ---------------- SWEEP ----------------
f_sweep_Hz = linspace(f_start_GHz*1e9, f_stop_GHz*1e9, Npts);

fRF_Hz = nan(size(f_sweep_Hz));
fLO_Hz = nan(size(f_sweep_Hz));

PinRF_dBm = nan(size(f_sweep_Hz));   % from RF power sensor 
PinLO_dBm = nan(size(f_sweep_Hz));   % from LO power sensor

PoutIF_dBm = nan(size(f_sweep_Hz));  % from SA marker OR IF sensor
CL_dB      = nan(size(f_sweep_Hz));  % conversion loss

for k = 1:numel(f_sweep_Hz)

    f = f_sweep_Hz(k);

    % Determine fRF and fLO based on sweep mode and side selection, keeping IF fixed
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

    % Program sources
    src_set_freq_Hz(rf_src, fRF);
    src_set_freq_Hz(lo_src, fLO);

    pause(settle_s);

    % Read input powers from power sensors (each point)
    prf = pwr_read_dBm(pwr_rf) + RF_sensor_offset_dB;
    plo = pwr_read_dBm(pwr_lo) + LO_sensor_offset_dB;

    PinRF_dBm(k) = prf;
    PinLO_dBm(k) = plo;

    % Measure IF output power
    if use_if_power_sensor
        pif = pwr_read_dBm(pwr_if) + IF_sensor_offset_dB;
    else
        pif = sa_marker_power_dBm(specan, IF_Hz);
    end

    PoutIF_dBm(k) = pif;

    % Conversion loss (dB)
    CL_dB(k) = PinRF_dBm(k) - PoutIF_dBm(k);

    fprintf('k=%3d/%3d | fRF=%.6f GHz | fLO=%.6f GHz | PinRF=%.2f dBm | PoutIF=%.2f dBm | CL=%.2f dB\n', ...
        k, numel(f_sweep_Hz), fRF/1e9, fLO/1e9, PinRF_dBm(k), PoutIF_dBm(k), CL_dB(k));

end

%% ---------------- PLOTS ----------------
figure;
plot(fRF_Hz/1e9, CL_dB, '-o');
grid on;
xlabel('RF Frequency (GHz)');
ylabel('Conversion Loss (dB)');
title(sprintf('Conversion Loss (IF=%.3f GHz, %s-side)', IF_Hz/1e9, side));

figure;
plot(fRF_Hz/1e9, PinRF_dBm, '-o'); hold on;
plot(fRF_Hz/1e9, PinLO_dBm, '-o');
grid on;
xlabel('RF Frequency (GHz)');
ylabel('Measured Power at DUT Plane (dBm)');
legend('Pin RF (sensor)','Pin LO (sensor)','Location','best');
title('Measured Input Powers vs Frequency');

%% ========================================================================

function inst = open_gpib(vendor, board, primaryAddr, timeout_s)
    % Reuse existing if already created
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

function src_rst(src)
    scpi_try(src, { '*RST', ':SYST:PRES', 'SYST:PRES' });
end

function src_output_on(src, onoff)
    if onoff
        scpi_try(src, { ':OUTP ON', 'OUTP ON', ':OUTP:STAT ON', 'OUTP:STAT ON' });
    else
        scpi_try(src, { ':OUTP OFF', 'OUTP OFF', ':OUTP:STAT OFF', 'OUTP:STAT OFF' });
    end
end

function src_set_freq_Hz(src, fHz)
    cmdList = {
        sprintf(':FREQ %.12e', fHz)
        sprintf('FREQ %.12e', fHz)
        sprintf(':FREQ:CW %.12e', fHz)
        sprintf('FREQ:CW %.12e', fHz)
        };
    scpi_try(src, cmdList);
end

function src_set_power_dBm(src, p_dBm)
    cmdList = {
        sprintf(':POW %.6f dBm', p_dBm)
        sprintf('POW %.6f dBm', p_dBm)
        sprintf(':POW:LEV %.6f dBm', p_dBm)
        sprintf('POW:LEV %.6f dBm', p_dBm)
        };
    scpi_try(src, cmdList);
end

function sa_preset(sa)
    scpi_try(sa, { '*RST', ':SYST:PRES', 'SYST:PRES' });
end

function sa_config_if_marker(sa, fIF_Hz, span_Hz, rbw_Hz, vbw_Hz, ref_dBm, att_dB)
    % Basic SA setup for measuring a single tone at IF with marker readout
    scpi_try(sa, {
        ':INIT:CONT OFF', 'INIT:CONT OFF', ...
        sprintf(':FREQ:CENT %.12e', fIF_Hz), sprintf('FREQ:CENT %.12e', fIF_Hz), ...
        sprintf(':FREQ:SPAN %.12e', span_Hz), sprintf('FREQ:SPAN %.12e', span_Hz), ...
        sprintf(':BAND:RES %.12e', rbw_Hz), sprintf('BAND:RES %.12e', rbw_Hz), ...
        sprintf(':BAND:VID %.12e', vbw_Hz), sprintf('BAND:VID %.12e', vbw_Hz), ...
        sprintf(':DISP:WIND:TRAC:Y:RLEV %.6f', ref_dBm), sprintf('DISP:WIND:TRAC:Y:RLEV %.6f', ref_dBm), ...
        sprintf(':INP:ATT %.3f', att_dB), sprintf('INP:ATT %.3f', att_dB), ...
        ':CALC:MARK1:STAT ON', 'CALC:MARK1:STAT ON', ...
        sprintf(':CALC:MARK1:X %.12e', fIF_Hz), sprintf('CALC:MARK1:X %.12e', fIF_Hz), ...
        ':DET POS', 'DET POS'
        });
end

function p_dBm = sa_marker_power_dBm(sa, fHz)
    % Single sweep and read marker amplitude at fHz
    scpi_try(sa, {
        sprintf(':CALC:MARK1:X %.12e', fHz), sprintf('CALC:MARK1:X %.12e', fHz)
        });

    % Trigger single sweep and wait
    scpi_try(sa, { ':INIT:IMM;*WAI', 'INIT:IMM;*WAI', ':INIT;*WAI', 'INIT;*WAI' });

    % Query marker Y (power in dBm)
    p_dBm = scpi_query_num(sa, {
        ':CALC:MARK1:Y?', 'CALC:MARK1:Y?', ...
        ':CALC:MARK:Y?',  'CALC:MARK:Y?'
        });
end

function pwr_sensor_preset(pwr)
    % Set sensor/meter to return in dBm if possible
    scpi_try(pwr, { '*RST' });
    scpi_try(pwr, { ':UNIT:POW DBM', 'UNIT:POW DBM', ':SENS:UNIT:POW DBM', 'SENS:UNIT:POW DBM' });
end

function p_dBm = pwr_read_dBm(pwr)
    % Read power from a power sensor/meter in dBm (tries several common SCPI variants)
    % Trigger if needed (safe to ignore if unsupported)
    scpi_try(pwr, { ':INIT:IMM', 'INIT:IMM', ':INIT', 'INIT' });

    % Read value
    p_dBm = scpi_query_num(pwr, {
        ':FETC?', 'FETC?', ...
        ':READ?', 'READ?', ...
        ':MEAS:POW?', 'MEAS:POW?', ...
        ':MEAS?', 'MEAS?'
        });
end

function scpi_try(inst, cmdList)
    if ischar(cmdList), cmdList = {cmdList}; end
    lastErr = [];
    for i = 1:numel(cmdList)
        try
            fprintf(inst, cmdList{i});
            return;
        catch ME
            lastErr = ME;
        end
    end
    if ~isempty(lastErr)
        rethrow(lastErr);
    end
end

function out = scpi_query(inst, cmd)
    fprintf(inst, cmd);
    out = fscanf(inst);
end

function val = scpi_query_num(inst, cmdList)
    if ischar(cmdList), cmdList = {cmdList}; end
    lastErr = [];
    for i = 1:numel(cmdList)
        try
            s = scpi_query(inst, cmdList{i});
            val = str2double(strtrim(s));
            if ~isnan(val)
                return;
            end
        catch ME
            lastErr = ME;
        end
    end
    if ~isempty(lastErr)
        rethrow(lastErr);
    else
        error('Could not parse numeric response from instrument.');
    end
end
