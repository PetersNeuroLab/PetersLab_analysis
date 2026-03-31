% Batch preprocess Neuropixels data
% (is this not what's on the ephys computer? seemed outdated)

% Find animals with ephys data (by Open Ephys structure.oebin files)
oe_data_paths = unique(string( ...
    fileparts(fileparts({dir(fullfile( ...
    plab.locations.local_data_path,'/**/','structure.oebin')).folder}))));

for curr_oe_data_path = oe_data_paths

    % Grab animal name and date
    animal_name_pattern = lettersPattern(2)+digitsPattern(3);
    animal = extract(curr_oe_data_path,animal_name_pattern);

    day_pattern = digitsPattern(4)+'-'+digitsPattern(2)+'-'+digitsPattern(2);
    day = extract(curr_oe_data_path,day_pattern);

    % Run Neuropixels preprocessing
    plab.ephys.neuropixels_preprocess(animal,day,curr_oe_data_path);

end

%%%% TO DO: clean up empty folders



