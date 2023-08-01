
%%% working on this - not sure about keeping
%%% not sure if assumptions are correct, also maybe cross-reference with
%%% timelite to see if there are any problems first?


widefield_metadata_fn = ...
    plab.locations.make_server_filename(animal,rec_day,[], ...
            'widefield',sprintf('widefield_%s_metadata.bin',rec_time));

% Load widefield metadata (recorded from plab.widefield)
fid = fopen(widefield_metadata_fn);
widefield_metadata = reshape(fread(fid,'double'),9,[]);
fclose(fid);

% Get time difference between frame uploads
frame_upload_time = datetime(widefield_metadata(4:9,:)');
frame_upload_time_diff = seconds(diff(frame_upload_time));

% Find where upload time was > 1.5x mean (= skipped a frame)
frame_interval = median(frame_upload_time_diff);
skipped_frame_idx = find(frame_upload_time_diff > frame_interval*1.5);

% For each skipped frame: check if the correct number was uploaded (e.g. if
% interval was 3x, check that 2 frames were uploaded immediately after the
% delayed frame to account for all 3 frames)
% (define threshold to define grabbing multiple frames together)
multi_frame_grab_timethresh = frame_interval/2;
for curr_skipped_frame = skipped_frame_idx
    % Get number of frames likely skipped
    n_skipped_frames = round(frame_upload_time_diff(curr_skipped_frame)/frame_interval);
    % Check if correct number of frames grabbed together after skip
    any_dropped_frames = ...
        any(frame_upload_time_diff(curr_skipped_frame + [1:n_skipped_frames-1]) > ...
        multi_frame_grab_timethresh);
    % If there are dropped frames, assume it's from the end (e.g. if 4
    % frames skipped and 2 frames dropped, assume frames 3-4 dropped)
    
    %%%% currently here

end














