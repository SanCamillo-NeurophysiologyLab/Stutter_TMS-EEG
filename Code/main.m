%% Clear everythingclear all;
close all;
clc

%% Parameters
bidsFolder = '/mnt/raid/atonin/balbuzie/TMS-EEG/Data/bids_export';
protocolName = 'Stutter_TMSEEG_2';
atlasFolder = '/mnt/raid/atonin/balbuzie/TMS-EEG/Data/atlas';
atlasFile = 'scout_StutterStudy_20.mat';

win_baseline =  [-0.200, -0.010];
win_data =      [ 0.020,  0.500];

%% Setup brainstorm
if ~brainstorm('status')
    brainstorm nogui
end

input_delete_protocol = input(sprintf("Delete protocol %s? Y/N [N]: ",protocolName),"s");
switch upper(input_delete_protocol)
    case {"Y","YES"}
        delete_protocol = 1;
    otherwise
        delete_protocol = 0;
end

if delete_protocol
    gui_brainstorm('DeleteProtocol', protocolName);
else
    input_delete_raw = input("Delete raw data? Y/N [N]: ","s");
    switch upper(input_delete_raw)
        case {"Y","YES"}
            delete_raw = 1;
        otherwise
            delete_raw = 0;
    end
    if delete_raw
        sFiles = bst_process('CallProcess', 'process_select_files_data', [], []);
        % Process: Delete selected files
        sFiles = bst_process('CallProcess', 'process_delete', sFiles, [], ...
            'target', 1);  % Delete selected files
    end
    input_delete_source = input("Delete source data? Y/N [N]: ","s");
    switch upper(input_delete_source)
        case {"Y","YES"}
            delete_source = 1;
        otherwise
            delete_source = 0;
    end
    if delete_source
        sFiles = bst_process('CallProcess', 'process_select_files_results', [], []);
        % Process: Delete selected files
        sFiles = bst_process('CallProcess', 'process_delete', sFiles, [], ...
            'target', 1);  % Delete selected files
    end
    input_delete_kernel = input("Delete kernel ROI? Y/N [N]: ","s");
    switch upper(input_delete_kernel)
        case {"Y","YES"}
            delete_kernelroi = 1;
        otherwise
            delete_kernelroi = 0;
    end
    if delete_kernelroi
        sFiles = bst_process('CallProcess', 'process_select_files_matrix', [], []);
        % Process: Delete selected files
        sFiles = bst_process('CallProcess', 'process_delete', sFiles, [], ...
            'target', 1);  % Delete selected files
    end
    input_delete_tf = input("Delete time frequency? Y/N [N]: ","s");
    switch upper(input_delete_tf)
        case {"Y","YES"}
            delete_tf = 1;
        otherwise
            delete_tf  = 0;
    end
    if delete_tf
        sFiles = bst_process('CallProcess', 'process_select_files_timefreq', [], []);
        % Process: Delete selected files
        sFiles = bst_process('CallProcess', 'process_delete', sFiles, [], ...
            'target', 1);  % Delete selected files
    end
end
%% Import data
% Load protocol
iProtocol = bst_get('Protocol', protocolName);
if isempty(iProtocol)
    warning("Protocol %s do not exist\n", protocolName)
    % Creating new protocol
    fprintf("Creating new protocol %s", protocolName)
    gui_brainstorm('CreateProtocol', protocolName, 0, 0)
    iProtocol = bst_get('Protocol', protocolName);
end

% Select the current protocol
fprintf("Selecting protocol %s\n", protocolName)
gui_brainstorm('SetCurrentProtocol', iProtocol)
protocolInfo = bst_get('ProtocolInfo');

% Import data
protocolSubjects = bst_get('ProtocolSubjects');
numSubjects = length(protocolSubjects.Subject);
if numSubjects == 0
    warning("Protocol %s has no data\n", protocolName)
    % Process: Import BIDS dataset
    fprintf("Loading BIDS dataset from %s\n", bidsFolder)
    bst_process('CallProcess', 'process_import_bids', [], [], ...
        'bidsdir',       {bidsFolder, 'BIDS'});
end

protocolSubjects = bst_get('ProtocolSubjects');
numSubjects = length(protocolSubjects.Subject);
protocolStudies = bst_get('ProtocolStudies');
numStudies = length(protocolStudies.Study);
fprintf("There are %d studies from %d subjects\n", numStudies, numSubjects);

% Process: Select data files
sdataAll = bst_process('CallProcess', 'process_select_files_data', [], []);
fprintf("There are %d datasets\n", length(sdataAll));

