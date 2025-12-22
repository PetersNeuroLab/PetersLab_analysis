

% Find animals with ephys data
% (find Open Ephys record node folders)
oe_data_paths = string({dir(fullfile(plab.locations.local_data_path, ...
    '/**/','Record Node*')).folder});

oe_data_paths = oe_data_paths(3);

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



