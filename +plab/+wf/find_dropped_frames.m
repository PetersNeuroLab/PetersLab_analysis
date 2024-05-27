function [dropped_frames,dropped_frame_idx] = find_dropped_frames(widefield_metadata_fn,plot_flag)
% [dropped_frames,dropped_frame_idx] = find_dropped_frames(widefield_metadata_fn,plot_flag)
%
% Determine if/which widefield frames were dropped
%
% [Inputs]
% widefield_metadata_fn: filename for widefield metadata
% plot_flag: flag to plot dropped frames (default on)
%
% [Outputs] 
% dropped_frames: fractional index of dropped frame (e.g. 25.5)
% dropped_frame_idx: boolean vector of dropped frames

if ~exist('plot_flag','var') || isempty(plot_flag)
    plot_flag = true;
end

% Load widefield metadata (recorded from plab.widefield)
fid = fopen(widefield_metadata_fn);
widefield_metadata = reshape(fread(fid,'double'),9,[]);
fclose(fid);

% Get time difference between frame uploads
frame_upload_time = datetime(widefield_metadata(4:9,:)');
frame_upload_time_diff = seconds(diff(frame_upload_time));

% Find where upload time was > 1.5x mean (= skipped a frame)
frame_interval = median(frame_upload_time_diff);
long_frametime_idx = find(frame_upload_time_diff > frame_interval*1.5) + 1;

% For each skipped frame: check if the correct number was uploaded (e.g. if
% interval was 3x, check that 2 frames were uploaded immediately after the
% delayed frame to account for all 3 frames)
% (record dropped frames as fractional frame indicies)
dropped_frames = nan(1,0);

multi_frame_grab_timethresh = frame_interval/2;
for curr_skipped_frame = reshape(long_frametime_idx,1,[])
    % Get number of frames likely skipped
    n_skipped_frames = round(frame_upload_time_diff(curr_skipped_frame-1)/frame_interval);

    % Check if correct number of frames grabbed together after skip
    % (after long time, n frametimes which were under normal frame time)
    long_frametime_n_collected_frames = ...
        1 + sum(frame_upload_time_diff(curr_skipped_frame-1 + [1:n_skipped_frames-1]) < ...
        multi_frame_grab_timethresh);

    % If skipped frames doesn't match collected frames, record drop (assume
    % from frame after the long frametime)
    if n_skipped_frames ~= long_frametime_n_collected_frames
        n_dropped_frames = n_skipped_frames - long_frametime_n_collected_frames;
        dropped_frame_linspace = linspace(curr_skipped_frame,curr_skipped_frame+1,2+n_dropped_frames)';
        dropped_frames = vertcat(dropped_frames,dropped_frame_linspace(2:end-1));
    end
end

% Make boolean array of dropped frames
n_frames = size(widefield_metadata,2);
all_frame_idx = sort(vertcat((1:n_frames)',dropped_frames));
dropped_frame_idx = mod(all_frame_idx,1) ~= 0;

% Plot frame time and assumed dropped frame
if plot_flag && any(dropped_frames)
    figure; hold on;
    plot([NaN;frame_upload_time_diff],'.k');
    xline(dropped_frames,'r');
    title({'Widefield dropped frames:',widefield_metadata_fn},'interpreter','none');
end







