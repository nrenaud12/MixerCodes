%% signal_gen_single_test_dual.m
% Single-tone output test for two generator families:
% - Synthesized sweeper (SCPI-style, e.g., HP 8341B)
% - Sweep oscillator (legacy HP-IB style, e.g., HP 8350B)
%
% Select the instrument type with GEN_TYPE and update the command lists
% below if your manual uses different mnemonics.
clear; clc;

%% ---- user settings ----
ADDR   = 15;           % GPIB address of the generator
timeout_s = 3;         % seconds
GEN_TYPE = "synth";    % "synth" (SCPI) or "sweep" (legacy HP-IB)

f_GHz = 1.000;         % target frequency
p_dBm = -10;           % target power (ignored if sweep osc has no level control)
settle_s = 0.1;

%% ---- open signal generator (VISA) ----
T = visadevlist;
gen_rsrc = find_gpib_resource(T, ADDR);
gen = visadev(gen_rsrc);
gen.Timeout = timeout_s;
cleanupObj = onCleanup(@() close_one(gen)); %#ok<NASGU>

idn = safe_idn(gen);
if idn == ""
    fprintf('Signal generator opened (no IDN response).\n');
else
    fprintf('Signal generator IDN: %s\n', idn);
end

%% ---- configure output ----
if GEN_TYPE == "synth"
    % SCPI-style commands (typical for HP 8341B synthesized sweeper)
    src_set_freq_mode_cw(gen, {"FREQ:MODE CW",":FREQ:MODE CW","SOUR:FREQ:MODE CW",":SOUR:FREQ:MODE CW"});
    src_set_freq_Hz_units(gen, f_GHz * 1e9, {
        "FREQ:CW %.6f GHZ","FREQ %.6f GHZ",":FREQ:CW %.6f GHZ",":FREQ %.6f GHZ", ...
        "SOUR:FREQ:CW %.6f GHZ",":SOUR:FREQ:CW %.6f GHZ","SOUR:FREQ %.6f GHZ",":SOUR:FREQ %.6f GHZ", ...
        "FREQ:CW %.3f MHZ","FREQ %.3f MHZ","FREQ:CW %d HZ","FREQ %d HZ",":FREQ:CW %d",":FREQ %d", ...
        "SOUR:FREQ:CW %d",":SOUR:FREQ:CW %d","SOUR:FREQ %d",":SOUR:FREQ %d"
    });
    src_set_power_unit_dbm(gen, {":POW:UNIT DBM","POW:UNIT DBM",":SOUR:POW:UNIT DBM","SOUR:POW:UNIT DBM"});
    src_set_power_dBm(gen, p_dBm, {
        ":POW %.3f","POW %.3f",":POW:LEV %.3f","POW:LEV %.3f", ...
        ":SOUR:POW %.3f","SOUR:POW %.3f",":SOUR:POW:LEV %.3f","SOUR:POW:LEV %.3f"
    });
    src_output_on(gen, true, {":OUTP ON","OUTP ON",":OUTP:STAT ON","OUTP:STAT ON"});
else
    % Legacy HP-IB style commands (typical for HP 8350B sweep oscillator)
    % Update these mnemonics to match your instrument manual if needed.
    src_set_freq_mode_cw(gen, {"CW",":CW","FREQ:MODE CW","FREQ:MODE FIX"});
    src_set_freq_Hz_units(gen, f_GHz * 1e9, {
        "FR %d","FREQ %d","FREQ:CW %d","FREQ %d HZ","FREQ %.3f MHZ","FREQ %.6f GHZ"
    });
    src_set_power_dBm(gen, p_dBm, {"PL %.3f","POW %.3f","LEV %.3f"});
    src_output_on(gen, true, {"ON","OUTP ON","RF ON","OUTP:STAT ON"});
end

pause(settle_s);
fprintf('Set: f=%.6f GHz, P=%.1f dBm. Exiting now.\n', f_GHz, p_dBm);

%% ================= helpers =================
function out = safe_idn(dev)
    out = "";
    try
        writeline(dev, '*IDN?');
        out = strtrim(readline(dev));
    catch
    end
end

function close_one(inst)
    try
        if ~isempty(inst)
            clear inst;
        end
    catch
    end
end

function ok = scpi_try_soft(inst, cmdList)
    ok = false;
    if ischar(cmdList), cmdList = {cmdList}; end
    for i = 1:numel(cmdList)
        try
            writeline(inst, cmdList{i});
            ok = true;
            return;
        catch
        end
    end
end

function src_output_on(dev, onoff, cmdList)
    if onoff
        scpi_try_soft(dev, cmdList);
    else
        scpi_try_soft(dev, {":OUTP OFF","OUTP OFF",":OUTP:STAT OFF","OUTP:STAT OFF","OFF","RF OFF"});
    end
end

function src_set_freq_mode_cw(dev, cmdList)
    scpi_try_soft(dev, cmdList);
end

function src_set_power_unit_dbm(dev, cmdList)
    scpi_try_soft(dev, cmdList);
end

function src_set_power_dBm(dev, p_dBm, cmdList)
    cmdList = string(cmdList);
    for i = 1:numel(cmdList)
        cmdList(i) = sprintf(cmdList(i), p_dBm);
    end
    scpi_try_soft(dev, cellstr(cmdList));
end

function src_set_freq_Hz_units(dev, fHz, cmdList)
    fGHz = fHz/1e9; fMHz = fHz/1e6; fInt = round(fHz);
    cmdList = string(cmdList);
    for i = 1:numel(cmdList)
        if contains(cmdList(i), "GHZ")
            cmdList(i) = sprintf(cmdList(i), fGHz);
        elseif contains(cmdList(i), "MHZ")
            cmdList(i) = sprintf(cmdList(i), fMHz);
        else
            cmdList(i) = sprintf(cmdList(i), fInt);
        end
    end
    scpi_try_soft(dev, cellstr(cmdList));
end

function rsrc = find_gpib_resource(T, addr)
    names = string(T.ResourceName);
    aliases = string(T.Alias);
    addr_str = "::" + string(addr) + "::INSTR";
    hit = contains(names, addr_str);
    if ~any(hit)
        hit = contains(aliases, "GPIB") & contains(aliases, string(addr));
    end
    if ~any(hit)
        rsrc = "GPIB0" + addr_str;
        warning("No VISA resource match found for GPIB address %d. Falling back to %s.", addr, rsrc);
        return;
    end
    rsrc = names(find(hit,1,'first'));
end
