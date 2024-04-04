function vfs = retinotopy_vfs(animal,rec_day,rec_time)
% vfs = retinotopy_vfs(animal,rec_day,rec_time)
%
% Create visual field sign map from Bonsai workflow 'sparse_noise'

%% Load Timelite stim/widefield times

% Set level for TTL threshold
ttl_thresh = 2;

% Load timelite
timelite_fn = plab.locations.filename('server',animal,rec_day,rec_time,'timelite.mat');
timelite = load(timelite_fn);

% Widefield times
widefield_idx = strcmp({timelite.daq_info.channel_name}, 'widefield_camera');
widefield_thresh = timelite.data(:,widefield_idx) >= ttl_thresh;
widefield_expose_times = timelite.timestamps(find(diff(widefield_thresh) == 1) + 1);
% (if stuck high at end, long dark exposure as first frame, add first timepoint as timestamp)
if widefield_thresh(1)
    widefield_expose_times = [timelite.timestamps(1);widefield_expose_times];
end
% (if stuck high at the end, unrecorded bad frame: remove timestamp)
if widefield_thresh(end)
    widefield_expose_times(end) = [];
end

% Screen on times
screen_idx = strcmp({timelite.daq_info.channel_name}, 'stim_screen');
screen_on = timelite.data(:,screen_idx) > ttl_thresh;

% Photodiode flips
photodiode_idx = strcmp({timelite.daq_info.channel_name}, 'photodiode');
if all(screen_on)
    % (if no screen flicker, use as is)
    photodiode_trace = timelite.data(screen_on,photodiode_idx);
else
    % (if screen flicker: median filter and interpolate across flicker)
    photodiode_trace = ...
        interp1(timelite.timestamps(screen_on), ...
        medfilt1(timelite.data(screen_on,photodiode_idx),3), ...
        timelite.timestamps,'previous','extrap');
end
% (discretize into black/NaN/white, interpolate across NaN/intermediate)
% (e.g. simulate instantaneous flips and ignore intermediate values)
photodiode_bw_thresh = [0.5,2.8]; % [black,white]
photodiode_bw = nan(size(photodiode_trace));
photodiode_bw(photodiode_trace < photodiode_bw_thresh(1)) = 0;
photodiode_bw(photodiode_trace > photodiode_bw_thresh(2)) = 1;
% (if all intermediate photodiode, set to zero)
if all(isnan(photodiode_bw))
    photodiode_bw(:) = 0;
end
photodiode_bw_interp = interp1(find(~isnan(photodiode_bw)), ...
    photodiode_bw(~isnan(photodiode_bw)), ...
    1:length(photodiode_bw),'next','extrap')';

photodiode_flip_idx = find(diff(photodiode_bw_interp) ~= 0 & ...
    ~isnan(photodiode_bw_interp(2:end))) + 1;
photodiode_times = timelite.timestamps(photodiode_flip_idx);
photodiode_values = photodiode_bw_interp(photodiode_flip_idx);


%% Load Bonsai stimuli

% Get Bonsai workflow
bonsai_dir = dir(plab.locations.filename('server',animal,rec_day,rec_time,'bonsai'));
bonsai_workflow = bonsai_dir([bonsai_dir.isdir] & ~contains({bonsai_dir.name},'.')).name;

% Load Bonsai events (should be included in every workflow)
bonsai_events_fn = plab.locations.filename('server', ...
    animal,rec_day,rec_time,'bonsai','bonsai_events.csv');

if exist(bonsai_events_fn,'file') && ~isempty(readtable(bonsai_events_fn))
    % Set Bonsai timestamp format
    bonsai_table_opts = detectImportOptions(bonsai_events_fn);
    bonsai_table_opts = setvaropts(bonsai_table_opts,'Timestamp','Type','datetime', ...
        'InputFormat','yyyy-MM-dd''T''HH:mm:ss.SSSSSSSZ','TimeZone','local', ...
        'DatetimeFormat','yyyy-MM-dd HH:mm:ss.SSS');

    % Load Bonsai CSV file
    bonsai_events_raw = readtable(bonsai_events_fn,bonsai_table_opts);

    % Check for NaT timestamps, throw warning and flag if so
    if any(isnat(bonsai_events_raw.Timestamp))
        bad_bonsai_csv = true;
        warning('Bonsai file ends improperly: %s',bonsai_events_fn);
    else
        bad_bonsai_csv = false;
    end

    % Create nested structure for trial events
    trial_events = struct('parameters',cell(1),'values',cell(1),'timestamps',cell(1));

    % Save anything in "Trial 0" as a parameter
    parameter_idx = bonsai_events_raw.Trial == 0;
    unique_parameters = unique(bonsai_events_raw.Event(parameter_idx));
    for curr_parameter = unique_parameters'
        curr_parameter_idx = parameter_idx & strcmp(bonsai_events_raw.Event,curr_parameter);
        trial_events.parameters.(cell2mat(curr_parameter)) = bonsai_events_raw.Value(curr_parameter_idx);
    end

    % Loop through trials (excluding 0), save values and timestamps for all events
    % (exclude entries with empty events - happens sometimes on last entry)
    empty_events = cellfun(@isempty,bonsai_events_raw.Event);
    n_trials = max(bonsai_events_raw.Trial);
    unique_events = unique(bonsai_events_raw.Event(~parameter_idx & ~empty_events));
    for curr_trial = 1:n_trials
        for curr_event = unique_events'
            curr_event_idx = bonsai_events_raw.Trial == curr_trial & strcmp(bonsai_events_raw.Event,curr_event);
            trial_events.values(curr_trial).(cell2mat(curr_event)) = bonsai_events_raw.Value(curr_event_idx);
            trial_events.timestamps(curr_trial).(cell2mat(curr_event)) = bonsai_events_raw.Timestamp(curr_event_idx);
        end
    end
