function [U,Vrec,im_avg,frame_info] = preprocess_widefield_hamamatsu(im_path)
% [U,Vrec,im_color_avg,frame_info] = AP_preprocess_widefield_pco(im_path)
%
% SVD-compress widefield imaging from Hamamatsu ORCA-Flash 4.0 v3
% Assumes: 
% - alternating 2-color imaging that resets order on recording start
% - recordings are defined by timestamp gaps of >2s
%
% Input -- 
% im_path: path containing widefield images as TIFFs
%
% Outputs -- 
% U: SVD spatial components (by color)
% Vrec: SVD temporal components split by recording (recording x color)
% im_avg: average raw image (by color)
% frame_info: header information for each frame 


verbose = true; % Turn off messages by default


%% Get image filenames

im_files = dir(fullfile(im_path,'*.tif'));


%% Get header information from all frames

if verbose; disp('Getting image headers...'); end

% Loop through all files, get frame number and timestamp

for curr_im=1:length(im_files)
    curr_im_fn = fullfile(im_path,im_files(curr_im).name);
    file_info = imfinfo(curr_im_fn);
    
    % get file metadata
    file_md = {file_info.ImageDescription};

    % using the first one, save out the information for the whole recording
    frame_md = file_md{1};

    % find indexes for the title and the content
    all_title_beg_idx = strfind(frame_md, '[');
    all_title_end_idx = strfind(frame_md, ']');
    all_section_beg_idx = all_title_end_idx+1;
    all_section_end_idx = [all_section_beg_idx(2:end)-1, length(frame_md)];   

    % go through each section and pull content
    for n_section=1:length(all_section_beg_idx)-1 % exclude the last section
        
        % get section title and get rid of extra characters
        title = frame_md(all_title_beg_idx(n_section):all_title_end_idx(n_section));
        title = lower(strrep(erase(title,{'[ ', ' ]'}),' ', '_'));
    
        % get section contents
        section_str = frame_md(all_section_beg_idx(n_section):all_section_end_idx(n_section));
    
        % split by .. = ..
        name_pattern = '(?<name>(\w+).*?)';
        values_pattern = '(?<value>.*?(\w+).*?\n)';
        expr = [name_pattern ' = ' values_pattern];
        test = regexp(section_str, expr, 'names');
    
        % save in frame_info 
        for val_idx=1:length(test)
            name = strrep(test(val_idx).name,' ', '_');
            value = test(val_idx).value;
            frame_info(curr_im).(title).(name) = value(1:end-2);
        end
    end

    % get timestamp
    timestamp_section = frame_md(1:all_title_beg_idx(1)-1);
    expr = '\d*.[a-z]+.\d*.\d*:\d*:\d*';
    timestamp_str = regexpi(timestamp_section, expr, 'match');
    frame_info(curr_im).timestamp = repmat(datetime(timestamp_str,...
        'InputFormat','dd MMM yyyy HH:mm:ss', ...
        'Format', 'yyyy-MMM-dd HH:mm:ss.SSSS'), ...
        1, length(file_info));

    % get times for all frames
    name_pattern = '(?<name>Time_From_+(Start|Last))';
    time_pattern = '(?<time>\d\d:\d\d:\d\d.\d\d\d\d)';
    expr = [name_pattern ' = ' time_pattern];
    capture_times = regexp(file_md, expr, 'names');

    % convert both time from start and time from last to seconds
    F = 'hh:mm:ss.SSSS';
    time_from_last = cellfun(@(X) ...
        seconds(duration(X(strcmp({X.name},'Time_From_Last')).time, ...
        'InputFormat', F, 'Format', F)), capture_times);
    time_from_start = cellfun(@(X) ...
        seconds(duration(X(strcmp({X.name},'Time_From_Start')).time, ...
        'InputFormat', F, 'Format', F)), capture_times);

    % Store info for file
    frame_info(curr_im).frame_num(:) = 1:length(file_info);
    frame_info(curr_im).time_from_last(:) = time_from_last;
    frame_info(curr_im).time_from_start(:) = time_from_start;
    frame_info(curr_im).timestamp.Second = frame_info(curr_im).timestamp.Second + time_from_start;

end


%% Get illumination color for each frame
% Assume: blue/violet alternating, with blue starting whenever there is a
% >2s gap (= new recording, which starts on blue)

% Get total number of frames
n_frames = sum(cellfun(@length,{frame_info.frame_num}));

% Find recording boundaries (EITHER: start button was pressed and time
% frome last frame is zero, OR: long time between frames, tag on number of
% frames+1 at end to ensure interpolation works even if one recording)
recording_boundary_thresh = 2; % seconds between frames to define recording
recording_start_frame_idx = [find( ...
    [frame_info.time_from_last] == 0 | ...
    [frame_info.time_from_last] >= recording_boundary_thresh),n_frames+1];

