function [U,V,im_avg] = preprocess_widefield(data_path,n_colors)
% [U,V,im_color_avg,frame_info] = preprocess_widefield_hamamatsu(im_files,color_split)
%
% SVD-compress widefield imaging from Hamamatsu ORCA-Flash 4.0 v3
% Assumes:
% - data was recorded in widefield GUI (plab.widefield)
% - each file corresponds to a separate recording
%
% Input --
% im_path: path containing widefield images as TIFFs
% n_colors: number of colors to split SVD processing, assume alternating
% (note: single SVD on multi-color seems fine)
%
% Outputs --
% U: SVD spatial components (color x 1)
% V: SVD temporal components split by recording (recording x color)
% im_avg: average raw image (color x 1)

verbose = true; % Turn off messages by default

%% Set maximum number of components to keep

max_components = 2000;

%% Get data and metadata filenames

% Get filenames (data/metadata from widefield GUI)
data_dir = dir(fullfile(data_path,'*_data.bin'));
metadata_dir = dir(fullfile(data_path,'*_metadata.bin'));

% Check that data and metadata are matched
if length(data_dir) ~= length(metadata_dir) && ...
        ~all(strcmp(extract({data_dir.name},digitsPattern), ...
        extract({metadata_dir.name},digitsPattern)))
    error('Widefield %s: mismatched data/metadata',data_path);
end

% Get recording times from filename (not used)
recording_times = extract({data_dir.name},digitsPattern);

%% Check metadata, get image size and colors, check for dropped frames

im_size_allfiles = nan(length(metadata_dir),2);
im_n_frames = nan(length(metadata_dir),1);
im_color = cell(length(metadata_dir),1);
for curr_metadata_idx = 1:length(metadata_dir)

    curr_metadata_filename =  ...
        fullfile(metadata_dir(curr_metadata_idx).folder, ...
        metadata_dir(curr_metadata_idx).name);

    % Load metadata
    % Metadata format: 9 x n frames
    % [image height, image width, frame number, timestamp (y,m,d,H,M,S)]
    curr_metadata_fid = fopen(curr_metadata_filename,'r');
    curr_metadata = reshape(fread(curr_metadata_fid,'double'),9,[]);
    fclose(curr_metadata_fid);

    % Get frame size (from first frame)
    im_size_allfiles(curr_metadata_idx,:) = curr_metadata(1:2,1);

    % Check frames are continuous
    if any(diff(curr_metadata(3,:)) ~= 1)
        figure;plot(diff(curr_metadata(3,:)));
        xlabel('Measured frame');ylabel('\DeltaFrame number')
        error('Widefield %s: Frames not continuous',data_path);
    end
    im_n_frames(curr_metadata_idx) = size(curr_metadata,2);

    % Check for dropped frames
    [~,dropped_frame_idx] = ...
        plab.wf.find_dropped_frames(curr_metadata_filename);

    % Set frame color (assume alternating, account for dropped frames)
    im_color_including_dropped = mod((1:length(dropped_frame_idx))-1,n_colors)+1;
    im_color{curr_metadata_idx} = im_color_including_dropped(~dropped_frame_idx);

    % Get timestamp, convert to matlab format (not used)
    frame_timestamps = datetime( ...
        curr_metadata(4,:),curr_metadata(5,:),curr_metadata(6,:), ...
        curr_metadata(7,:),curr_metadata(8,:),curr_metadata(9,:));

end

% Ensure that all recordings have the same image size
if length(unique(im_size_allfiles(:,1))) ~= 1 || ...
        length(unique(im_size_allfiles(:,2))) ~= 1
    error('Widefield %s: different image sizes across files',data_path);
end

% Set image size (from first file)
im_size = im_size_allfiles(1,:);


%% Perform SVD on subsample of frames

if verbose; disp('Grabbing downsampled set of frames...'); end

% Downsample the number of frames (1/N frames by color)
skip_frames = 100; % (frames to skip at start/end to avoid artifacts)
downsample_factor = 15;
downsampled_frame_idx_color = cell(length(im_n_frames),n_colors);
for curr_file_idx = 1:length(data_dir)
    for curr_color = 1:n_colors
        curr_frames = find(im_color{curr_file_idx} == curr_color);
        downsampled_frame_idx_color{curr_file_idx,curr_color} = ...
            curr_frames(skip_frames:downsample_factor:end-skip_frames);
    end
