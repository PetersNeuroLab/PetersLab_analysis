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
% delayed_frames: frames that were delayed from normal frame rate

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
delayed_frames = find(frame_upload_time_diff > frame_interval*1.5) + 1;

% For each skipped frame: check if the correct number was uploaded 
% (e.g. get expected frames by time from the anomaly to the next normal
% time, check if all frames are accounted for or if any are missing)
% (record dropped frames as fractional frame indicies)
dropped_frames = nan(1,0);
last_frame_checked = 0;
for curr_longframe = reshape(delayed_frames,1,[])

    % If the current long frame fell within last checked, skip
    if curr_longframe <= last_frame_checked
        continue
    end

    % Get the next pair of frames collected with a normal interval
    normal_interval_leeway = 0.1; % fraction of normal frame interval
    normal_interval = frame_interval.*(1+[-1,1].*normal_interval_leeway);
 
    next_normal_interval_frame = curr_longframe +  find( ...
        frame_upload_time_diff(curr_longframe:end) >= normal_interval(1) & ...
        frame_upload_time_diff(curr_longframe:end) <= normal_interval(2),1) - 1;

    % Get number of frames skipped (expected from time minus collected)
    % across adjoining abnormal frame times
    n_dropped_frames = ...
        round(sum(frame_upload_time_diff(curr_longframe-1:next_normal_interval_frame-1))/frame_interval) - ...
        (length(curr_longframe-1:next_normal_interval_frame-1));

    if n_dropped_frames > 0
        dropped_frame_linspace = linspace(curr_longframe,curr_longframe+1,2+n_dropped_frames)';
        dropped_frames = vertcat(dropped_frames,dropped_frame_linspace(2:end-1));
    elseif n_dropped_frames < 0
        % If there are more frames collected than expected, bug in code
        error('Widefield dropped frame incorrectly estimated')
    end

    % Update the last frame checked
    last_frame_checked = next_normal_interval_frame;
end

% Make boolean array of dropped frames
n_frames = size(widefield_metadata,2);
all_frame_idx = sort(vertcat((1:n_frames)',dropped_frames));
dropped_frame_idx = mod(all_frame_idx,1) ~= 0;

% Plot frame time and assumed dropped frame
if plot_flag && ~isempty(dropped_frames)
    figure; hold on;
    plot([NaN;frame_upload_time_diff],'.k');
    xline(dropped_frames,'r');
    title({'Widefield dropped frames:',widefield_metadata_fn},'interpreter','none');
end













