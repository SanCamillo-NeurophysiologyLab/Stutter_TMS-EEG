%% Bl and TEP eeglab .set files

data_dir = '/mnt/raid/atonin/balbuzie/data';
full_dir = 'FULL';
out_dir = '/mnt/raid/atonin/balbuzie/TMS-EEG/Data';
bids_dir = 'bids_export';

study_name = 'Stutter TMS';
license = 'CC0';

%remove existing files 
remove_existing = 1;

%% Load eeglab
[ALLEEG EEG CURRENTSET ALLCOM] = eeglab;

%% Load all files (easier since info are stored in the eeglab set file)
all_full_files = dir(fullfile(data_dir, '**', full_dir, '*.set'));

for i_file = 1:length(all_full_files)
    file = all_full_files(i_file);
    EEG = pop_loadset('filename', file.name, 'filepath', file.folder);
    [ALLEEG EEG CURRENTSET] = eeg_store(ALLEEG, EEG, i_file);
end

%% Create a study
[ STUDY ALLEEG ] = pop_study(STUDY, ALLEEG, 'name', study_name);

%% Export bids
ALLEEG = pop_eventinfo(ALLEEG, STUDY, 'default');
ALLEEG = pop_participantinfo(ALLEEG, STUDY, 'default');
ALLEEG = pop_taskinfo(ALLEEG, 'default');
out_dir = fullfile(out_dir, bids_dir);
pop_exportbids(STUDY, ALLEEG, 'targetdir', out_dir, 'License', license, 'createids', 'off', 'individualEventsJson', 'off');
