%% copy_timefreq_results.m
% This script scans the Brainstorm data directory and copies all
% "timefreq_morlet_YYMMDD_HHMM*.mat" files into a new folder.
%
% Author: [Your Name]
% Date: [Today's Date]

clc;
clear;

%% === Configuration ===
src_root = '/mnt/raid/brainstorm_db/Stutter_TMSEEG/data';  % Source data folder
dst_root = '/mnt/raid/atonin/balbuzie/TMS-EEG/Data/Results'; % Destination folder

% Create destination folder if it doesn't exist
if ~exist(dst_root, 'dir')
    mkdir(dst_root);
end

%% === Loop through subjects ===
subjects = dir(fullfile(src_root, 'sub-S*'));
subjects = subjects([subjects.isdir]); % Only keep directories

for iSub = 1:numel(subjects)
    subj_name = subjects(iSub).name;
    subj_path = fullfile(src_root, subj_name);

    % Get all session folders for this subject
    sessions = dir(fullfile(subj_path, '@rawsub-*'));
    sessions = sessions([sessions.isdir]);
    
    for iSes = 1:numel(sessions)
        sess_name = sessions(iSes).name;
        sess_path = fullfile(subj_path, sess_name);
        
        % Find time-frequency files
        tf_files = dir(fullfile(sess_path, 'timefreq_morlet_*.mat'));
        
        if isempty(tf_files)
            continue;
        end
        
        % Create destination folder for this subject/session
        dst_sess_dir = fullfile(dst_root, subj_name, sess_name);
        if ~exist(dst_sess_dir, 'dir')
            mkdir(dst_sess_dir);
        end
        
        % Loop through time-frequency files
        for iFile = 1:numel(tf_files)
            src_file = fullfile(sess_path, tf_files(iFile).name);
            
            try
                % Load only the 'Freqs' variable
                S = load(src_file, 'Freqs');
                
                if isfield(S, 'Freqs') && numel(S.Freqs) == 200
                    % Copy the file
                    dst_file = fullfile(dst_sess_dir, tf_files(iFile).name);
                    copyfile(src_file, dst_file);
                    fprintf('Copied: %s → %s\n', src_file, dst_file);
                else
                    fprintf('Skipped (Freqs length %d): %s\n', numel(S.Freqs), src_file);
                end
            catch ME
                fprintf('⚠️ Error reading %s: %s\n', src_file, ME.message);
            end
        end
    end
end

disp('✅ All matching time-frequency results have been copied successfully!');
