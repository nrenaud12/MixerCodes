%% read_P12_only.m
% One-shot read of power sensor at GPIB address 12 (P12).
clear; clc;

VENDOR = 'KEYSIGHT';
BOARD  = 7;      % <-- GPIB board index
ADDR   = 13;
timeout_s = 3;

OFF_dB = 0;      % +20 if reading a -20 dB coupler port

% Open sensor
pwr = gpib(VENDOR, BOARD, ADDR);
pwr.Timeout = timeout_s;
fopen(pwr);
cleanupObj = onCleanup(@() close_one(pwr)); %#ok<NASGU>

% Soft setup (won't error if unsupported)
scpi_try_soft(pwr, {':UNIT:POW DBM','UNIT:POW DBM',':SENS:UNIT:POW DBM','SENS:UNIT:POW DBM'});

% Read
scpi_try_soft(pwr, {':INIT:IMM','INIT:IMM',':INIT','INIT'});
P12 = scpi_query_num(pwr, {':FETC?','FETC?',':READ?','READ?',':MEAS:POW?','MEAS:POW?',':MEAS?','MEAS?'}) + OFF_dB;

fprintf('P12 = %.2f dBm\n', P12);

%% ---- helpers ----
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
    error('Could not parse numeric response from P12.');
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