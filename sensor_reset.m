%% power_sensor_reset.m
% Power-cycle/reset power sensor via GPIB (close/reopen + soft reset).
clear; clc;

%% ---- user settings ----
VENDOR = 'KEYSIGHT';
BOARD = 7;
SENSOR_ADDR = 12;
SENSOR_TIMEOUT_S = 5;

%% ---- open instrument ----
pwr = [];
cleanupPwr = [];

try
    pwr = gpib(VENDOR, BOARD, SENSOR_ADDR);
    pwr.Timeout = SENSOR_TIMEOUT_S;
    fopen(pwr);
    cleanupPwr = onCleanup(@() close_one(pwr));

    % Try soft reset + clear; ignore if unsupported.
    scpi_try_soft(pwr, {'*RST', '*CLS'});
    pause(0.5);

    % Close and reopen the session to simulate power-cycle for the bus.
    fclose(pwr);
    pause(0.5);
    fopen(pwr);
    pause(0.5);

    % Re-apply unit setting (safe if unsupported).
    scpi_try_soft(pwr, {':UNIT:POW DBM','UNIT:POW DBM',':SENS:UNIT:POW DBM','SENS:UNIT:POW DBM'});

    fprintf('Power sensor at GPIB %d reset/reopened.\n', SENSOR_ADDR);
catch ME
    warning('Power sensor reset failed: %s', ME.message);
end

%% ---- helpers ----
function scpi_try_soft(inst, cmdList)
    if ischar(cmdList), cmdList = {cmdList}; end
    for i = 1:numel(cmdList)
        try, fprintf(inst, cmdList{i}); return; catch, end
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