end

downsampled_frame_idx = arrayfun(@(color) ...
    mat2cell(1:length(horzcat(downsampled_frame_idx_color{:,color})), ...
    1,cellfun(@length,downsampled_frame_idx_color(:,color))), ...
    1:n_colors,'uni',false);

% Grab downsampled subsets of frames (file x color)
im_raw_downsampled = cellfun(@(x) zeros([im_size,x],'single'), ...
    num2cell(sum(cellfun(@length,downsampled_frame_idx_color),1)),'uni',false);

for curr_color = 1:n_colors
    for curr_file_idx = 1:length(data_dir)

        % Open file for reading
        curr_data_filename = fullfile( ...
            data_dir(curr_file_idx).folder, ...
            data_dir(curr_file_idx).name);

        curr_data_fid = fopen(curr_data_filename,'r');

        % Load all selected frames
        curr_load_frames = downsampled_frame_idx_color{curr_file_idx,curr_color};
        for curr_frame_idx = 1:length(curr_load_frames)

            curr_frame_location = prod(im_size)*(curr_load_frames(curr_frame_idx)-1)*2; % uint16: *2 bytes
            fseek(curr_data_fid,curr_frame_location,-1);

            curr_downsampled_frame_idx = downsampled_frame_idx{curr_color}{curr_file_idx}(curr_frame_idx);
            im_raw_downsampled{curr_color}(:,:,curr_downsampled_frame_idx) = ...
                reshape(fread(curr_data_fid,prod(im_size),'uint16=>single'),im_size);
        end

        % Close file
        fclose(curr_data_fid);
    end
end

% Get image average
im_avg = cellfun(@(x) mean(x,3),im_raw_downsampled,'uni',false);

% Do SVD on images, keep spatial components (U's)
if verbose; disp('Performing SVD...'); end

[U_full,~,~] = cellfun(@(x) svd(reshape(x,prod(im_size),[]),'econ'), ...
    im_raw_downsampled,'uni',false);

% Keep only the max number of components
U_flat = cellfun(@(x) x(:,1:min(size(x,2),max_components)),U_full,'uni',false);

% Clear the full U's to save space
clear U_full

% Reshape U into pixels row x pixels column x components (for saving)
% (and only keep the maximum number of set components)
U = cellfun(@(x) reshape(x,im_size(1),im_size(2),[]),U_flat,'uni',false);


%% Apply spatial components (U's) from SVD to full data
% (note: spatial components are applied as U' * mean-subtracted data, so
% the resulting matrix is equivalent to S*V but just called 'V')

if verbose; disp('Applying SVD spatial components to full data...'); end

max_load_frames = 7500; % (empirical: the biggest chunk loadable)

V = cell(length(data_dir),n_colors);
for curr_file_idx = 1:length(data_dir)

    % Open file for reading
    curr_data_filename = fullfile( ...
        data_dir(curr_file_idx).folder, ...
        data_dir(curr_file_idx).name);

    curr_data_fid = fopen(curr_data_filename,'r');

    % Loop through current file until the end is reached
    while ~feof(curr_data_fid)

        frame_bytes = prod(im_size)*2; % uint16: *2 bytes

        % Get starting frame index from intial position
        curr_first_frame = (ftell(curr_data_fid)/frame_bytes)+1;

        % Read in chunk of frames (flat)
        curr_im = reshape(fread(curr_data_fid, ...
            prod(im_size)*max_load_frames,'uint16=>single'),prod(im_size),[]);

        % Get last frame index from ending position
        curr_last_frame = ftell(curr_data_fid)/frame_bytes;

        % Get loaded frame index
        curr_frame_idx = curr_first_frame:curr_last_frame;

        % Loop through colors
        for curr_color = 1:n_colors
            % Assume alternating (load in multiples to start on same)
            curr_color_frames = im_color{curr_file_idx}(curr_frame_idx) == curr_color;

            % Apply spatial components to mean-subtracted data
            curr_V = U_flat{curr_color}'* ...
                (curr_im(:,curr_color_frames) - reshape(im_avg{curr_color},[],1));

            % Build full V by concatenating
            V{curr_file_idx,curr_color} = horzcat(V{curr_file_idx,curr_color},curr_V);
        end
    end

    % Close file
    fclose(curr_data_fid);

end

end












