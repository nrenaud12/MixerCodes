% Mixer sweep code
% Sweep RF frequency, maintain constant IF, and record output power at each point.
clear; clc;

%% ---- user settings ----
% RF Source
RFAddr = 15;
rfStart_GHz = 6;
rfStop_GHz = 12;
rfStep_GHz = 0.1;
RFPower_dBm = -10;

% LO Source
LOAddr = 19;
LOPower_dBm = 13;
ifTarget_GHz = 3.0;

% Power sensor
VENDOR = 'KEYSIGHT';
BOARD = 7;
SENSOR_ADDR = 12;
SENSOR_TIMEOUT_S = 3;
OFF_dB = 0;            % +20 if reading a -20 dB coupler port

% Timing
settle_s = 2;          % wait after power on before reading power
write_retries = 3;
write_pause_s = 0.2;

% Output file
save_csv = true;
out_csv = 'mixer_conversion_loss_sweep_1ghz_13dBm.csv';

%% ---- derived sweep list ----
rfFreqs_GHz = rfStart_GHz:rfStep_GHz:rfStop_GHz;
numPoints = numel(rfFreqs_GHz);
measuredPower_dBm = nan(numPoints, 1);

%% ---- open instruments ----
RF = [];
LO = [];
pwr = [];
cleanupRF = [];
cleanupLO = [];
cleanupPwr = [];
rfOn = false;
loOn = false;

try
    % RF Source
    RF = visadev(sprintf('GPIB0::%d::INSTR', RFAddr));
    configureTerminator(RF, "LF");
    cleanupRF = onCleanup(@() safe_clear(RF));
    write_with_retry(RF, 'IP', write_retries, write_pause_s);
    pause(0.5);
    write_with_retry(RF, sprintf('PL%fDB', RFPower_dBm), write_retries, write_pause_s);
    write_with_retry(RF, 'RF1', write_retries, write_pause_s);
    rfOn = true;

    fprintf('Synthesizer set to %g dBm. RF is ON.\n', RFPower_dBm);

    % LO Source
    LO = visadev(sprintf('GPIB0::%d::INSTR', LOAddr));
    LO.Timeout = 10;
    configureTerminator(LO, "LF");
    cleanupLO = onCleanup(@() safe_clear(LO));
    write_with_retry(LO, 'IP', write_retries, write_pause_s);
    pause(0.5);
    write_with_retry(LO, sprintf('PL%.3fDB', LOPower_dBm), write_retries, write_pause_s);
    write_with_retry(LO, 'RF1', write_retries, write_pause_s);
    loOn = true;

    fprintf('Oscillator set to %.1f dBm. RF is ON.\n', LOPower_dBm);

    % Power sensor
    pwr = gpib(VENDOR, BOARD, SENSOR_ADDR);
    pwr.Timeout = SENSOR_TIMEOUT_S;
    fopen(pwr);
    cleanupPwr = onCleanup(@() close_one(pwr));
    scpi_try_soft(pwr, {':UNIT:POW DBM','UNIT:POW DBM',':SENS:UNIT:POW DBM','SENS:UNIT:POW DBM'});

    % Sweep loop
    for idx = 1:numPoints
        rfFreq = rfFreqs_GHz(idx);
        loFreq_GHz = rfFreq - ifTarget_GHz;
        write_with_retry(RF, sprintf('CW%fGZ', rfFreq), write_retries, write_pause_s);
        write_with_retry(LO, sprintf('CW%.6fGZ', loFreq_GHz), write_retries, write_pause_s);
        pause(settle_s);

        scpi_try_soft(pwr, {':INIT:IMM','INIT:IMM',':INIT','INIT'});
        measuredPower_dBm(idx) = scpi_query_num(pwr, ...
            {':FETC?','FETC?',':READ?','READ?',':MEAS:POW?','MEAS:POW?',':MEAS?','MEAS?'}) + OFF_dB;

        fprintf('RF %.3f GHz / LO %.3f GHz -> %.2f dBm\n', ...
            rfFreq, loFreq_GHz, measuredPower_dBm(idx));
    end
catch ME
    warning('Error during run: %s', ME.message);
end

% Explicit shutdown
safe_rf_off_and_clear(RF, rfOn, write_retries, write_pause_s, 'Synthesizer');
safe_rf_off_and_clear(LO, loOn, write_retries, write_pause_s, 'Oscillator');

% Save results
if save_csv
    results = table(rfFreqs_GHz(:), measuredPower_dBm(:), ...
        'VariableNames', {'RF_GHz','MeasuredPower_dBm'});
    try
        writetable(results, out_csv);
        fprintf('Saved results to %s\n', out_csv);
    catch ME
        warning('Could not save CSV: %s', ME.message);
    end
end

%% ---- helpers ----
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

function safe_rf_off_and_clear(inst, rfOn, retries, pause_s, label)
    try
        if rfOn && ~isempty(inst) && isvalid(inst)
            write_with_retry(inst, 'RF0', retries, pause_s);
            fprintf('%s RF is OFF.\n', label);
        end
        safe_clear(inst);
    catch ME
        warning('Could not turn %s RF OFF: %s', label, ME.message);
    end
end

function safe_clear(inst)
    try
        if ~isempty(inst) && isvalid(inst)
            clear inst;
        end
    catch
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

function val = scpi_query_num(inst, cmdList)
    if ischar(cmdList), cmdList = {cmdList}; end
    lastErr = [];
    for i = 1:numel(cmdList)
        try
            s = strtrim(scpi_query(inst, cmdList{i}));
            tmp = sscanf(s, '%f', 1);
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

function close_one(inst)
    try
        if ~isempty(inst) && strcmpi(inst.Status,'open')
            fclose(inst);
        end
    catch
    end
    try, delete(inst); catch, end
end