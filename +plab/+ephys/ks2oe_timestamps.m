function ks2oe_timestamps(ks_spike_times_fn,oe_samples_fns,sample_rate)
% ks2oe_timestamps(ks_spike_times_fn,oe_samples_fns,oe_metadata_fn)
%
% 1) Convert kilosort spike times to Open Ephys times.
% 2) Convert and save Open Ephys TTL timestamps
%
% Kilosort spike "times" are sample indicies as integers. Open Ephys sample
% times are indexed by kilosort spike samples (this is only necessary if a
% sample is skipped, e.g. Open Ephys samples go [1,2,5,6,7], Kilosort
% sample [3] should be Open Ephys sample [5].
%
% Open Ephys assumes the main stream (AP band) is running at exactly the
% sample rate. It produces a timestamps.npy file, but this is adjusted
% based on the sync signal and not exactly reliable since it is recomputed
% on the fly. For this reason, the timestamps aren't used - instead, the
% samples are used, and the sample rate is assumed to be exact.
%
% Open Ephys can drop data, for example with high CPU or hard drive usage.
% This is flagged in the MessageCenter, which is interpreted with
% plab.ephys.find_dropped_ephys. This estimates how much time was dropped
% on late samples, and this time is added to the timestamps below.
%
% Open Ephys samples can start from arbitrary number: the digital sync
% signals correspond to the same numbers, so nothing needs correcting
%
% Inputs:
% ks_spike_times_fn - filename for Kilosort spike times (spike_times.npy)
% oe_samples_fns - filename for Open Ephys samples (sample_numbers.npy)
% (can be multiple filenames if multiple recordings: if so, assume OE
% sample numbers are continuous)
% sample_rate - sample rate (ideally from Open Ephys metadata structure.oebin)
%
% Outputs - saves new files (in same folder as spike_times.npy): 
% spike_times_openephys.npy 
% open_ephys_sync.mat

%% Set save filenames, confirm overwrite if exist

% Set save filenames
spike_times_save_fn = fullfile(fileparts(ks_spike_times_fn),'spike_times_openephys.npy');
open_ephys_ttl_save_fn = fullfile(fileparts(ks_spike_times_fn),'open_ephys_ttl.mat');

% Confirm overwrite if save files exist
if (exist(spike_times_save_fn,'file') && exist(open_ephys_ttl_save_fn,'file'))
    user_confirm = questdlg(sprintf('Overwrite Open Ephys spike/TTL timestamps? \n\n%s',fileparts(ks_spike_times_fn)));
    if ~user_confirm
        return
    end
end


%% Create Open Ephys timestamps

% Load Open Ephys samples
oe_samples_split = cellfun(@readNPY,oe_samples_fns,'uni',false);

% Check for clock resets on multiple recordings
oe_recording_clock_reset = ...
    find(cellfun(@(x) x(1),oe_samples_split(2:end)) - ...
    cellfun(@(x) x(end),oe_samples_split(1:end-1)) < 0) + 1;

if ~any(oe_recording_clock_reset)
    % Single recording or no clock resets: just concatenate
    oe_samples = vertcat(oe_samples_split{:});
else
    % Multiple recordings with clock reset (stop/start preview): make
    % pseudo-continuous by adding last sample of one recording to first sample
    % of next recording
    oe_samples_split_pseudocontinuous = oe_samples_split;
    oe_samples_split_pseudocontinuous(oe_recording_clock_reset) = ...
        cellfun(@(reset_samples,previous_sample) ...
        reset_samples + previous_sample, ...
        oe_samples_split(oe_recording_clock_reset), ...
        cellfun(@(x) x(end),oe_samples_split(oe_recording_clock_reset-1),'uni',false), ...
        'uni',false);
    oe_samples = vertcat(oe_samples_split_pseudocontinuous{:});
end

% Create expected time intervals for all samples (1/sample rate)
oe_time_intervals = ones(size(oe_samples))/sample_rate;

% Check for Open Ephys dropped data, compensate in timestamps if any
oe_bad_samples = plab.ephys.find_dropped_ephys(fileparts(oe_samples_fns{1}));

if ~isempty(oe_bad_samples)
    % Change time intervals for samples with time jumps
    [~,oe_bad_sample_idx] = ismember(cast(vertcat(oe_bad_samples.sample),class(oe_samples)),oe_samples);
    oe_time_intervals(oe_bad_sample_idx) = vertcat(oe_bad_samples.time_jump);
end

% Create vector of timestamps for each sample
oe_timestamps = cumsum(oe_time_intervals);


%% Convert kilosort spike time indices to Open Ephys timestamps

% Load Kilosort spike time indices
ks_spike_samples = readNPY(ks_spike_times_fn) + 1; % convert to 1-index

% Convert kilosort spike times indices to Open Ephys timestamps
% (interpolate: kilsoort can give spike indices out of range)
ks_spike_times_oe = interp1(1:length(oe_samples), ...
    oe_timestamps,double(ks_spike_samples),'linear','extrap');


%% Convert Open Ephys TTL events to timestamps

% Load Open Ephys TTL event samples
open_ephys_ttl_path = fullfile(strrep(fileparts(oe_samples_fns), ...
    'continuous','events'),'TTL');

open_ephys_ttl_sample_numbers = cellfun(@(data_path) ...
    readNPY(fullfile(data_path,'sample_numbers.npy')), ...
    open_ephys_ttl_path,'uni',false)';

% Check for clock resets as backwards timesteps across recordings
open_ephys_ttl_sample_backstep = ...
    find(cellfun(@(x) x(1),open_ephys_ttl_sample_numbers(2:end)) - ...
    cellfun(@(x) x(end),open_ephys_ttl_sample_numbers(1:end-1)) < 0) + 1;
    
if ~isempty(open_ephys_ttl_sample_backstep)
    
    error('OE clock reset: haven''t tested - check code works below');

    % If clock resets, make pseudocontinuous to match ks2oe
    % (load OE samples)
    oe_samples_dir = cellfun(@(data_path) ...
        dir(fullfile(data_path,'/**/','sample_numbers.npy')), ...
        open_ephys_path,'uni',false);
    oe_samples_fns = cellfun(@(data_dir) ...
        fullfile(data_dir.folder,data_dir.name),oe_samples_dir,'uni',false);
    oe_samples_split = cellfun(@readNPY,oe_samples_fns,'uni',false);
    oe_recordings_last_samples = cellfun(@(x) x(end),oe_samples_split);

    open_ephys_ttl_sample_numbers_pseudocontinuous = ...
        open_ephys_ttl_sample_numbers;
    open_ephys_ttl_sample_numbers_pseudocontinuous(open_ephys_ttl_sample_backstep) = ...
        cellfun(@(x,sample_add) x + sample_add, ...
        open_ephys_ttl_sample_numbers(open_ephys_ttl_sample_backstep), ...
        num2cell(oe_recordings_last_samples(open_ephys_ttl_sample_backstep-1)), ...
        'uni',false);

    open_ephys_ttl_timestamps = ...
        double(vertcat(open_ephys_ttl_sample_numbers_pseudocontinuous{:}))/oe_ap_samplerate;

end

% Convert TTL samples into timestamps 
open_ephys_ttl_timestamps = interp1(double(oe_samples), ...
    oe_timestamps,double(vertcat(open_ephys_ttl_sample_numbers{:})));

% Get state values for TTL events
open_ephys_ttl_states = cell2mat(cellfun(@(data_path) ...
    readNPY(fullfile(data_path,'states.npy')),open_ephys_ttl_path,'uni',false)');

% Package TTL timestamps and values into structure
open_ephys_ttl.state = open_ephys_ttl_states;
open_ephys_ttl.timestamps = open_ephys_ttl_timestamps;


%% Save Kilosort spike times and Open Ephys TTL times

% Save spike times
writeNPY(ks_spike_times_oe,spike_times_save_fn);

% Save TTL times
save(open_ephys_ttl_save_fn,'open_ephys_ttl');

% Print confirmation
fprintf('Saved spike/TTL times: %s\n',fileparts(ks_spike_times_fn));