%% Head model
% OpenMEEG BEM 8002 vertices as forward solution and ICBM152 template
% anatomy

% Process: Project electrodes on scalp
disp("Projecting electrodes on the scalp")
sdataAll = bst_process('CallProcess', 'process_select_files_data', [], []);
sProj = bst_process('CallProcess', 'process_channel_project', sdataAll, [], ...
    'sensortypes', 'EEG');

input_common_head = input("Use a common head model? Y/N [Y]: ","s");
switch upper(input_common_head)
    case {"N","NO"}
        commonHeadModel = 0;
    otherwise
        commonHeadModel = 1;
end

% if common head model calculate head model only for first dataset
if commonHeadModel
    dataSubList = sProj(1);
else
    dataSubList = sProj;
end

for iData = 1:length(dataSubList)
    fprintf("Computing head model for %s\n", dataSubList(iData).SubjectName)
    % Process: Compute head model
    sFiles = bst_process('CallProcess', 'process_headmodel', dataSubList(iData), [], ...
        'sourcespace', 1, ...  % Cortex surface
        'eeg',         3, ...  % OpenMEEG BEM
        'openmeeg',    struct(...
             'BemSelect',    [1, 1, 1], ...
             'BemCond',      [1, 0.0125, 1], ...
             'BemNames',     {{'Scalp', 'Skull', 'Brain'}}, ...
             'BemFiles',     {{}}, ...
             'isAdjoint',    0, ...
             'isAdaptative', 1, ...
             'isSplit',      0, ...
             'SplitLength',  4000));
end

if commonHeadModel
    % Copy the head model to all the subjects
    fprintf("Copying the head model to all the subjects\n")
    headModel = bst_get('HeadModelForStudy', dataSubList.iStudy);

    % sFiles = db_set_headmodel(headModel.FileName, 'AllSubjects');

    % We cannot use basic bs function because it does not copy the
    % headmodel since there are already raw data
    % So we do it with a custom function!

    sFiles = db_force_headmodel(headModel.FileName, 'AllSubjects'); 

end

%% Noise covariance matrix

sdataAll = bst_process('CallProcess', 'process_select_files_data', [], []);

%%%
%%% Alternativa: provare con identity matrix
%%%

% Process: Compute covariance (noise or data)
sCovariance = bst_process('CallProcess', 'process_noisecov', sdataAll, [], ...
    'baseline',       win_baseline, ...
    'datatimewindow', win_data, ...
    'sensortypes',    'EEG', ...
    'target',         1, ...  % Noise covariance     (covariance over baseline time window)
    'dcoffset',       1);  % Block by block, to avoid effects of slow shifts in data
    
% 
% data_conditions = {sdataAll.Condition};
% 
% for ii = 1:length(data_conditions)
%     condition = data_conditions{ii};
%     % if it is not baseline skip
%     if endsWith(condition, data_end_pattern)
%         continue
%     end
%     % otherwise it is a baseline
%     idx_bl = ii;
%     bl_study = sdataAll(idx_bl).iStudy;
% 
%     % Process: Compute covariance (noise or data)
%     sCovariance = bst_process('CallProcess', 'process_noisecov', sdataAll(idx_bl), [], ...
%         'baseline',       [], ...
%         'sensortypes',    'EEG', ...
%         'target',         1, ...  % Noise covariance     (covariance over baseline time window)
%         'dcoffset',       1);  % Block by block, to avoid effects of slow shifts in data
%     
%     % Then find the corresponding dataset
%     base_name = extractBefore(condition, baseline_end_pattern);
%     condition_data = [base_name data_end_pattern];
% 
%     idx_data = find(strcmp(data_conditions, condition_data));
%     if isempty(idx_data)
%         % This should never happen
%         warning("File %s not found!", condition_data)
%     end
%     data_study = sdataAll(idx_data).iStudy;
% 
%     % And copy the noise covariance matrix
%     db_set_noisecov(bl_study, data_study, 0, 1)
% end

%% Source
sdataAll = bst_process('CallProcess', 'process_select_files_data', [], []);

% Process: Compute sources [2018]
sSource = bst_process('CallProcess', 'process_inverse_2018', sdataAll, [], ...
    'output',  2, ...  % Kernel only: one per file
    'inverse', struct(...
         'Comment',        'sLORETA: EEG', ...
         'InverseMethod',  'minnorm', ...
         'InverseMeasure', 'sloreta', ...
         'SourceOrient',   {{'free'}}, ...
         'Loose',          0.2, ...
         'UseDepth',       0, ...
         'WeightExp',      0.5, ...
         'WeightLimit',    10, ...
         'NoiseMethod',    'reg', ...
         'NoiseReg',       0.1, ...
         'SnrMethod',      'fixed', ...
         'SnrRms',         1e-06, ...
         'SnrFixed',       3, ...
         'ComputeKernel',  1, ...
         'DataTypes',      {{'EEG'}}));

