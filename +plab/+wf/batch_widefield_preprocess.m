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

process_files = cell(0);
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

        % Look for: DCIMG (HCImage streaming file), TIFFs
        curr_dcimg_files = dir(fullfile(curr_widefield_path,'*.dcimg'));
        curr_tiff_files = dir(fullfile(curr_widefield_path,'*.tif'));

        % Choose files to process (or return if none)
        % (priority: DCIMG > TIFF)
        if ~isempty(curr_dcimg_files)
            im_files = curr_dcimg_files;
        elseif ~isempty(curr_tiff_files)
            im_files = curr_tiff_files;
        else
            return
        end

        % Add files to processing list
        process_files{end+1} = cellfun(@(dir,fn) ...
            fullfile(dir,fn),{im_files.folder},{im_files.name},'uni',false);
    end
end

%% Preprocess all local data

for curr_process_files_idx = 1:length(process_files)

    % Put in TRY/CATCH: if one dataset doesn't work, move to the next
    try

        preload_vars = who;

        curr_process_files = process_files{curr_process_files_idx};
        fprintf('Preprocessing: [%s] \n',cell2mat(join(curr_process_files,', ')));

        %% SVD decomposition of widefield data

        %%%%% VERY TEMPORARY: GET FRAME SPLITS FROM TIMELITE

        % Get animal/day folder on server

        curr_server_path = strrep(fileparts(fileparts(curr_process_files{1})), ...
            plab.locations.local_data_path,plab.locations.server_data_path);

        curr_protocol_paths = dir(fullfile(curr_server_path,'Protocol*'));
        curr_timelite_filenames = cellfun(@(day_path,protocol_path) ...
            fullfile(day_path,protocol_path,'timelite.mat'), ...
            {curr_protocol_paths.folder},{curr_protocol_paths.name},'uni',false);

        n_frames_tl = zeros(length(curr_timelite_filenames),1);
        for curr_protocol = 1:length(curr_timelite_filenames)

            % Set level for TTL threshold
            ttl_thresh = 2;

            % Load timelite
            if exist(curr_timelite_filenames{curr_protocol},'file')
                timelite = load(curr_timelite_filenames{curr_protocol});
            else
                continue
            end

            % Widefield times
            widefield_idx = strcmp({timelite.daq_info.channel_name}, 'widefield_camera');
            widefield_thresh = timelite.data(:,widefield_idx) >= ttl_thresh;
            widefield_expose_times = timelite.timestamps(find(diff(widefield_thresh) == 1) + 1);

            % Store number of frames
            n_frames_tl(curr_protocol) = length(widefield_expose_times);

        end
        % (don't include protocols with 0 widefield frames)
        n_frames_tl(n_frames_tl == 0) = [];

        %%%%% ALSO TEMPORARY: optionally enter number of frames per recording
        %%%%% as an input to preprocessing function
        [U,Vrec,im_avg_color,frame_info] = plab.wf.preprocess_widefield_hamamatsu(curr_process_files,n_frames_tl);
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        % TO DO - WHEN THINGS ARE BACK TO NORMAL:
        %     [U,Vrec,im_avg_color,frame_info] = plab.wf.preprocess_widefield_hamamatsu(curr_process_files);

        %% Save preprocessed widefield data locally

        local_save_path = fileparts(curr_process_files{1});

        % Assume 2 colors in order of blue/purple
        color_names = {'blue','violet'};

        % Save frame information in experiment folder
        frame_info_fn = fullfile(local_save_path,'widefield_frame_info');
        save(frame_info_fn,'frame_info','-v7.3');

        % Save mean images in experiment folder by color
        for curr_color = 1:length(color_names)
            curr_mean_im_fn = fullfile(local_save_path, ...
                sprintf('meanImage_%s.npy',color_names{curr_color}));
            writeNPY(im_avg_color(:,:,curr_color),curr_mean_im_fn);
        end

        % Save spatial components in experiment (animal/day) folder by color
        for curr_color = 1:length(color_names)
            curr_U_fn = fullfile(local_save_path, ...
                sprintf('svdSpatialComponents_%s.npy',color_names{curr_color}));
            writeNPY(U{curr_color},curr_U_fn);
        end

        % Save temporal components in associated recording folders
        for curr_recording = 1:size(Vrec,1)
            for curr_color = 1:length(color_names)
                % Put V's into separate recording paths
                curr_V_fn = fullfile(local_save_path,sprintf('recording_%d',curr_recording), ...
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
        local_data_dir = dir(local_save_path);

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

        %%% TEMPORARY: JUST ASSUME PROTOCOLS ARE IN ORDER OF RECORDINGS
        %     % Get timestamp of first frame in each recording
        %     [~,recording_start_frame] = unique([frame_info.rec_idx]);
        %     frame_timestamp_cat = [frame_info.timestamp];
        %     recording_start_times = str2num(char(frame_timestamp_cat(recording_start_frame),'HHmm'));

        % Get Protocol folder with closest previous time for each recording
        % NOTE: THIS DOESN'T WORK! THE TIMESTAMPS ON THE VIDEOS ARE TOTALLY OFF
        % FROM THE PROTOCOL TIMES?? E.G. A VIDEO OFTEN STARTS AFTER THE
        % TIMESTAMP FOR THE NEXT PROTOCOL, SO THE TIMESTAMP IS IMPOSSIBLE
        curr_server_path = strrep(fileparts(local_save_path), ...
            plab.locations.local_data_path,plab.locations.server_data_path);
        curr_server_dir = dir(curr_server_path);
        [protocol_paths,protocol_regexp] = regexp({curr_server_dir.name},'Protocol_(\d*)','match','tokens');
        protocol_paths_cat = horzcat(protocol_paths{:});
        protocol_regexp_cat = cellfun(@(x) horzcat(x{:}),protocol_regexp,'uni',false);
        curr_server_protocol_times = cellfun(@str2num,horzcat(protocol_regexp_cat{:}));

        %     recording_protocol_idx = arrayfun(@(x) ...
        %         find(recording_start_times(x) - curr_server_protocol_times > 0,1,'last'), ...
        %         1:length(recording_start_times));
        recording_protocol_idx = 1:length(curr_server_protocol_times);

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
            curr_hierarchy_path = fileparts(curr_process_files);
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








