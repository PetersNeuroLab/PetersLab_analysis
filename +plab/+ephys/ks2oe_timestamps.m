function ks2oe_timestamps(ks_spike_times_fn,oe_samples_fns,sample_rate)
% ks2oe_timestamps(ks_spike_times_fn,oe_samples_fns,oe_metadata_fn)
%
% Convert kilosort spike times to open ephys times.
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
% Outputs:
% Saves spike_times_openephys.npy (in same folder as spike_times.npy)

% Load Kilosort spike times, Open Ephys samples
ks_spike_samples = readNPY(ks_spike_times_fn) + 1; % convert to 1-index

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

% Get timestamps by indexing Open Ephys samples as Kilosort samples and
% dividing by sample rate
% (note: kilosort can give negative spike times or spike times beyond the
% recording, so extrapolate)
ks_spike_samples_oe = ...
    interp1(1:length(oe_samples),double(oe_samples), ...
    double(ks_spike_samples),'linear','extrap');
ks_spike_times_oe = ks_spike_samples_oe/sample_rate;

% Save spike times
save_fn = fullfile(fileparts(ks_spike_times_fn),'spike_times_openephys.npy');
if ~exist(save_fn,'file')
    writeNPY(ks_spike_times_oe,save_fn);
else
    % Confirm overwrite if a file already exists
    user_confirm = questdlg(sprintf('spike_times_openephys.npy exists, overwrite? \n\n%s',save_fn));
    if strcmp(user_confirm,'Yes')
        writeNPY(ks_spike_times_oe,save_fn);
    end
end

% Print result
fprintf('Converted and saved Open Ephys spike times: %s\n',save_fn);






