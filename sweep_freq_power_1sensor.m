%% mixer_conversion_loss_sweep
% Sweep RF frequency and record output power at each point.
clear; clc;

%% ---- user settings ----
% RF source
RFAddr = 15;
rfStart_GHz = 6;
rfStop_GHz = 12;
rfStep_GHz = 0.1;
RFPower_dBm = -10;

% LO Source
LOAddr = 19;
LOPower_dBm = 10;
LOPowerSweep_dBm = [10, 13, 15, 18];
ifTarget_GHz = 1.0;

% Power sensor
VENDOR = 'KEYSIGHT';
BOARD = 7;
SENSOR_ADDR = 12;
SENSOR_TIMEOUT_S = 3;
OFF_dB = 0; % +20 if reading a -20 dB coupler port
set_sensor_freq = true; % tell sensor IF frequency for better accuracy

% Timing
settle_s = 2;          % wait after setting RF before reading power
write_retries = 3;
write_pause_s = 0.2;
read_retries = 3;
read_pause_s = 0.2;
invalid_abs_threshold = 1e20;

% Output file
save_csv = true;
out_csv = 'mixer_conversion_loss_sweep.csv';

%% ---- derived sweep list ----
rfFreqs_GHz = rfStart_GHz:rfStep_GHz:rfStop_GHz;
numPoints = numel(rfFreqs_GHz);
measuredPower_dBm = nan(numPoints, 1);

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
    % Synthesized sweeper (RF source)
    synth = visadev(sprintf('GPIB0::%d::INSTR', RFAddr));
    configureTerminator(synth, "LF");
    cleanupSynth = onCleanup(@() safe_clear(synth));
    write_with_retry(synth, 'IP', write_retries, write_pause_s);
    pause(0.5);
    write_with_retry(synth, sprintf('PL%fDB', RFPower_dBm), write_retries, write_pause_s);
    write_with_retry(synth, 'RF1', write_retries, write_pause_s);
    rfOnSynth = true;

    fprintf('Synthesizer set to %g dBm. RF is ON.\n', RFPower_dBm);

    % Sweep oscillator (LO source)
    osc = visadev(sprintf('GPIB0::%d::INSTR', LOAddr));
    osc.Timeout = 10;
    configureTerminator(osc, "LF");
    cleanupOsc = onCleanup(@() safe_clear(osc));
    write_with_retry(osc, 'IP', write_retries, write_pause_s);
    pause(0.5);
    write_with_retry(osc, sprintf('PL%.3fDB', LOPower_dBm), write_retries, write_pause_s);
    write_with_retry(osc, 'RF1', write_retries, write_pause_s);
    rfOnOsc = true;

    fprintf('Oscillator set to %.1f dBm. RF is ON.\n', LOPower_dBm);

    % Power sensor
    pwr = gpib(VENDOR, BOARD, SENSOR_ADDR);
    pwr.Timeout = SENSOR_TIMEOUT_S;
    fopen(pwr);
    cleanupPwr = onCleanup(@() close_one(pwr));
    sensor_soft_setup(pwr);
    if set_sensor_freq
        pwr_set_freq_Hz(pwr, ifTarget_GHz * 1e9);
    end

    % Sweep loop (default LO power, then additional LO power settings)
    for pIdx = 1:numel(LOPowerSweep_dBm) + 1
        if pIdx == 1
            loPower_dBm = LOPower_dBm;
            powerLabel = 'default';
        else
            loPower_dBm = LOPowerSweep_dBm(pIdx - 1);
            powerLabel = sprintf('%.1f dBm', loPower_dBm);
        end

        write_with_retry(osc, sprintf('PL%.3fDB', loPower_dBm), write_retries, write_pause_s);
        fprintf('Starting sweep with LO power = %s.\n', powerLabel);

        measuredPower_dBm(:) = NaN;
        for idx = 1:numPoints
            rfFreq = rfFreqs_GHz(idx);
            loFreq_GHz = rfFreq - ifTarget_GHz;
            write_with_retry(synth, sprintf('CW%fGZ', rfFreq), write_retries, write_pause_s);
            write_with_retry(osc, sprintf('CW%.6fGZ', loFreq_GHz), write_retries, write_pause_s);
            pause(settle_s);

            [pwr_dBm, raw] = pwr_read_dBm(pwr, read_retries, read_pause_s);
            if ~isfinite(pwr_dBm) || abs(pwr_dBm) > invalid_abs_threshold
                measuredPower_dBm(idx) = NaN;
                fprintf('RF %.3f GHz / LO %.3f GHz -> INVALID (raw="%s")\n', ...
                    rfFreq, loFreq_GHz, raw);
                continue;
            end
            measuredPower_dBm(idx) = pwr_dBm + OFF_dB;

            fprintf('RF %.3f GHz / LO %.3f GHz -> %.2f dBm\n', ...
                rfFreq, loFreq_GHz, measuredPower_dBm(idx));
        end

        if save_csv
            results = table(rfFreqs_GHz(:), measuredPower_dBm(:), ...
                'VariableNames', {'RF_GHz','MeasuredPower_dBm'});
            try
                if pIdx == 1
                    out_csv_name = out_csv;
                else
                    [outBase, outExt] = fileparts(out_csv);
                    out_csv_name = sprintf('%s_lo_%ddBm%s', outBase, round(loPower_dBm), outExt);
                end
                writetable(results, out_csv_name);
                fprintf('Saved results to %s\n', out_csv_name);
            catch ME
                warning('Could not save CSV: %s', ME.message);
            end
        end
    end
catch ME
    warning('Error during run: %s', ME.message);
end

% Explicit shutdown
safe_rf_off_and_clear(synth, rfOnSynth, write_retries, write_pause_s, 'Synthesizer');
safe_rf_off_and_clear(osc, rfOnOsc, write_retries, write_pause_s, 'Oscillator');

% Save results now handled per sweep above.

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

function sensor_soft_setup(pwr)
    scpi_try_soft(pwr, {':UNIT:POW DBM','UNIT:POW DBM',':SENS:UNIT:POW DBM','SENS:UNIT:POW DBM'});
end

function pwr_set_freq_Hz(pwr, fHz)
    fInt = round(fHz);
    scpi_try_soft(pwr, {
        sprintf(':SENS:FREQ %d', fInt)
        sprintf('SENS:FREQ %d',  fInt)
        sprintf(':FREQ %d',      fInt)
        sprintf('FREQ %d',       fInt)
        });
end

function [p_dBm, raw] = pwr_read_dBm(pwr, retries, pause_s)
    cmdList = {':FETC?','FETC?',':READ?','READ?',':MEAS:POW?','MEAS:POW?',':MEAS?','MEAS?'};
    p_dBm = NaN;
    raw = '';
    for i = 1:retries
        scpi_try_soft(pwr, {':INIT:IMM','INIT:IMM',':INIT','INIT'});
        for j = 1:numel(cmdList)
            try
                fprintf(pwr, cmdList{j});
                raw = strtrim(fscanf(pwr));
                break;
            catch
            end
        end
        tmp = sscanf(raw, '%f', 1);
        if ~isempty(tmp) && ~isnan(tmp)
            p_dBm = tmp;
            return;
        end
        pause(pause_s);
    end
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
