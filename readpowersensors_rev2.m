%% read_P12_P13_P17_only.m
% One-shot read of power sensors at GPIB addresses 12, 13, 17.
clear; clc;

VENDOR = 'KEYSIGHT';
BOARD  = 7;      % <-- working GPIB board index
timeout_s = 10;

ADDR_12 = 12;
ADDR_13 = 13;
%%ADDR_17 = 17;

% Offsets (e.g., +20 if reading a -20 dB coupler port)
OFF_12_dB = 0;
OFF_13_dB = 0;
OFF_17_dB = 0;

% Open sensors
p12 = gpib(VENDOR, BOARD, ADDR_12); p12.Timeout = timeout_s; fopen(p12);
p13 = gpib(VENDOR, BOARD, ADDR_13); p13.Timeout = timeout_s; fopen(p13);
%%p17 = gpib(VENDOR, BOARD, ADDR_17); p17.Timeout = timeout_s; fopen(p17);

cleanupObj = onCleanup(@() close_all({p12,p13,p17})); %#ok<NASGU>

% Soft setup (won't error if unsupported)
sensor_soft_setup(p12);
sensor_soft_setup(p13);
%%sensor_soft_setup(p17);

% Read once
P12 = sensor_read_dBm(p12) + OFF_12_dB;
P13 = sensor_read_dBm(p13) + OFF_13_dB;
%%P17 = sensor_read_dBm(p17) + OFF_17_dB;

fprintf('P12 = %.2f dBm | P13 = %.2f dBm', P12, P13);

%% ---- helpers ----
function sensor_soft_setup(pwr)
    scpi_try_soft(pwr, {'*RST'});
    scpi_try_soft(pwr, {':UNIT:POW DBM','UNIT:POW DBM',':SENS:UNIT:POW DBM','SENS:UNIT:POW DBM'});
end

function p_dBm = sensor_read_dBm(pwr)
    scpi_try_soft(pwr, {':INIT:IMM','INIT:IMM',':INIT','INIT'});
    p_dBm = scpi_query_num(pwr, {':FETC?','FETC?',':READ?','READ?',':MEAS:POW?','MEAS:POW?',':MEAS?','MEAS?'});
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

function close_all(instCell)
    for k = 1:numel(instCell)
        try
            if ~isempty(instCell{k}) && strcmpi(instCell{k}.Status,'open')
                fclose(instCell{k});
            end
        catch
        end
        try, delete(instCell{k}); catch, end
    end
end