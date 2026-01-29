clear; clc;

%% ---------------- USER SETTINGS ----------------
VENDOR = 'KEYSIGHT';
BOARD  = 7;
LO_ADDR = 19;                 
RF_ADDR = 15;
SENSOR_ADDR = 13;             % power sensor address
  
LO_f_GHz = 7.000;             % LO frequency in GHz
LO_p_dBm = 10.0;              % LO power in dBm

RF_f_GHz = 8.000;             % RF frequency in GHz
RF_p_dBm = -10.0;             % RF power in dBm

settle_s = 2.0;               % stabilize time after turning ON outputs
timeout_s_sensor = 3;         %power sensor timeout time

SENSOR_OFFSET_dB = 0;         % +20 if reading a -20 dB coupler port, etc.

% estimated insertion loss 
RF_path_loss_dB   = 0;        % cable/fixture loss from RF gen to DUT RF port
IF_chain_cal_dB   = 0;        % gain/loss between DUT IF output and sensor plane

%% ---------------- INTERNAL SETTINGS ----------------
timeout_s_gen   = 5;
write_retries   = 3;
write_pause_s   = 0.2;

lo = [];
rf = [];
pwr = [];

try
    %% -------- Open + configure the two generators (visadev) --------
    lo = visadev(sprintf('GPIB0::%d::INSTR', LO_ADDR));
    lo.Timeout = timeout_s_gen;
    configureTerminator(lo, "LF");

    rf = visadev(sprintf('GPIB0::%d::INSTR', RF_ADDR));
    rf.Timeout = timeout_s_gen;
    configureTerminator(rf, "LF");

    % Preset both
    write_with_retry(lo, 'IP', write_retries, write_pause_s);
    write_with_retry(rf, 'IP', write_retries, write_pause_s);
    pause(0.5);

    % Program LO
    write_with_retry(lo, sprintf('CW%.6fGZ', LO_f_GHz), write_retries, write_pause_s);
    write_with_retry(lo, sprintf('PL%.3fDB', LO_p_dBm), write_retries, write_pause_s);

    % Program RF
    write_with_retry(rf, sprintf('CW%.6fGZ', RF_f_GHz), write_retries, write_pause_s);
    write_with_retry(rf, sprintf('PL%.3fDB', RF_p_dBm), write_retries, write_pause_s);

    % Turn ON both RF outputs
    write_with_retry(lo, 'RF1', write_retries, write_pause_s);
    write_with_retry(rf, 'RF1', write_retries, write_pause_s);

    fprintf('LO ON: %.6f GHz @ %.1f dBm (GPIB %d)\n', LO_f_GHz, LO_p_dBm, LO_ADDR);
    fprintf('RF ON: %.6f GHz @ %.1f dBm (GPIB %d)\n', RF_f_GHz, RF_p_dBm, RF_ADDR);

    %% -------- Wait to stabilize --------
    pause(settle_s);

    %% -------- Read power sensor (legacy gpib object) --------
    pwr = gpib(VENDOR, BOARD, SENSOR_ADDR);
    pwr.Timeout = timeout_s_sensor;
    fopen(pwr);

    % Soft setup (won't error if unsupported)
    scpi_try_soft(pwr, {':UNIT:POW DBM','UNIT:POW DBM',':SENS:UNIT:POW DBM','SENS:UNIT:POW DBM'});

    % Trigger + read
    scpi_try_soft(pwr, {':INIT:IMM','INIT:IMM',':INIT','INIT'});
    Pout_dBm = scpi_query_num(pwr, {':FETC?','FETC?',':READ?','READ?',':MEAS:POW?','MEAS:POW?',':MEAS?','MEAS?'}) ...
               + SENSOR_OFFSET_dB;

    fprintf('\nMeasured output power = %.2f dBm (sensor addr %d)\n', Pout_dBm, SENSOR_ADDR);

    % Optional conversion loss estimate
    PRF_in_est_dBm = RF_p_dBm - RF_path_loss_dB;
    PIF_at_DUT_dBm = Pout_dBm + IF_chain_cal_dB;
    ConvLoss_dB    = PRF_in_est_dBm - PIF_at_DUT_dBm;

    fprintf('Estimated conversion loss = %.2f dB  (PRF_in_est=%.2f dBm, PIF_at_DUT=%.2f dBm)\n', ...
            ConvLoss_dB, PRF_in_est_dBm, PIF_at_DUT_dBm);

catch ME
    warning('Measurement failed: %s', ME.message);
end

%% -------- Always: turn OFF both generators + close sensor --------
% Turn off generators
try
    if ~isempty(lo), write_with_retry(lo, 'RF0', write_retries, write_pause_s); end
catch ME2
    warning('Could not turn LO RF OFF: %s', ME2.message);
end
try
    if ~isempty(rf), write_with_retry(rf, 'RF0', write_retries, write_pause_s); end
catch ME3
    warning('Could not turn RF gen RF OFF: %s', ME3.message);
end
fprintf('\nGenerators OFF.\n');

% Close power sensor
try
    if ~isempty(pwr) && strcmpi(pwr.Status,'open'), fclose(pwr); end
catch
end
try
    if ~isempty(pwr), delete(pwr); end
catch
end

% Clear visadev handles
clear lo rf;

%% ---------------- helper functions ----------------
function write_with_retry(inst, cmd, retries, pause_s)
    for i = 1:retries
        try
            writeline(inst, cmd);
            pause(pause_s);
            return;
        catch ME
            if i == retries
                rethrow(ME);
            end
            pause(pause_s);
        end
    end
end

function scpi_try_soft(inst, cmdList)
    if ischar(cmdList), cmdList = {cmdList}; end
    for i = 1:numel(cmdList)
        try
            fprintf(inst, cmdList{i});
            return;
        catch
        end
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
            s = strtrim(scpi_query(inst, cmdList{i}));
            tmp = sscanf(s, '%f', 1);   % handles "-12.34 dBm"
            if ~isempty(tmp) && ~isnan(tmp)
                val = tmp;
                return;
            end
        catch ME
            lastErr = ME;
        end
    end
    if ~isempty(lastErr), rethrow(lastErr); end
    error('Could not parse numeric response from power sensor.');
end
