% --- suppress warnings for this script only ---
warnState = warning('off','all');
cleanupWarn = onCleanup(@() warning(warnState)); %#ok<NASGU>


%% gpib_scan.m
clear; clc;

VENDOR = 'KEYSIGHT';
BOARD  = 7;          % working board
to = 3;              % short timeout so scan is quick

fprintf('Scanning GPIB board %d...\n', BOARD);

for addr = 0:20
    v = [];
    try
        v = gpib(VENDOR, BOARD, addr);
        v.Timeout = to;
        fopen(v);

        % Try IDN 
        fprintf(v, '*IDN?');
        idn = strtrim(fscanf(v));

        fclose(v); delete(v);

        if ~isempty(idn)
            fprintf('ADDR %2d : %s\n', addr, idn);
        else
            fprintf('ADDR %2d : opened, no IDN\n', addr);
        end

    catch
        try, if ~isempty(v) && strcmpi(v.Status,'open'), fclose(v); end, catch, end
        try, delete(v); catch, end
    end
end