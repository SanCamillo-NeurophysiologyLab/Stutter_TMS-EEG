%% Bl and TEP eeglab .set files

data_dir = '/mnt/raid/atonin/balbuzie/data';
group_dir = {'balb', 'norm'};
bl_dir = 'BL';
tep_dir = 'TEP';
full_dir = 'FULL';
conditions = {'sham', 'tms'};

%remove existing files 
remove_existing = 1;

%% Load eeglab

[ALLEEG EEG CURRENTSET ALLCOM] = eeglab;

%% Main loop

for i_cond = 1:length(group_dir)
    group = group_dir{i_cond};
    curr_cond_dir = fullfile(data_dir, group);
    subject_id = 100 * i_cond; % Balb = 1xx, Norm = 2xx
    all_subjects = dir(curr_cond_dir);
    for i_subj = 1:length(all_subjects)
        subj = all_subjects(i_subj);
        % skip not subject files/folders
        if ~subj.isdir
            continue
        elseif startsWith(subj.name, '.')
            continue
        end
        subject_id = subject_id + 1;
        subj_dir = fullfile(curr_cond_dir, subj.name);
        sham_files = [dir(fullfile(subj_dir, bl_dir, '*sham*.set')) dir(fullfile(subj_dir, tep_dir, '*sham*.set'))];
        tms_files = [dir(fullfile(subj_dir, bl_dir, '*tms*.set')) dir(fullfile(subj_dir, tep_dir, '*tms*.set'))];

        % skip subjects without both bl and tep dir
        if length(sham_files) ~= 2
            warning("Skipping subject %s: missing sham files", subj.name)
            continue
        elseif length(tms_files) ~= 2
            warning("Skipping subject %s: missing tms files", subj.name)
            continue
        end

        eeg_sets = {sham_files, tms_files};
        
        for i_set = 1:2
            try
                eeg_set = eeg_sets{i_set};
                condition = conditions{i_set};
    
                fprintf("Processing %s: %s - %s\n", group_dir{i_cond}, subj.name, condition)
    
                % define set path
                set_bl = eeg_set(1); %fullfile(eeg_set(1).folder, eeg_set(1).name);
                set_tep = eeg_set(2); %fullfile(eeg_set(2).folder, eeg_set(2).name);
           
                %% Load datasets
                EEG_A = pop_loadset('filename', set_bl.name, 'filepath', fullfile(set_bl.folder, filesep));
                EEG_A = eeg_checkset(EEG_A);
                EEG_B = pop_loadset('filename', set_tep.name, 'filepath', fullfile(set_tep.folder, filesep));
                EEG_B = eeg_checkset(EEG_B);
                
                % check the datasets match
                if EEG_A.trials ~= EEG_B.trials
                    error('Subject: %s. Condition: %s. Number of epochs do not match.', subj.name, condition);
                end
                
                %% Interpolate gap
                
                gap_len = round((0.020 - (-0.010)) * EEG_A.srate); % e.g., 30 samples
                
                nEpochs = EEG_A.trials;
                nChan = EEG_A.nbchan;
                
                % Preallocate
                EEG_interp = zeros(nChan, gap_len, nEpochs);
                
                for ep = 1:nEpochs
                    for ch = 1:nChan
                        y1 = EEG_A.data(ch, end, ep);  % value at -0.010
                        y2 = EEG_B.data(ch, 1, ep);    % value at 0.020
                
                        EEG_interp(ch, :, ep) = linspace(y1, y2, gap_len);
                    end
                end
                
                %% Concatenate
                EEG_full = cat(2, EEG_A.data, EEG_interp, EEG_B.data);
                
                %% Create new EEGLAB structure
                
                EEG = EEG_A;  % Use A as base
                EEG.data = EEG_full;
                EEG.pnts = size(EEG_full, 2);
                EEG.times = linspace(-0.200, 0.500, EEG.pnts);  % Update time vector
                EEG.xmin = -0.200;
                EEG.xmax = 0.500;
%                 [ALLEEG EEG CURRENTSET] = eeg_store(ALLEEG, EEG);

                %% Update fields
                eeg_subject = sprintf('S%d', subject_id);
                eeg_condition = condition;
                eeg_group = group;
                eeg_task = condition;
                eeg_session = 1;
                eeg_run = i_set;
                
                setname = sprintf('%s_%s_merged', subj.name, condition);
                

                EEG = pop_editset(EEG, 'setname', setname, 'subject', eeg_subject, 'condition', eeg_condition, 'group', eeg_group, 'session', eeg_session);      
                EEG.task = eeg_task;
                EEG.run = eeg_run;
                %% Save
                outfile_path = fullfile(subj_dir, full_dir, filesep);
                outfile_name = sprintf('%s.set', setname);   
                EEG.filename = outfile_name;
                EEG.filepath = outfile_path;

                if ~exist(outfile_path, "dir")
                    mkdir(outfile_path)
                elseif remove_existing && i_set==1
                    rmdir(outfile_path, "s")
                    mkdir(outfile_path)
                end
                EEG = pop_saveset(EEG, 'filename', EEG.filename, 'filepath', EEG.filepath);
            catch ME
                warning("ERROR: Skipping subject %s condition %s", subj.name, condition)
            end
        end
    end
end

