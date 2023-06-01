function [U,V,im_avg] = preprocess_widefield(data_path)
% [U,V,im_color_avg,frame_info] = preprocess_widefield_hamamatsu(im_files)
%
% SVD-compress widefield imaging from Hamamatsu ORCA-Flash 4.0 v3
% Assumes: 
% - alternating 2-color imaging that resets order on recording start
% - data was recorded in widefield GUI (plab.widefield)
% - each file corresponds to a separate recording
%
% Input -- 
% im_path: path containing widefield images as TIFFs
%
% Outputs -- 
% U: SVD spatial components (by color)
% V: SVD temporal components split by recording (recording x color)
% im_avg: average raw image (by color)

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

%% Check metadata and get image size

im_size_allfiles = nan(length(metadata_dir),2);
im_n_frames = nan(length(metadata_dir),1);
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

%% Create moving-average images
% (moving average is used to create SVD spatial components)

if verbose; disp('Building image moving average by color...'); end

n_colors = 2;

% Set moving average number of frames
n_frame_avg = 15;

% Set max frames to load at once (empirical, avoid memory ceiling)
max_load_frames = n_frame_avg*250*n_colors;

% Initialize moving average (height x width x frames x color)
n_mov_avg_frames = sum(floor((im_n_frames/n_colors)/n_frame_avg));
im_mov_avg = zeros(im_size(1),im_size(2),n_mov_avg_frames,n_colors,'single');

% Loop through files and build moving average for each color
im_move_avg_frameidx = 1;
for curr_file_idx = 1:length(data_dir)

    % Open file for reading
    curr_data_filename = fullfile( ...
        data_dir(curr_file_idx).folder, ...
        data_dir(curr_file_idx).name);

    curr_data_fid = fopen(curr_data_filename,'r');

    % Loop through current file until the end is reached
    while ~feof(curr_data_fid)

        % Read in chunk of frames (flat)
        curr_im = reshape(fread(curr_data_fid, ...
            prod(im_size)*max_load_frames,'uint16=>single'),prod(im_size),[]);

        % Get moving average by color
        % (only use multiples of n_frame_avg)
        curr_n_color_frames = floor(floor(size(curr_im,2)/2)/n_frame_avg);
        curr_im_mov_avg = reshape(permute(mean(reshape( ...
            curr_im(:,1:curr_n_color_frames*n_colors*n_frame_avg), ...
            prod(im_size),n_colors,n_frame_avg,[]),3),[1,4,2,3]), ...
            im_size(1),im_size(2),[],n_colors);

        % Store current moving average, update frame index
        im_move_avg_lastframeidx = im_move_avg_frameidx+size(curr_im_mov_avg,3)-1;
        im_mov_avg(:,:,im_move_avg_frameidx:im_move_avg_lastframeidx,:) = curr_im_mov_avg;
        im_move_avg_frameidx = im_move_avg_lastframeidx+1;
    end

    % Close file
    fclose(curr_data_fid);
end

% Get total image average
im_avg = squeeze(mean(im_mov_avg,3));

%% Do SVD on moving-average images
% (keep U and S, don't keep V since U will be applied to full dataset next)

if verbose; disp('Running SVD on moving average images by color...'); end

[U_full,~,~] = arrayfun(@(color) ...
    svd(reshape(cat(3,im_mov_avg(:,:,:,color)),prod(im_size),[]),'econ'), ...
    1:n_colors,'uni',false);

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

V = cell(length(data_dir),n_colors);
for curr_file_idx = 1:length(data_dir)

    % Open file for reading
    curr_data_filename = fullfile( ...
        data_dir(curr_file_idx).folder, ...
        data_dir(curr_file_idx).name);

    curr_data_fid = fopen(curr_data_filename,'r');

    % Loop through current file until the end is reached
    while ~feof(curr_data_fid)

        % Read in chunk of frames (flat)
        curr_im = reshape(fread(curr_data_fid, ...
            prod(im_size)*max_load_frames,'uint16=>single'),prod(im_size),[]);

        % Loop through colors
        for curr_color = 1:n_colors
            % Assume alternating (load in multiples to start on same)
            curr_color_frames = mod(0:size(curr_im,2)-1,n_colors)+1 == curr_color;

            % Apply spatial components to mean-subtracted data
            curr_V = U_flat{curr_color}'* ...
                (curr_im(:,curr_color_frames) - reshape(im_avg(:,:,curr_color),[],1));

            % Build full V by concatenating
            V{curr_file_idx,curr_color} = horzcat(V{curr_file_idx,curr_color},curr_V);
        end
    end

    % Close file
    fclose(curr_data_fid);

end

end














































