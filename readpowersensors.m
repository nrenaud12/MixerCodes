%% read_power_sensors_only_clean.m
clear; clc;

VENDOR = 'KEYSIGHT';
BOARD  = 7;     
ADDR_1 = 12;
ADDR_2 = 13;
ADDR_3 = 17;

timeout_s = 30;

OFF_1_dB = 0;
OFF_2_dB = 0;
OFF_3_dB = 0;

Nreads = 50;
dt_s   = 0.25;

% Open
pwr1 = gpib(VENDOR, BOARD, ADDR_1); pwr1.Timeout = timeout_s; fopen(pwr1);
pwr2 = gpib(VENDOR, BOARD, ADDR_2); pwr2.Timeout = timeout_s; fopen(pwr2);
pwr3 = gpib(VENDOR, BOARD, ADDR_3); pwr3.Timeout = timeout_s; fopen(pwr3);

cleanupObj = onCleanup(@() close_all({pwr1,pwr2,pwr3})); %#ok<NASGU>

% Soft setup
pwr_sensor_setup_soft(pwr1);
pwr_sensor_setup_soft(pwr2);
pwr_sensor_setup_soft(pwr3);

% Read loop
t_s = nan(Nreads,1);
p1  = nan(Nreads,1);
p2  = nan(Nreads,1);
p3  = nan(Nreads,1);

t0 = tic;
for k = 1:Nreads
    t_s(k) = toc(t0);

    p1(k) = pwr_read_dBm(pwr1) + OFF_1_dB;
    p2(k) = pwr_read_dBm(pwr2) + OFF_2_dB;
    p3(k) = pwr_read_dBm(pwr3) + OFF_3_dB;

    fprintf('k=%3d | t=%.2f s | P12=%.2f dBm | P13=%.2f dBm | P17=%.2f dBm\n', ...
        k, t_s(k), p1(k), p2(k), p3(k));

    pause(dt_s);
end

% Plots
figure; plot(t_s, p1, '-o'); grid on; xlabel('Time (s)'); ylabel('Power (dBm)'); title('PWR @ 12');
figure; plot(t_s, p2, '-o'); grid on; xlabel('Time (s)'); ylabel('Power (dBm)'); title('PWR @ 13');
figure; plot(t_s, p3, '-o'); grid on; xlabel('Time (s)'); ylabel('Power (dBm)'); title('PWR @ 17');

%% ---- helpers ----
function pwr_sensor_setup_soft(pwr)
    scpi_try_soft(pwr, { '*RST' });
    scpi_try_soft(pwr, { ':UNIT:POW DBM', 'UNIT:POW DBM', ':SENS:UNIT:POW DBM', 'SENS:UNIT:POW DBM' });
end

function p_dBm = pwr_read_dBm(pwr)
    scpi_try_soft(pwr, { ':INIT:IMM', 'INIT:IMM', ':INIT', 'INIT' });
    p_dBm = scpi_query_num(pwr, {':FETC?','FETC?',':READ?','READ?',':MEAS:POW?','MEAS:POW?',':MEAS?','MEAS?'});
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
            tmp = sscanf(s, '%f', 1);  % handles "-12.3 dBm"
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
