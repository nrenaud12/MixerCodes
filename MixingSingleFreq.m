%% MixingSingleFreq_visadev.m
% One measurement: RF=GPIB::15, LO=GPIB::19, IF sensor=P12=GPIB::12
clear; clc;

%% ---- user settings ----
ADDR_RF  = 15;
ADDR_LO  = 19;
ADDR_P = 13;

fRF_GHz = 6.000;      % pick one point
IF_GHz  = 1.000;
side    = "high";     % "high" => fLO=fRF+IF, "low" => fLO=fRF-IF

PRF_dBm = -10;
PLO_dBm = 10;

settle_s = 0.3;
invalid_abs_threshold = 1e20;

%% ---- discover VISA resources ----
T = visadevlist;
rf_rsrc  = find_gpib_resource(T, ADDR_RF);
lo_rsrc  = find_gpib_resource(T, ADDR_LO);
p12_rsrc = find_gpib_resource(T, ADDR_P);

fprintf("RF  resource : %s\n", rf_rsrc);
fprintf("LO  resource : %s\n", lo_rsrc);
fprintf("P12 resource : %s\n", p12_rsrc);

%% ---- open devices ----
rf  = visadev(rf_rsrc);
lo  = visadev(lo_rsrc);
p12 = visadev(p12_rsrc);

rf.Timeout  = 3;
lo.Timeout  = 3;
p12.Timeout = 3;

% Optional IDN (won't crash if unsupported)
disp("RF  IDN: " + safe_idn(rf));
disp("LO  IDN: " + safe_idn(lo));
disp("P12 IDN: " + safe_idn(p12));

%% ---- compute freqs ----
fRF_Hz = fRF_GHz*1e9;
IF_Hz  = IF_GHz *1e9;
if strcmpi(side,"high")
    fLO_Hz = fRF_Hz + IF_Hz;
else
    fLO_Hz = fRF_Hz - IF_Hz;
end
fprintf("Target: fRF=%.6f GHz | fLO=%.6f GHz | IF=%.3f GHz (%s-side)\n", ...
    fRF_Hz/1e9, fLO_Hz/1e9, IF_Hz/1e9, side);

%% ---- configure sources (no *RST) ----
src_set_power_dBm(rf, PRF_dBm, "RF");
src_set_power_dBm(lo, PLO_dBm, "LO");
src_output_on(rf, true, "RF");
src_output_on(lo, true, "LO");

src_set_freq_Hz_units(rf, fRF_Hz, "RF");
src_set_freq_Hz_units(lo, fLO_Hz, "LO");

pause(settle_s);

%% ---- configure P12 (no hard reset) ----
scpi_try_soft(p12, [":UNIT:POW DBM","UNIT:POW DBM",":SENS:UNIT:POW DBM","SENS:UNIT:POW DBM"]);
% Tell sensor it is measuring IF (helps cal correction; safe if unsupported)
pwr_set_freq_Hz_soft(p12, IF_Hz);

%% ---- one read ----
[p_dBm, raw] = pwr_read_dBm_with_raw(p12);

if ~isfinite(p_dBm) || abs(p_dBm) > invalid_abs_threshold
    fprintf("P12(IF) = INVALID | raw=\%s\\n", raw);
else
    fprintf("P12(IF) = %.2f dBm\n", p_dBm);
end

%% ================= helpers =================

function rsrc = find_gpib_resource(T, addr)
    % Find something like "GPIB0::15::INSTR" in visadevlist
    names = string(T.ResourceName);
    pat = "GPIB\d+::" + string(addr) + "::INSTR";
    hit = ~cellfun(@isempty, regexp(cellstr(names), pat, 'once'));
    if ~any(hit)
        error("No VISA resource found for GPIB address %d. Run visadevlist and verify it appears.", addr);
    end
    rsrc = names(find(hit,1,'first'));
end

function out = safe_idn(dev)
    out = "(no response)";
    try
        writeline(dev, "*IDN?");
        out = strtrim(readline(dev));
    catch
    end
end

function scpi_try_soft(dev, cmdList)
    if ischar(cmdList) || isstring(cmdList)
        cmdList = string(cmdList);
    end
    for i = 1:numel(cmdList)
        try
            writeline(dev, cmdList(i));
            return;
        catch
        end
    end
end

function err = syst_err_soft(dev, tag)
    err = "";
    try
        writeline(dev, "SYST:ERR?");
        err = strtrim(readline(dev));
        if err ~= "" && ~startsWith(err,"+0") && ~startsWith(err,"0")
            fprintf("[%s] SYST:ERR? -> %s\n", tag, err);
        end
    catch
    end
end

function src_output_on(dev, onoff, tag)
    if onoff
        scpi_try_soft(dev, [":OUTP ON","OUTP ON",":OUTP:STAT ON","OUTP:STAT ON"]);
    else
        scpi_try_soft(dev, [":OUTP OFF","OUTP OFF",":OUTP:STAT OFF","OUTP:STAT OFF"]);
    end
    syst_err_soft(dev, tag);
end

function src_set_power_dBm(dev, p_dBm, tag)
    scpi_try_soft(dev, [
        sprintf(":POW %.3f dBm", p_dBm)
        sprintf("POW %.3f dBm", p_dBm)
        sprintf(":POW:LEV %.3f dBm", p_dBm)
        sprintf("POW:LEV %.3f dBm", p_dBm)
    ]);
    syst_err_soft(dev, tag);
end

function src_set_freq_Hz_units(dev, fHz, tag)
    % Avoid scientific notation; try unit formats first
    fGHz = fHz/1e9; fMHz = fHz/1e6; fInt = round(fHz);
    cmdList = [
        sprintf("FREQ:CW %.6f GHZ", fGHz)
        sprintf("FREQ %.6f GHZ",    fGHz)
        sprintf(":FREQ:CW %.6f GHZ", fGHz)
        sprintf(":FREQ %.6f GHZ",    fGHz)
        sprintf("FREQ:CW %.3f MHZ", fMHz)
        sprintf("FREQ %.3f MHZ",    fMHz)
        sprintf("FREQ:CW %d HZ",    fInt)
        sprintf("FREQ %d HZ",       fInt)
        sprintf(":FREQ:CW %d",      fInt)
        sprintf(":FREQ %d",         fInt)
    ];
    for i = 1:numel(cmdList)
        try
            writeline(dev, cmdList(i));
            pause(0.02);
            e = syst_err_soft(dev, tag);
            if e=="" || startsWith(e,"+0") || startsWith(e,"0")
                return;
            end
        catch
        end
    end
end

function pwr_set_freq_Hz_soft(dev, fHz)
    fInt = round(fHz);
    scpi_try_soft(dev, [
        sprintf(":SENS:FREQ %d", fInt)
        sprintf("SENS:FREQ %d",  fInt)
        sprintf(":FREQ %d",      fInt)
        sprintf("FREQ %d",       fInt)
    ]);
end

function [p_dBm, raw] = pwr_read_dBm_with_raw(dev)
    scpi_try_soft(dev, [":INIT:IMM","INIT:IMM",":INIT","INIT"]);
    cmdList = [":FETC?","FETC?",":READ?","READ?",":MEAS:POW?","MEAS:POW?",":MEAS?","MEAS?"];
    raw = "";
    for i = 1:numel(cmdList)
        try
            writeline(dev, cmdList(i));
            raw = strtrim(readline(dev));
            break;
        catch
        end
    end
    tmp = sscanf(raw, "%f", 1);
    if isempty(tmp) || isnan(tmp), p_dBm = NaN; else, p_dBm = tmp; end
end
