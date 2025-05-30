%% Batch process widefield images on rig
%
% - Finds folders with images
% - Runs SVD
% - Moves from local to server:
%       -> day-specific folders in day/widefield
%       -> protocol-specific folders in day/protocol/widefield
%
% To re-SVD: this can be run from any computer if the animal/day/widefield
% folder is copied into `plab.locations.local_data_path`

%% Find folders with data

% Loop through all animals/days, look for populated "widefield" folders
local_data_dir = dir(plab.locations.local_data_path);
animal_paths = ~contains({local_data_dir.name},{'.'});

process_paths = cell(0);
for animal_path = {local_data_dir(animal_paths).name}
    animal_path = cell2mat(animal_path);
    animal_dir = dir(fullfile(plab.locations.local_data_path,animal_path));
    % Find day paths of the form YYYY-MM-DD
    day_paths = cellfun(@(x) ...
        ~isempty(regexp(x,'\d\d\d\d-\d\d-\d\d')), ...
        {animal_dir.name}) &...
        [animal_dir.isdir];
    % Check if day paths contain images
    for curr_day_path = find(day_paths)
        curr_widefield_path = fullfile(animal_dir(curr_day_path).folder, ...
            animal_dir(curr_day_path).name,'widefield');

        if isempty(dir(fullfile(curr_widefield_path,'*.bin')))
            continue
        end

        process_paths{end+1} = curr_widefield_path;
    end
end

%% Preprocess all local data

for curr_process_path_cell = process_paths
    curr_process_path = cell2mat(curr_process_path_cell);

    % Put in TRY/CATCH: if one dataset doesn't work, move to the next
    try

        preload_vars = who;

        fprintf('Preprocessing: %s \n',curr_process_path);

        %% SVD decomposition of widefield data
        
        % Currently: SVD 2 colors separately, assume alt. blue/violet
        wf_colors = {'blue','violet'};
        n_colors = length(wf_colors);

        [U,V,im_avg] = plab.wf.preprocess_widefield(curr_process_path,n_colors);

        %% Save preprocessed widefield data locally

        local_save_path = curr_process_path;

        % Set color names (empty if SVD not split by color)
        if n_colors == 1
            color_suffix = {''};
        else
            color_suffix = cellfun(@(x) sprintf('_%s',x),wf_colors,'uni',false);
        end

        % Save mean images in experiment folder by color
        for curr_color = 1:length(color_suffix)
            curr_mean_im_fn = fullfile(local_save_path, ...
                sprintf('meanImage%s.npy',color_suffix{curr_color}));
            writeNPY(im_avg{curr_color},curr_mean_im_fn);
        end

        % Save spatial components in experiment (animal/day) folder by color
        for curr_color = 1:length(color_suffix)
            curr_U_fn = fullfile(local_save_path, ...
                sprintf('svdSpatialComponents%s.npy',color_suffix{curr_color}));
            writeNPY(U{curr_color},curr_U_fn);
        end

        % Save temporal components in associated recording folders
        % (get recording times from filenames)
        data_dir = dir(fullfile(curr_process_path,'*_data.bin'));
        recording_times = extract({data_dir.name},digitsPattern);
        for curr_recording = 1:size(V,1)
            for curr_color = 1:length(color_suffix)
                % Put V's into separate recording paths
                curr_V_fn = fullfile(local_save_path,recording_times{curr_recording}, ...
                    sprintf('svdTemporalComponents%s.npy',color_suffix{curr_color}));
                % Make recording path
                if ~exist(fileparts(curr_V_fn),'dir')
                    mkdir(fileparts(curr_V_fn));
                end
                % Write V to file
                writeNPY(V{curr_recording,curr_color},curr_V_fn);
            end
        end

        %% Move data onto server
        % Check if the server is available
        if ~exist(plab.locations.server_data_path,'dir')
            warning('Server not accessible at %s',plab.locations.server_data_path)
            return
        end

        % Move local data to server:
        local_data_dir = dir(local_save_path);

        % Move day-level files to day widefield folder
        disp('Moving widefield files to server...')
        local_data_dayfiles_idx = ~[local_data_dir.isdir];
        for curr_file_idx = find(local_data_dayfiles_idx)

            % Local filename
            curr_local_filename = fullfile(local_data_dir(curr_file_idx).folder, ...
                local_data_dir(curr_file_idx).name);

            % Server filename: replace path from local data to server
            curr_server_filename = strrep(curr_local_filename, ...
                plab.locations.local_data_path,plab.locations.server_data_path);

            % Make server path (if it doesn't exist) and move
            if ~exist(fileparts(curr_server_filename),'dir')
                mkdir(fileparts(curr_server_filename));
            end

            [status,message] = movefile(curr_local_filename,curr_server_filename);
            if ~status
                warning('Failed moving to server: %s',message);
            else
                fprintf('Moved %s --> %s \n',curr_local_filename,curr_server_filename);
            end
        end

        % Move protocol-level files to protocol folders
        local_data_protocolfiles_idx = [local_data_dir.isdir] & ~contains({local_data_dir.name},'.');
        % (get animal/day)
        animal_day = split(erase(curr_process_path,{[plab.locations.local_data_path,filesep],'widefield'}),filesep);

        for curr_recording_idx = find(local_data_protocolfiles_idx)

            % Local path (name is recording time)
            curr_local_path = fullfile(local_data_dir(curr_recording_idx).folder, ...
                local_data_dir(curr_recording_idx).name);
            rec_time = local_data_dir(curr_recording_idx).name;

            % Server path
            curr_server_path = plab.locations.filename('server', ...
                animal_day{1},animal_day{2},rec_time,'widefield');

            % Make server recording path (if it doesn't exist)
            if ~exist(fileparts(curr_server_path),'dir')
                mkdir(fileparts(curr_server_path));
            end

            % Remove recording widefield folder (if it exists)
            % (only used when overwriting on re-processing)
            if exist(curr_server_path,'dir')
                rmdir(curr_server_path,'s');        
            end

            % Move local widefield V's into recording widefield folder
            [status,message] = movefile(curr_local_path,curr_server_path);
            if ~status
                warning('Failed moving to server: %s',message);
            else
                fprintf('Moved %s --> %s \n',curr_local_path,curr_server_path);
            end

        end

        % Delete empty local folders
        % (2 hierarchy levels: day > animal)
        try
            curr_hierarchy_path = curr_process_path;
            for hierarchy_levels = 1:3
                hierarchy_dir = dir(curr_hierarchy_path);
                if all(contains({hierarchy_dir.name},'.'))
                    rmdir(curr_hierarchy_path)
                    % Move up one step in hierarchy
                    curr_hierarchy_path = fileparts(curr_hierarchy_path);
                end
            end
        end

        % Clean workspace for next loop
        clearvars('-except',preload_vars{:});

        disp('Finished.');

        % If there was a failure at any point, warning and move to next data
    catch me
        warning(me.identifier,'Widefield preprocessing failed: %s',me.message);
    end

end