% Get recording for each frame
im_rec_idx = mat2cell( ....
    interp1(recording_start_frame_idx,1:length(recording_start_frame_idx), ...
    1:n_frames,'previous','extrap'), ...
    1,cellfun(@length,{frame_info.frame_num}));
[frame_info.rec_idx] = im_rec_idx{:};

% Get illumination color of frame (alternate starting at each recording)
n_colors = 2;
im_frame_color = mat2cell( ...
    1+mod((1:n_frames) - ...
    interp1(recording_start_frame_idx,recording_start_frame_idx,...
    1:n_frames,'previous','extrap'),n_colors), ...
    1,cellfun(@length,{frame_info.frame_num}));
[frame_info.color] = im_frame_color{:};


%% Set pixels to keep 
% % (no timestamp to remove)

im_info = imfinfo(fullfile(im_path,im_files(1).name));
im_size = [im_info(1).Height,im_info(1).Width];

im_px_loc = {[1,im_size(1)],[1,im_size(2)],[1,Inf]};
im_grab_size = cellfun(@(x) diff(x)+1,im_px_loc(1:2));


%% Create moving- and total-average images
% (moving average is used to create SVD spatial components)

% Set moving average number of frames
n_frame_avg = 15;

if verbose; disp('Building image moving average by color...'); end

% Loop through images, cumulatively build averages by illumination color
im_avg = zeros(im_grab_size(1),im_grab_size(2),n_colors);
im_mov_avg = cell(length(im_files),n_colors);
for curr_im = 1:length(im_files)
   
    curr_im_fn = fullfile(im_path,im_files(curr_im).name);
    im = single(tiffreadVolume(curr_im_fn,'PixelRegion',im_px_loc));

    % Loop through illumination colors
    for curr_color = 1:n_colors
        % Get color index forifif frames in current image
        curr_frame_color_idx = frame_info(curr_im).color == curr_color;

        % Cumulatively add average image
        curr_color_partial = ...
            sum(im(:,:,curr_frame_color_idx)./sum([frame_info.color] == curr_color),3);
        im_avg(:,:,curr_color) = im_avg(:,:,curr_color) + ...
            curr_color_partial;

        % Get moving average (truncate based on moving avg modulus)
        curr_n_frames = sum(curr_frame_color_idx);
        curr_frame_avg_idx = find(curr_frame_color_idx, ...
            curr_n_frames - mod(curr_n_frames,n_frame_avg));
        im_mov_avg{curr_im,curr_color} = ...
            permute(mean(reshape(im(:,:,curr_frame_avg_idx), ...
            size(im,1),size(im,2),n_frame_avg,[]),3),[1,2,4,3]);
    end
end


%% Do SVD on moving-average images
% (keep U and S, don't keep V since U will be applied to full dataset next)

if verbose; disp('Running SVD on moving average images by color...'); end

[U,~,~] = arrayfun(@(color) ...
    svd(reshape(cat(3,im_mov_avg{:,color}),prod(im_grab_size),[]),'econ'), ...
    1:n_colors,'uni',false);

% Reshape U into pixels row x pixels column x components
U = cellfun(@(x) reshape(x,im_grab_size(1),im_grab_size(2),[]),U,'uni',false);


%% Apply spatial components (U's) from SVD to full data
% (note: spatial components are applied as U' * mean-subtracted data, so
% the resulting matrix is equivalent to S*V but just called 'V')

if verbose; disp('Applying SVD spatial components to full data...'); end

V = cell(length(im_files),n_colors);
for curr_im = 1:length(im_files)
   
    curr_im_fn = fullfile(im_path,im_files(curr_im).name);
    im = single(tiffreadVolume(curr_im_fn,'PixelRegion',im_px_loc));

    % Loop through illumination colors
    for curr_color = 1:n_colors
        % Get color index for frames in current image
        curr_frame_color_idx = frame_info(curr_im).color == curr_color;

        % Apply spatial components to mean-subtracted data
        V{curr_im,curr_color} = ...
            reshape(U{curr_color},[],size(U{curr_color},3))' * ...
            (reshape(im(:,:,curr_frame_color_idx),[],sum(curr_frame_color_idx)) - ...
            reshape(im_avg(:,:,curr_color),[],1));
    end
end


%% Split V's by recording (instead of by file)

if verbose; disp('Applying SVD spatial components to full data...');end

% Store V's as recordings x color
Vrec = cell(length(recording_start_frame_idx),n_colors);

frame_color_cat = horzcat(frame_info.color)';
frame_rec_idx_cat = horzcat(frame_info.rec_idx)';
for curr_color = 1:n_colors

    % Split concatenated V by recording index
    curr_V_cat = horzcat(V{:,curr_color});
    Vrec(:,curr_color) = ...
        mat2cell(curr_V_cat,size(curr_V_cat,1), ...
        accumarray(frame_rec_idx_cat(frame_color_cat == curr_color),1));
    
end

if verbose; disp('Finished SVD.'); end

















































