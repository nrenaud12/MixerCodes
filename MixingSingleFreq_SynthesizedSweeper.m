% Define parameters
gpibAddress = 19; 
frequency_GHz = 8;
power_dBm = 10;

sigGen = visadev(sprintf('GPIB0::%d::INSTR', gpibAddress));

try
    % 1. Preset the instrument
    writeline(sigGen, 'IP'); 
    pause(0.5);
    
    % 2. SET FREQUENCY (CW mode)
    writeline(sigGen, sprintf('CW%fGZ', frequency_GHz));

    % 3. SET POWER LEVEL
    writeline(sigGen, sprintf('PL%fDB', power_dBm));
    
    % 4. ENABLE RF OUTPUT
    writeline(sigGen, 'RF1'); 
    
    fprintf('Signal Generator set to %g GHz at %g dBm. RF is ON.\n', ...
            frequency_GHz, power_dBm);

    % ---- Do whatever measurement you want here ----
    pause(5);  % keep on for 2 seconds

catch ME
    warning('Error: %s', ME.message);
end

% 5. TURN OFF RF OUTPUT (always try, even if an error occurred above)
try
    writeline(sigGen, 'RF0');     % RF OFF
    % Optional: return to local control (may be ignored depending on model)
    % writeline(sigGen, 'LOCAL');
    fprintf('RF is OFF.\n');
catch ME2
    warning('Could not turn RF OFF: %s', ME2.message);
end

clear sigGen;
