function OutputFiles = db_force_headmodel(HeadModelFile, Target)
% DB_FORCE_HEADMODEL: Force a head model node to other studies
%
% USAGE:  OutputFiles = db_force_headmodel(HeadModelFile, iDestStudies)   : Apply to the target studies
%         OutputFiles = db_force_headmodel(HeadModelFile, 'AllConditions'): Apply to all the conditons in the same subject
%         OutputFiles = db_force_headmodel(HeadModelFile, 'AllSubjects')  : Apply to all the conditons in all the subjects

% This function is a modified version of BrainStorm function
% db_set_headmodel

OutputFiles = {};

% ===== GET SOURCE STUDY =====
% Get source study
[sSrcStudy, iSrcStudy] = bst_get('AnyFile', HeadModelFile);
    
% ===== GET TARGET STUDIES =====
if isnumeric(Target)
    % Destination studies are passed in argument
    iDestStudies = Target;
elseif strcmpi(Target, 'AllConditions')
    % Get all the studies for this subject
    [sDestStudies, iDestStudies] = bst_get('StudyWithSubject', sSrcStudy.BrainStormSubject);
elseif strcmpi(Target, 'AllSubjects')
    % Get the whole database
    ProtocolSubjects = bst_get('ProtocolSubjects');
    % Get list of subjects (sorted alphabetically => same order as in the tree)
    [uniqueSubjects, iUniqueSubjects] = sort({ProtocolSubjects.Subject.Name});
    % Process each subject
    iDestStudies = [];
    for iSubj = 1:length(uniqueSubjects)
        % Get subject filename
        iSubject = iUniqueSubjects(iSubj);
        SubjectFile = ProtocolSubjects.Subject(iSubject).FileName;
        % Get all the studies for this subject
        [sStudies, iStudies] = bst_get('StudyWithSubject', SubjectFile, 'intra_subject', 'default_study');
        iDestStudies = [iDestStudies, iStudies];
    end
else 
    return;
end

% ===== COPY HEADMODEL =====
% Process each target study
nCopied = 0;
for i = 1:length(iDestStudies)
    % Get destination study
    iDestStudy = iDestStudies(i);
    destStudy = bst_get('Study', iDestStudy);
    
    % Skip source study
    if iDestStudy == iSrcStudy
        continue;
    end
    
    % Check whether destination study has head model
    destHeadModel = bst_get('HeadModelForStudy', iDestStudy);
    if ~isempty(destHeadModel)
        destSubject = bst_get('Subject', destStudy.BrainStormSubject);
        disp(['BST> Study "' conditionName '" of subject "' destSubject.Name '" already contains a head model. Skipping.']);
        continue;
    end
    
    % Copy head model file
    OutputFiles{end + 1} = panel_protocols('CopyFile', iDestStudy, HeadModelFile, 'headmodel', iSrcStudy);
    nCopied = nCopied + 1;
end

% ===== RELOAD STUDIES =====
if nCopied > 0
    db_reload_studies(iDestStudies);
else
    java_dialog('warning', ['No file was copied.']);
end

