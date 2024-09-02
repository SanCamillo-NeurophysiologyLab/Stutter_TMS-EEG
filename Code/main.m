%% Clear everything
% clear all;
% close all;
% clc

%% Parameters
bidsFolder = '/mnt/raid/atonin/balbuzie/TMS-EEG/Data/bids';
protocolName = 'TMSEEG';
commonHeadModel = true;
baseline_end_pattern = '1_eeg';
data_end_pattern = '2_eeg';

delete_raw = 0;

delete_headmodel = 0;
delete_covmatrix = 0;

delete_source = 0;
delete_kernelroi = 0;
delete_tf = 0;

%% Setup brainstorm
if ~brainstorm('status')
    brainstorm nogui
end

if delete_raw
    sFiles = bst_process('CallProcess', 'process_select_files_data', [], []);
    % Process: Delete selected files
    sFiles = bst_process('CallProcess', 'process_delete', sFiles, [], ...
        'target', 1);  % Delete selected files
end
if delete_source
    sFiles = bst_process('CallProcess', 'process_select_files_results', [], []);
    % Process: Delete selected files
    sFiles = bst_process('CallProcess', 'process_delete', sFiles, [], ...
        'target', 1);  % Delete selected files
end
if delete_kernelroi
    sFiles = bst_process('CallProcess', 'process_select_files_matrix', [], []);
    % Process: Delete selected files
    sFiles = bst_process('CallProcess', 'process_delete', sFiles, [], ...
        'target', 1);  % Delete selected files
end
if delete_tf
    sFiles = bst_process('CallProcess', 'process_select_files_timefreq', [], []);
    % Process: Delete selected files
    sFiles = bst_process('CallProcess', 'process_delete', sFiles, [], ...
        'target', 1);  % Delete selected files
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
    sFiles = db_set_headmodel(headModel.FileName, 'AllSubjects');
end

%% Noise covariance matrix

sdataAll = bst_process('CallProcess', 'process_select_files_data', [], []);
data_conditions = {sdataAll.Condition};

for ii = 1:length(data_conditions)
    condition = data_conditions{ii};
    % if it is not baseline skip
    if endsWith(condition, data_end_pattern)
        continue
    end
    % otherwise it is a baseline
    idx_bl = ii;
    bl_study = sdataAll(idx_bl).iStudy;

    % Process: Compute covariance (noise or data)
    sCovariance = bst_process('CallProcess', 'process_noisecov', sdataAll(idx_bl), [], ...
        'baseline',       [], ...
        'sensortypes',    'EEG', ...
        'target',         1, ...  % Noise covariance     (covariance over baseline time window)
        'dcoffset',       1);  % Block by block, to avoid effects of slow shifts in data
    
    % Then find the corresponding dataset
    base_name = extractBefore(condition, baseline_end_pattern);
    condition_data = [base_name data_end_pattern];

    idx_data = find(strcmp(data_conditions, condition_data));
    if isempty(idx_data)
        % This should never happen
        warning("File %s not found!", condition_data)
    end
    data_study = sdataAll(idx_data).iStudy;

    % And copy the noise covariance matrix
    db_set_noisecov(bl_study, data_study, 0, 1)
end

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

%% Extract time series at ROI level
sdataAll = bst_process('CallProcess', 'process_select_files_results', [], []);

% Process: Scout time series: temporal L temporal R inferiorParietal L inferiorParietal R central L central R posteriorFrontal L posteriorFrontal R anteriorFrontal L anteriorFrontal R inferiorFrontal L inferiorFrontal R
sFiles = bst_process('CallProcess', 'process_extract_scout', sdataAll, [], ...
    'scouts',         {'DS_Linguistic', {'temporal L', 'temporal R', 'inferiorParietal L', 'inferiorParietal R', 'central L', 'central R', 'posteriorFrontal L', 'posteriorFrontal R', 'anteriorFrontal L', 'anteriorFrontal R', 'inferiorFrontal L', 'inferiorFrontal R'}}, ...
    'scoutfunc',      'pca', ...  % PCA
    'pcaedit',        struct(...
         'Method',         'pcai', ...
         'Baseline',       [NaN, NaN], ...
         'DataTimeWindow', [-0.2, -0.0103], ...
         'RemoveDcOffset', 'none'));

%% TF decomposition
sdataAll = bst_process('CallProcess', 'process_select_files_matrix', [], []);

% Process: Time-frequency (Morlet wavelets)
sFiles = bst_process('CallProcess', 'process_timefreq', sdataAll, [], ...
    'edit',          struct(...
         'Comment',         'Power,8-30Hz', ...
         'TimeBands',       [], ...
         'Freqs',           [8:1:30], ...
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
data_conditions = {sDataTF.Condition};

% Baseline normalization
for ii = 1:length(data_conditions)
    condition = data_conditions{ii};
    % if it is not baseline skip
    if endsWith(condition, data_end_pattern)
        continue
    end
    % otherwise it is a baseline
    idx_bl = ii;

    % look for the corresponding dataset
    base_name = extractBefore(condition, baseline_end_pattern);
    condition_data = [base_name data_end_pattern];

    idx_data = find(strcmp(data_conditions, condition_data));
    
    if isempty(idx_data)
        % This should never happen
        warning("File %s not found!", condition_data)
    end

    % Process: Event-related perturbation (ERS/ERD): [All file]
    sFiles = bst_process('CallProcess', 'process_baseline_norm2', sDataTF(idx_bl), sDataTF(idx_data), ...
        'baseline', [], ...
        'method',   'ersd');  % Event-related perturbation (ERS/ERD):    x_std = (x - &mu;) / &mu; * 100


end