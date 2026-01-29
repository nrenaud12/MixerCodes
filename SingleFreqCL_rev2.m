
clear; clc;

%% ---- user settings ----
% Synthesized sweeper (HP 8341B)
synthAddr = 19;
synthFreq_GHz = 8;
synthPower_dBm = 10;

% Sweep oscillator (HP 8350B)
oscAddr = 15;
oscFreq_GHz = 7.000;
oscPower_dBm = -10;

% Power sensor (HP 437B)
VENDOR = 'KEYSIGHT';
BOARD = 7;
SENSOR_ADDR = 12;
SENSOR_TIMEOUT_S = 3;
OFF_dB = 0; % +20 if reading a -20 dB coupler port
set_sensor_freq = true; 

% Timing
settle_s = 2;          % wait after setting RF before reading power
write_retries = 3;
write_pause_s = 0.2;
read_retries = 3;
read_pause_s = 0.2;
invalid_abs_threshold = 1e20;
%% ---- open instruments ----
synth = [];
osc = [];
pwr = [];
cleanupSynth = [];
cleanupOsc = [];
cleanupPwr = [];
rfOnSynth = false;
rfOnOsc = false;

try
    % Synthesized sweeper
    synth = visadev(sprintf('GPIB0::%d::INSTR', synthAddr));
    configureTerminator(synth, "LF");
    cleanupSynth = onCleanup(@() safe_clear(synth));
    write_with_retry(synth, 'IP', write_retries, write_pause_s);
    pause(0.5);
    write_with_retry(synth, sprintf('CW%fGZ', synthFreq_GHz), write_retries, write_pause_s);
    write_with_retry(synth, sprintf('PL%fDB', synthPower_dBm), write_retries, write_pause_s);
    write_with_retry(synth, 'RF1', write_retries, write_pause_s);
    rfOnSynth = true;

    fprintf('Synthesizer set to %g GHz at %g dBm. RF is ON.\n', ...
        synthFreq_GHz, synthPower_dBm);

    % Sweep oscillator
    osc = visadev(sprintf('GPIB0::%d::INSTR', oscAddr));
    osc.Timeout = 20;
    configureTerminator(osc, "LF");
    cleanupOsc = onCleanup(@() safe_clear(osc));
    write_with_retry(osc, 'IP', write_retries, write_pause_s);
    pause(0.5);
    write_with_retry(osc, sprintf('CW%.6fGZ', oscFreq_GHz), write_retries, write_pause_s);
    write_with_retry(osc, sprintf('PL%.3fDB', oscPower_dBm), write_retries, write_pause_s);
    write_with_retry(osc, 'RF1', write_retries, write_pause_s);
    rfOnOsc = true;

    fprintf('Oscillator set to %.6f GHz at %.1f dBm. RF is ON.\n', ...
        oscFreq_GHz, oscPower_dBm);

    % Power sensor
    pwr = gpib(VENDOR, BOARD, SENSOR_ADDR);
    pwr.Timeout = SENSOR_TIMEOUT_S;
    fopen(pwr);
    cleanupPwr = onCleanup(@() close_one(pwr));
    scpi_try_soft(pwr, {':UNIT:POW DBM','UNIT:POW DBM',':SENS:UNIT:POW DBM','SENS:UNIT:POW DBM'});

    pause(settle_s);

    scpi_try_soft(pwr, {':INIT:IMM','INIT:IMM',':INIT','INIT'});
    P12 = scpi_query_num(pwr, {':FETC?','FETC?',':READ?','READ?',':MEAS:POW?','MEAS:POW?',':MEAS?','MEAS?'}) + OFF_dB;
    fprintf('Measured power = %.2f dBm\n', P12);
catch ME
    warning('Error during run: %s', ME.message);
end

% Explicit shutdown
safe_rf_off_and_clear(synth, rfOnSynth, write_retries, write_pause_s, 'Synthesizer');
safe_rf_off_and_clear(osc, rfOnOsc, write_retries, write_pause_s, 'Oscillator');

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
