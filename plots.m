%% plot_all_mixer_sweeps_CL.m
clear; clc; close all;

P_IN_RF_dBm = -10;     % RF input power
OFF_dB = 0;            % offset for cabling and coupler

files = dir('mixer_conversion_loss_sweep_*ghz_*dBm.csv');
if isempty(files)
    error('No files found');
end

G = struct();

for k = 1:numel(files)
    fname = files(k).name;

    tok = regexp(fname, '_([0-9]+)ghz_([0-9]+)dBm\.csv$', 'tokens', 'once');
    if isempty(tok), continue; end
    fGHz  = str2double(tok{1});
    p_dBm = str2double(tok{2});

    T = readtable(fname, 'PreserveVariableNames', true);
    RF_GHz = T.RF_GHz;

    % Conversion loss
    CL_dB = P_IN_RF_dBm - T.MeasuredPower_dBm + OFF_dB;   

    % Clean/sort
    good = isfinite(RF_GHz) & isfinite(CL_dB);
    x = RF_GHz(good);
    y = CL_dB(good);
    [x, idx] = sort(x); y = y(idx);

    key = sprintf('f%d', fGHz);
    if ~isfield(G,key), G.(key) = struct('p',{},'x',{},'y',{}); end
    G.(key)(end+1) = struct('p',p_dBm,'x',x,'y',y); %#ok<SAGROW>
end

% Plot power per IF 
keys = fieldnames(G);
for i = 1:numel(keys)
    arr = G.(keys{i});
    [~, sidx] = sort([arr.p]); arr = arr(sidx);

    figure('Name', keys{i});
    hold on; grid on;
    for j = 1:numel(arr)
        plot(arr(j).x, arr(j).y, 'DisplayName', sprintf('%d dBm LO', arr(j).p));
    end
    xlabel('RF Frequency(GHz)');
    ylabel('Conversion Loss (dB)');
    title(sprintf('Conversion Loss (RF = %.1f dBm,IF = %s GHz)', ...
        P_IN_RF_dBm, keys{i}(2:end)));
    legend('Location','best');
end

% ---------- SAVE FIGURES ----------
outDir = pwd;
figs = findall(0,'Type','figure');

for k = 1:numel(figs)
    figure(figs(k));  
    name = get(figs(k),'Name');
    if isempty(name)
        name = sprintf('Figure%02d', k);
    end
    name = regexprep(name,'[^\w- ]','');
    name = strrep(strtrim(name),' ','');

    saveas(figs(k), fullfile(outDir, [name '.png']));
end
fprintf('Saved %d figure(s) to: %s\n', numel(figs), outDir);