end

bonsai_noise_fn = plab.locations.filename('server', ...
    animal,rec_day,rec_time,'bonsai','NoiseLocations.bin');
fid = fopen(bonsai_noise_fn);

n_x_squares = trial_events.parameters.ScreenExtentX./trial_events.parameters.StimSize;
n_y_squares = trial_events.parameters.ScreenExtentY./trial_events.parameters.StimSize;

noise_locations = reshape(fread(fid),n_y_squares,n_x_squares,[]);
fclose(fid);

% Get stim times from photodiode (extrapolate: sparse noise photodiode
% flips every N stim to give a more robust signal)
if ~isfield(trial_events.parameters,'NthPhotodiodeFlip')
    % (if it wasn't defined, default to flipping on every stim)
    trial_events.parameters.NthPhotodiodeFlip = 1;
end
photodiode_stim_idx = 1:trial_events.parameters.NthPhotodiodeFlip:size(noise_locations,3);
% (check that the number of photodiode flips is expected)
if length(photodiode_stim_idx) ~= length(photodiode_times)
    if length(photodiode_stim_idx) < length(photodiode_times)
        % (rarely: Bonsai square to black temporarily, don't know why)
        % (fix? find when time differences on either side are less than a
        % threshold and remove those flips)
        photodiode_diff = diff(photodiode_times);
        photodiode_diff_thresh = mean(photodiode_diff)/2;
        bad_photodiode_idx = ...
            find(photodiode_diff(1:end-1) < photodiode_diff_thresh & ...
            photodiode_diff(2:end) < photodiode_diff_thresh) + 1;

        if (length(photodiode_times) - length(photodiode_stim_idx)) == ...
                length(bad_photodiode_idx)
            % (if detected bad flips even out the numbers, apply fix)
            photodiode_times(bad_photodiode_idx) = [];
        else
            % (otherwise, error)
            error('Sparse noise: photodiode > stim, unfixable')
        end
    else
        error('Sparse noise: photodiode < stim')
    end
end

stim_times = interp1(photodiode_stim_idx,photodiode_times, ...
    1:size(noise_locations,3),'linear','extrap')';


%% Load widefield data (just raw data)

% Load widefield data for all colors
widefield_colors = {'blue','violet'};

wf_day_path = plab.locations.filename('server',animal,rec_day,[],'widefield');
wf_rec_path = plab.locations.filename('server',animal,rec_day,rec_time,'widefield');

[wf_avg_all,wf_U_raw,wf_V_raw,wf_t_all] = deal(cell(length(widefield_colors),1));
for curr_wf = 1:length(widefield_colors)
    mean_image_fn = fullfile(wf_day_path,sprintf('meanImage_%s.npy',widefield_colors{curr_wf}));
    svdU_fn = fullfile(wf_day_path,sprintf('svdSpatialComponents_%s.npy',widefield_colors{curr_wf}));
    svdV_fn = fullfile(wf_rec_path,sprintf('svdTemporalComponents_%s.npy',widefield_colors{curr_wf}));

    wf_avg_all{curr_wf} = readNPY(mean_image_fn);
    wf_U_raw{curr_wf} = readNPY(svdU_fn);
    wf_V_raw{curr_wf} = readNPY(svdV_fn);

    % Timestamps: assume colors go in order (dictated by Arduino)
    wf_t_all{curr_wf} = widefield_expose_times(curr_wf:length(widefield_colors):end);
end


%% Calculate visual field sign map

% Use raw blue signal (best SNR)
surround_window = [0.3,0.5]; % 6s = [0.3,0.5], deconv = [0.05,0.15]
framerate = 1./nanmean(diff(wf_t_all{1}));
surround_samplerate = 1/(framerate*1);
surround_time = surround_window(1):surround_samplerate:surround_window(2);
response_n = nan(n_y_squares,n_x_squares);
response_grid = cell(n_y_squares,n_x_squares);
for px_y = 1:n_y_squares
    for px_x = 1:n_x_squares

        align_times = ...
            stim_times(find( ...
            (noise_locations(px_y,px_x,1:end-1) == 128 & ...
            noise_locations(px_y,px_x,2:end) == 255) | ...
            (noise_locations(px_y,px_x,1:end-1) == 128 & ...
            noise_locations(px_y,px_x,2:end) == 0))+1);

        response_n(px_y,px_x) = length(align_times);

        % Don't use times that fall outside of imaging
        align_times(align_times + surround_time(1) < wf_t_all{1}(2) | ...
            align_times + surround_time(2) > wf_t_all{1}(end)) = [];

        % Get stim-aligned responses, 2 choices:

        % 1) Interpolate times (slow - but supersamples so better)
        %         align_surround_times = bsxfun(@plus, align_times, surround_time);
        %         peri_stim_v = permute(mean(interp1(frame_t,fV',align_surround_times),1),[3,2,1]);

        % 2) Use closest frames to times (much faster - not different)
        align_surround_times = align_times + surround_time;
        frame_edges = [wf_t_all{1};wf_t_all{1}(end)+1/framerate];
        align_frames = discretize(align_surround_times,frame_edges);

        % Get stim-aligned baseline (at stim onset)
        align_baseline_times = align_times;
        align_frames_baseline = discretize(align_baseline_times,frame_edges);

        % Don't use NaN frames (delete, dirty)
        nan_stim = any(isnan(align_frames),2) | isnan(align_frames_baseline);
        align_frames(nan_stim,:) = [];
        align_frames_baseline(nan_stim,:) = [];

        % Define the peri-stim V's as subtracting first frame (baseline)
        peri_stim_v = ...
            reshape(wf_V_raw{1}(:,align_frames)',size(align_frames,1),size(align_frames,2),[]) - ...
            nanmean(reshape(wf_V_raw{1}(:,align_frames_baseline)',size(align_frames_baseline,1),size(align_frames_baseline,2),[]),2);

        mean_peri_stim_v = permute(mean(peri_stim_v,2),[3,1,2]);

        % Store V's
        response_grid{px_y,px_x} = mean_peri_stim_v;

    end
end

% Get position preference for every pixel
U_downsample_factor = 1; %2 if max method
screen_resize_scale = 1; %3 if max method
filter_sigma = (screen_resize_scale*2);

% Downsample U
[Uy,Ux,nSV] = size(wf_U_raw{1});
Ud = imresize(wf_U_raw{1},1/U_downsample_factor,'bilinear');

% Convert V responses to pixel responses
use_svs = 1:min(2000,size(Ud,3)); % can de-noise if reduced
n_boot = 10;

response_mean_bootstrap = cellfun(@(x) bootstrp(n_boot,@mean,x')',response_grid,'uni',false);

% Get visual field sign (for each bootstrap)
vfs_boot = nan(size(Ud,1),size(Ud,2),n_boot);
for curr_boot = 1:n_boot

    response_mean = cell2mat(cellfun(@(x) x(:,curr_boot),response_mean_bootstrap(:),'uni',false)');
    stim_im_px = reshape(permute(plab.wf.svd2px(Ud(:,:,use_svs), ...
        response_mean(use_svs,:)),[3,1,2]),n_y_squares,n_x_squares,[]);
    gauss_filt = fspecial('gaussian',[n_y_squares,n_x_squares],filter_sigma);
    stim_im_smoothed = imfilter(imresize(stim_im_px,screen_resize_scale,'bilinear'),gauss_filt);

    %     % (for troubleshooting: scroll through px stim responses)
    %     AP_imscroll(reshape(permute(stim_im_px,[3,1,2]),size(Ud,1),size(Ud,2),[]));
    %     axis image;clim(max(abs(clim)).*[-1,1]);colormap(ap.colormap('BWR'));

    % Get center-of-mass screen response for each widefield pixel
    [yy,xx] = ndgrid(1:size(stim_im_smoothed,1),1:size(stim_im_smoothed,2));
    m_xr = reshape(sum(sum(bsxfun(@times,stim_im_smoothed.^2,xx),1),2)./sum(sum(stim_im_smoothed.^2,1),2),size(Ud,1),size(Ud,2));
    m_yr = reshape(sum(sum(bsxfun(@times,stim_im_smoothed.^2,yy),1),2)./sum(sum(stim_im_smoothed.^2,1),2),size(Ud,1),size(Ud,2));

    % Calculate and plot sign map (dot product between horz & vert gradient)

    % 1) get gradient direction
    [~,Vdir] = imgradient(imgaussfilt(m_yr,1));
    [~,Hdir] = imgradient(imgaussfilt(m_xr,1));

    % 3) get sin(difference in direction) if retinotopic, H/V should be
    % orthogonal, so the closer the orthogonal the better (and get sign)
    angle_diff = sind(Vdir-Hdir);
    angle_diff(isnan(angle_diff)) = 0;

    vfs_boot(:,:,curr_boot) = angle_diff;
end

vfs = imgaussfilt(nanmean(vfs_boot,3),2);

figure;
imagesc(vfs)
axis image off;
colormap(ap.colormap('BWR'));
title(sprintf('%s, %s',animal,rec_day));





