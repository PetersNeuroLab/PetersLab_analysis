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


%% Perform SVD on subset of frames

% Thin frames (regardless of color number)
if verbose; disp('Grabbing thinned set of frames...'); end

% Thin the number of frames by a factor by taking N frames every K frames
skip_frames = 100; % (frames to skip at start/end to avoid artifacts)
thin_factor = 15;
thinned_frame_idx = cell(size(im_n_frames));
for curr_file_idx = 1:length(data_dir)
    curr_n_frames = im_n_frames(curr_file_idx);
    curr_use_frames = skip_frames:curr_n_frames-skip_frames;

    n_thin_groups = curr_n_frames/thin_factor;
    thin_frame_group = min(floor(linspace(1,n_thin_groups+1,length(curr_use_frames))),n_thin_groups);
    thinned_frame_idx{curr_file_idx} = curr_use_frames(mod(thin_frame_group,thin_factor) == 1);
end

% Split thinned frames by color (file x color)
thinned_frame_idx_color = cell(length(thinned_frame_idx),n_colors);
for curr_color = 1:n_colors
    thinned_frame_idx_color(:,curr_color) = ...
        cellfun(@(x) x(mod(x-1,n_colors) == (curr_color-1)), ...
        thinned_frame_idx,'uni',false);
end

% Grab frames indexed by thinning (1 x color)
im_raw_thinned = cellfun(@(x) zeros([im_size,x],'single'), ...
    num2cell(sum(cellfun(@length,thinned_frame_idx_color),1)),'uni',false);

for curr_color = 1:n_colors

    curr_frame_counter = 1;
    for curr_file_idx = 1:length(data_dir)

        % Open file for reading
        curr_data_filename = fullfile( ...
            data_dir(curr_file_idx).folder, ...
            data_dir(curr_file_idx).name);

        curr_data_fid = fopen(curr_data_filename,'r');

        % Load all selected frames
        curr_load_frames = thinned_frame_idx_color{curr_file_idx,curr_color};

        for curr_frame_idx = 1:length(curr_load_frames)
            curr_frame_location = prod(im_size)*(curr_load_frames(curr_frame_idx)-1)*2; % uint16: *2 bytes
            fseek(curr_data_fid,curr_frame_location,-1);
            im_raw_thinned{curr_color}(:,:,curr_frame_counter) = ...
                reshape(fread(curr_data_fid,prod(im_size),'uint16=>single'),im_size);
            curr_frame_counter = curr_frame_counter + 1;
        end

        % Close file
        fclose(curr_data_fid);
    end
end

% Get thinned image average
im_avg = cellfun(@(x) mean(x,3),im_raw_thinned,'uni',false);

% Do SVD on images, keep spatial components (U's)
if verbose; disp('Performing SVD...'); end

[U_full,~,~] = cellfun(@(x) svd(reshape(x,prod(im_size),[]),'econ'), ...
    im_raw_thinned,'uni',false);

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

        % Read in chunk of frames (flat)
        curr_im = reshape(fread(curr_data_fid, ...
            prod(im_size)*max_load_frames,'uint16=>single'),prod(im_size),[]);

        % Loop through colors
        for curr_color = 1:n_colors
            % Assume alternating (load in multiples to start on same)
            curr_color_frames = mod((1:size(curr_im,2))-1,n_colors) == (curr_color-1);

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












