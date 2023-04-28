%% Batch process widefield images on rig
% 
% - Finds folders with images
% - Runs SVD
% - Moves from local to server: 
%       -> day-specific folders in day/widefield
%       -> protocol-specific folders in day/protocol/widefield

%% Find folders with data

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
    % Check if day paths contain tiffs
    for curr_day_path = find(day_paths)
        curr_day_path_tiff = dir( ...
            fullfile(animal_dir(curr_day_path).folder, ...
            animal_dir(curr_day_path).name,'widefield','*.tif'));
        % If day path contains tiffs, add path to to-process list
        if ~isempty(curr_day_path_tiff)
            process_paths{end+1} = curr_day_path_tiff.folder;
        end
    end
end

%% Preprocess all local data

for curr_data_path = process_paths
    curr_data_path = cell2mat(curr_data_path);

    fprintf('Preprocessing: %s \n',curr_data_path);

    %% Widefield preprocessing function
    [U,Vrec,im_avg_color,frame_info] = plab.wf.preprocess_widefield_hamamatsu(curr_data_path);

    %% Save preprocessed widefield data locally

    % Assume 2 colors in order of blue/purple
    color_names = {'blue','violet'};

    % Save frame information in experiment folder
    frame_info_fn = fullfile(curr_data_path,'widefield_frame_info');
    save(frame_info_fn,'frame_info','-v7.3');

    % Save mean images in experiment folder by color
    for curr_color = 1:length(color_names)
        curr_mean_im_fn = fullfile(curr_data_path, ...
            sprintf('meanImage_%s.npy',color_names{curr_color}));
        writeNPY(im_avg_color(:,:,curr_color),curr_mean_im_fn);
    end

    % Save spatial components in experiment (animal/day) folder by color
    for curr_color = 1:length(color_names)
        curr_U_fn = fullfile(curr_data_path, ...
            sprintf('svdSpatialComponents_%s.npy',color_names{curr_color}));
        writeNPY(U{curr_color},curr_U_fn);
    end

    % Save temporal components in associated recording folders
    for curr_recording = 1:size(Vrec,1)
        for curr_color = 1:length(color_names)
            % Put V's into separate recording paths
            curr_V_fn = fullfile(curr_data_path,sprintf('recording_%d',curr_recording), ...
                sprintf('svdTemporalComponents_%s.npy',color_names{curr_color}));
            % Make recording path
            mkdir(fileparts(curr_V_fn));
            % Write V to file
            writeNPY(Vrec{curr_recording,curr_color},curr_V_fn);
        end
    end

    %% Move data onto server
    % Check if the server is available
    if ~exist(plab.locations.server_data_path,'dir')
        warning('Server not accessible at %s',plab.locations.server_data_path)
        return
    end

    % Move local data to server:
    local_data_dir = dir(curr_data_path);

    % Move day-relevant files to day folder
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

    % Move protocol-relevant files to protocol folders
    local_data_protocolfiles_idx = find([local_data_dir.isdir] & ~contains({local_data_dir.name},'.'));

    % Get timestamp of first frame in each recording
    [~,recording_start_frame] = unique([frame_info.rec_idx]);
    frame_timestamp_cat = [frame_info.timestamp];
    recording_start_times = str2num(char(frame_timestamp_cat(recording_start_frame),'HHmm'));

    % Get Protocol folder with closest previous time for each recording
    curr_server_path = strrep(fileparts(curr_data_path), ...
        plab.locations.local_data_path,plab.locations.server_data_path);
    curr_server_dir = dir(curr_server_path);
    [protocol_paths,protocol_regexp] = regexp({curr_server_dir.name},'Protocol_(\d*)','match','tokens');
    protocol_paths_cat = horzcat(protocol_paths{:});
    protocol_regexp_cat = cellfun(@(x) horzcat(x{:}),protocol_regexp,'uni',false);
    curr_server_protocol_times = cellfun(@str2num,horzcat(protocol_regexp_cat{:}));

    recording_protocol_idx = arrayfun(@(x) ...
        find(recording_start_times(x) - curr_server_protocol_times >= 0,1,'last'), ...
        1:length(recording_start_times));

    % (sanity check: there should be no overlapping protocol indices)
    if length(unique(recording_protocol_idx)) ~= length(recording_protocol_idx)
        error('Widefield recordings have overlapping protocol folders')
    end

    for curr_recording_idx = 1:length(recording_protocol_idx)

        % Local path
        curr_dir_idx = local_data_protocolfiles_idx(curr_recording_idx);
        curr_local_filename = fullfile(local_data_dir(curr_dir_idx).folder, ...
            local_data_dir(curr_dir_idx).name);

        % Server path: 
        curr_server_filename = fullfile(curr_server_path, ...
            protocol_paths_cat{recording_protocol_idx(curr_recording_idx)}, ...
            'widefield');

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

    % Delete empty local folders
    % (2 hierarchy levels: day > animal)
    try
        curr_hierarchy_path = curr_data_path;
        for hierarchy_levels = 1:3
            hierarchy_dir = dir(curr_hierarchy_path);
            if all(contains({hierarchy_dir.name},'.'))
                rmdir(curr_hierarchy_path)
                % Move up one step in hierarchy
                curr_hierarchy_path = fileparts(curr_hierarchy_path);
            end
        end
    end

    disp('Finished.');

end



















