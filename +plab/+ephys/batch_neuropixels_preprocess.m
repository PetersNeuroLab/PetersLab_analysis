% Batch preprocess Neuropixels data

%% Find data to process

% Find animals with ephys data (by Open Ephys structure.oebin files)
oe_data_paths = unique(string( ...
    fileparts(fileparts({dir(fullfile( ...
    plab.locations.local_data_path,'/**/','structure.oebin')).folder}))));

%% Process all data

for curr_oe_data_path = oe_data_paths

    % Grab animal name and date
    animal_name_pattern = lettersPattern(2)+digitsPattern(3);
    animal = extract(curr_oe_data_path,animal_name_pattern);

    day_pattern = digitsPattern(4)+'-'+digitsPattern(2)+'-'+digitsPattern(2);
    day = extract(curr_oe_data_path,day_pattern);

    % Run Neuropixels preprocessing
    plab.ephys.neuropixels_preprocess(animal,day,curr_oe_data_path);

end

%% Remove empty folders/subfolders in local data path

local_data_dir = dir(fullfile(plab.locations.local_data_path,'/**/'));

all_folders = {local_data_dir.folder};
file_folders = {local_data_dir(~[local_data_dir.isdir]).folder};

empty_folder_idx = ~arrayfun(@(x) any(contains(file_folders,x)),all_folders);
empty_folders = string(unique({local_data_dir(empty_folder_idx).folder}));

if ~isempty(empty_folders)
    [~,subfolder_sort] = sort(strlength(empty_folders),'descend');
    for curr_empty_folder = empty_folders(subfolder_sort)
        remove_success = rmdir(curr_empty_folder);
        if remove_success
            fprintf('Removed: %s\n',curr_empty_folder)
        else
            fprintf('Could not remove: %s\n',curr_empty_folder)
        end
    end
end