%% Load Atlas
% Load surface
[sScouts, sSurf, iSurf] = panel_scout('GetScouts');
% Check atlas name
atlas = load(fullfile(atlasFolder, atlasFile));

% Check if atlas is already loaded
[~, iAtlas] = ismember(atlas.Name, {sSurf.Atlas.Name});

if iAtlas == 0 % not loaded
    loadAtlas = 1;
else
    surfScouts = sSurf.Atlas(iAtlas).Scouts;
    atlasScouts = atlas.Scouts;
    % remove handlers for comparison
    surfScouts = rmfield(surfScouts, 'Handles');
    atlasScouts = rmfield(atlasScouts, 'Handles');
    if isequaln(surfScouts, atlasScouts)
        % already loaded
        loadAtlas = 0;
    else
        warning("An Atlas called %s is already loaded, but it is different. We load a new one.", atlas.Name)
        loadAtlas = 1;
    end
end

if loadAtlas
    [atlas, Message] = import_label(sSurf.FileName, fullfile(atlasFolder, atlasFile));
end


%% Extract time series at ROI level
sdataAll = bst_process('CallProcess', 'process_select_files_results', [], []);

% Process: Scout time series: temporal L temporal R inferiorParietal L inferiorParietal R central L central R posteriorFrontal L posteriorFrontal R anteriorFrontal L anteriorFrontal R inferiorFrontal L inferiorFrontal R
sFiles = bst_process('CallProcess', 'process_extract_scout', sdataAll, [], ...
    'scouts',         {atlas.Name, {atlas.Scouts.Label}}, ... % load all scouts
    'scoutfunc',      'pca', ...  % PCA
    'pcaedit',        struct(...
         'Method',         'pcai', ...
         'Baseline',       win_baseline, ...
         'DataTimeWindow', win_data, ...
         'RemoveDcOffset', 'none'));

%% TF decomposition
sdataAll = bst_process('CallProcess', 'process_select_files_matrix', [], []);

% Process: Time-frequency (Morlet wavelets)
sFiles = bst_process('CallProcess', 'process_timefreq', sdataAll, [], ...
    'edit',          struct(...
         'Comment',         'Power,0.5-100Hz', ...
         'TimeBands',       [], ...
         'Freqs',           [0.5:0.5:100], ...
         'MorletFc',        1, ...
         'MorletFwhmTc',    3, ...
         'ClusterFuncTime', 'none', ...
         'Measure',         'power', ...
         'Output',          'all', ...
         'SaveKernel',      0), ...
    'normalize2020', 0, ...
    'normalize',     'none');  % None: Save non-standardized time-frequency maps

%% Event related sync/desync
sDataTF = bst_process('CallProcess', 'process_select_files_timefreq', [], []);

