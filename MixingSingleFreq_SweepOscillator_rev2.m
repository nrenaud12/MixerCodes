
 clear; clc;
 
 %% ---- user settings ----
 ADDR   = 15;    % GPIB address of the sweep oscillator
 timeout_s = 10; % seconds
 write_retries = 3;
 write_pause_s = 0.2;
 
 f_GHz = 7.000;  % target frequency
 p_dBm = -10;    % target power
 settle_s = 0.1;
 

%% ---- open signal generator (VISA) ----
resourceName = sprintf('GPIB0::%d::INSTR', ADDR);
sigGen = [];
rfOn = false;
cleanupObj = []; %#ok<NASGU>

sigGen = visadev(resourceName);
sigGen.Timeout = timeout_s;
configureTerminator(sigGen, "LF");
cleanupObj = onCleanup(@() safe_clear(sigGen)); %#ok<NASGU>
 
 %% ---- program 8350B (legacy mnemonics) ----
 try
     write_with_retry(sigGen, 'IP', write_retries, write_pause_s);  % preset
     pause(0.5);
 
     write_with_retry(sigGen, sprintf('CW%.6fGZ', f_GHz), write_retries, write_pause_s);
     write_with_retry(sigGen, sprintf('PL%.3fDB', p_dBm), write_retries, write_pause_s);
     write_with_retry(sigGen, 'RF1', write_retries, write_pause_s);
     rfOn = true;
 
     fprintf('Sweep oscillator set to %.6f GHz at %.1f dBm. RF is ON.\n', f_GHz, p_dBm);
     pause(settle_s);
 catch ME
     warning('Error: %s', ME.message);
 end
 
 %% ---- turn RF off ----
try
    if rfOn && ~isempty(sigGen) && isvalid(sigGen)
        write_with_retry(sigGen, 'RF0', write_retries, write_pause_s);
        fprintf('RF is OFF.\n');
    end
catch ME2
    warning('Could not turn RF OFF: %s', ME2.message);
end
 
 %% ---- helper ----

function safe_clear(inst)
    try
        if ~isempty(inst) && isvalid(inst)
            clear inst;
        end
    catch
    end
end
 
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