sFiles = bst_process('CallProcess', 'process_baseline_norm', sDataTF, [], ...`
    'baseline',  win_baseline, ...
    'method',    'ersd', ...  % Event-related perturbation (ERS/ERD):    x_std = (x - &mu;) / &mu; * 100
    'overwrite', 0);

%% Group in bands
sDataTF = bst_process('CallProcess', 'process_select_files_timefreq', [], []);
sDataTFersd = sDataTF(contains({sDataTF.Comment},"ersd"));

% Process: Group in time or frequency bands
sFiles = bst_process('CallProcess', 'process_tf_bands', sDataTFersd, [], ...
    'isfreqbands', 1, ...
    'freqbands',   {'delta', '0.5, 4', 'mean'; 'theta', '4.5, 7.5', 'mean'; 'alpha1', '8, 10', 'mean'; 'alpha2', '10.5, 12', 'mean'; 'beta1', '12.5, 16', 'mean'; 'beta2', '16.5, 21', 'mean'; 'beta3', '21.5, 30', 'mean'; 'gamma1', '30.5, 70', 'mean'; 'gamma2', '70.5, 100', 'mean'}, ...
    'istimebands', 0, ...
    'timebands',   '', ...
    'overwrite',   0);

%% Extract bands/roi-timeframe matrix
sDataTF = bst_process('CallProcess', 'process_select_files_timefreq', [], []);
sDataTFbands = sDataTF(contains({sDataTF.Comment},"tfbands"));

stutter_sDataTFbands = sDataTFbands(startsWith({sDataTFbands.SubjectName}, "sub-S1"));
fluent_sDataTFbands = sDataTFbands(startsWith({sDataTFbands.SubjectName}, "sub-S2"));

% Extract stutter data
stutterData = [];

for ii = 1:length(stutter_sDataTFbands)
    subj = stutter_sDataTFbands(ii).SubjectName;
    run = "";
    if contains(stutter_sDataTFbands(ii).Condition,'sham')
        run = 'sham';
    elseif contains(stutter_sDataTFbands(ii).Condition,'tms')
        run = 'tms';
    end
    export_matlab(stutter_sDataTFbands(ii).FileName, "tmpData");
    stutterData(ii).subj = subj;
    stutterData(ii).run = run;
    stutterData(ii).data = tmpData.TF;
end

% Extract fluent data
fluentData = [];

for ii = 1:length(fluent_sDataTFbands)
    subj = fluent_sDataTFbands(ii).SubjectName;
    run = "";
    if contains(fluent_sDataTFbands(ii).Condition,'sham')
        run = 'sham';
    elseif contains(fluent_sDataTFbands(ii).Condition,'tms')
        run = 'tms';
    end
    export_matlab(fluent_sDataTFbands(ii).FileName, "tmpData");
    fluentData(ii).subj = subj;
    fluentData(ii).run = run;
    fluentData(ii).data = tmpData.TF;
end

% Sort the two structs
st_table = struct2table(stutterData);
st_table = sortrows(st_table, ["subj", "run"]);
stutterData = table2struct(st_table);

fl_table = struct2table(fluentData);
fl_table = sortrows(fl_table, ["subj", "run"]);
fluentData = table2struct(fl_table);

%% Group data for analysis

rois = extractBefore(tmpData.RowNames, "@");
bands = tmpData.Freqs(:,1);
times = tmpData.Time;

stutterShamData = stutterData(contains({stutterData.run},"sham"));
stutterTmsData = stutterData(contains({stutterData.run},"tms"));
fluentShamData = fluentData(contains({fluentData.run},"sham"));
fluentTmsData = fluentData(contains({fluentData.run},"tms"));

allData = [];

for iRoi = 1:length(rois)
    for iBand = 1:length(bands)
        stutter_sham_data_tmp = [];
        stutter_tms_data_tmp = [];
        for iStSham = 1:length(stutterShamData)
            stutter_sham_data_tmp(iStSham,:) = stutterShamData(iStSham).data(iRoi, :, iBand);
        end
        for iStTms = 1:length(stutterTmsData)
            stutter_tms_data_tmp(iStTms,:) = stutterTmsData(iStTms).data(iRoi, :, iBand);
        end
        fluent_sham_data_tmp = [];
        fluent_tms_data_tmp = [];
        for iFlSham = 1:length(fluentShamData)
            fluent_sham_data_tmp(iFlSham,:) = fluentShamData(iFlSham).data(iRoi, :, iBand);
        end
        for iFlTms = 1:length(fluentTmsData)
            fluent_tms_data_tmp(iFlTms,:) = fluentTmsData(iFlTms).data(iRoi, :, iBand);
        end
        % Create structure
        RoiBandData.roi = rois{iRoi};
        RoiBandData.band = bands{iBand};
        RoiBandData.st_sham = stutter_sham_data_tmp;
        RoiBandData.st_tms = stutter_tms_data_tmp;
        RoiBandData.st_diff = stutter_tms_data_tmp - stutter_sham_data_tmp;
        RoiBandData.fl_sham = fluent_sham_data_tmp;
        RoiBandData.fl_tms = fluent_tms_data_tmp;
        RoiBandData.fl_diff = fluent_tms_data_tmp - fluent_sham_data_tmp;

        allData = [allData; RoiBandData];
    end
end

%% Stat
for iData = 1:length(allData)
    [st_h,st_p,st_ci,st_stats] = ttest(allData(iData).st_sham,allData(iData).st_tms,'tail','both');
    [fl_h,fl_p,fl_ci,fl_stats] = ttest(allData(iData).fl_sham,allData(iData).fl_tms,'tail','both');
    [tot_h,tot_p,tot_ci,tot_stats] = ttest2(allData(iData).st_diff,allData(iData).fl_diff,'tail','both');
    % Update all data structure
    allData(iData).st_h = st_h;
    allData(iData).st_p = st_p;
    allData(iData).st_ci = st_ci;
    allData(iData).st_tstat = st_stats.tstat;
    allData(iData).fl_h = fl_h;
    allData(iData).fl_p = fl_p;
    allData(iData).fl_ci = fl_ci;
    allData(iData).fl_tstat = fl_stats.tstat;
    allData(iData).tot_h = tot_h;
    allData(iData).tot_p = tot_p;
    allData(iData).tot_ci = tot_ci;
    allData(iData).tot_tstat = tot_stats.tstat;
end

%% Export
export_path = '/mnt/raid/atonin/balbuzie/TMS-EEG/Results/Stats';
common_file_name = 'TMS_EEG_ersd_stats.csv';

if ~exist(export_path, 'dir')
    mkdir(export_path)
end

rowformat = ['%s,%s,',repmat('%f,', 1, length(times)-1),'%f\n'];
header = [{'roi','band'}, num2cell(times)];

% Write stutter
stutter_file = strcat('stutter_', common_file_name);
fid = fopen(fullfile(export_path, stutter_file), 'w');
fprintf(fid,rowformat,header{:});
for iData = 1:length(allData)
    roi = allData(iData).roi;
    band = allData(iData).band;
    p = allData(iData).st_p;
    fprintf(fid,rowformat,roi,band,p);
end
fclose(fid);

% Write fluent
fluent_file = strcat('fluent_', common_file_name);
fid = fopen(fullfile(export_path, fluent_file), 'w');
fprintf(fid,rowformat,header{:});
for iData = 1:length(allData)
    roi = allData(iData).roi;
    band = allData(iData).band;
    p = allData(iData).fl_p;
    fprintf(fid,rowformat,roi,band,p);
end
fclose(fid);

% Write total
total_file = strcat('total_', common_file_name);
fid = fopen(fullfile(export_path, total_file), 'w');
fprintf(fid,rowformat,header{:});
for iData = 1:length(allData)
    roi = allData(iData).roi;
    band = allData(iData).band;
    p = allData(iData).tot_p;
    fprintf(fid,rowformat,roi,band,p);
end
fclose(fid);

%% Plot t stat

export_path = '/mnt/raid/atonin/balbuzie/TMS-EEG/Results/Stats/Img/tstat';
common_file_name = 'TMS_EEG_ersd_t-stat.png';

if ~exist(export_path, 'dir')
    mkdir(export_path)
end

rois = unique({allData.roi});
conditions = ["Stutter", "Fluent", "Total"];
names_tstat = ["st_tstat", "fl_tstat", "tot_tstat"];

for iRoi = 1:length(rois)
    roi_name = rois{iRoi};
    % Extract data
    roi_data = allData(strcmp({allData.roi},roi_name));
    bands = {roi_data.band};
    for iCon = 1:length(conditions)
        % plot images
        figure
        tstat = cat(1,roi_data.(names_tstat(iCon)));
        imagesc(times,1:length(bands),tstat)
        colorbar
        axis xy
        set(gca, ...
        'YTick', 1:9, ...
        'YTickLabel', bands)
        title(sprintf("t-value - %s - %s", strtrim(roi_name), conditions(iCon)))
        img_name = sprintf("%s_%s_%s", conditions(iCon), replace(strtrim(roi_name),' ','_'), common_file_name);
        exportgraphics(gcf, fullfile(export_path, img_name), 'Resolution',300)
    end
end

%% Plot ersd mean values

export_path = '/mnt/raid/atonin/balbuzie/TMS-EEG/Results/Stats/Img/mean';
common_file_name = 'TMS_EEG_ersd_mean.png';

if ~exist(export_path, 'dir')
    mkdir(export_path)
end

rois = unique({allData.roi});
conditions = ["Stutter", "Fluent"];
names_mean = ["st_diff", "fl_diff"];

for iRoi = 1:length(rois)
    roi_name = rois{iRoi};
    % Extract data
    roi_data = allData(strcmp({allData.roi},roi_name));
    bands = {roi_data.band};
    for iCon = 1:length(conditions)
        % plot images
        figure
        mean_vals = cellfun(@mean, {roi_data.(names_mean(iCon))}, 'UniformOutput', false);
        vals = cat(1,mean_vals{:});
        imagesc(times,1:length(bands),vals)
        colorbar
        axis xy
        set(gca, ...
        'YTick', 1:9, ...
        'YTickLabel', bands)
        title(sprintf("Average TMS-SHAM - %s - %s", strtrim(roi_name), conditions(iCon)))
        img_name = sprintf("%s_%s_%s", conditions(iCon), replace(strtrim(roi_name),' ','_'), common_file_name);
        exportgraphics(gcf, fullfile(export_path, img_name), 'Resolution',300)
    end
end

