function ks2oe_timestamps(ks_spike_times_fn,oe_samples_fn,sample_rate)
% ks2oe_timestamps(ks_spike_times_fn,oe_samples_fn,oe_metadata_fn)
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
% Inputs:
% ks_spike_times_fn - filename for Kilosort spike times (spike_times.npy)
% oe_samples_fn - filename for Open Ephys samples (sample_numbers.npy)
% sample_rate - sample rate (ideally from Open Ephys metadata structure.oebin)
%
% Outputs:
% Saves spike_times_openephys.npy (in same folder as spike_times.npy)

% Load in Kilosort spike times, Open Ephys samples, Open Ephys metadata
ks_spike_samples = readNPY(ks_spike_times_fn);
oe_samples = readNPY(oe_samples_fn);

% Get timestamps by indexing Open Ephys samples as Kilosort samples and
% dividing by sample rate
ks_spike_times_oe = double(oe_samples(ks_spike_samples))/sample_rate;

% NOTE: sometimes kilsort outputs indicies of spike times which are
% not in the range of recording?! Give a warning and calculate
% those times with the sample rate
spike_times_kilosort_validtime = ...
    ks_spike_times_oe >= 1 & ...
    ks_spike_times_oe <= oe_samples(end);

%%%%%%%%%%%%%%% crossing this bridge when I get to it
if ~all(spike_times_kilosort_validtime)
    error('Kilosort spike times out-of-range - finish writing this code')
end

% if all(spike_times_kilosort_validtime)
%     spike_times_openephys = openephys_ap_timestamps(spike_times_kilosort);
% else
%     ap_sample_time = median(diff(openephys_ap_timestamps));
%     warning('Kilosort %s: %d spike times out of time range of data, interpolating', ....
%         ks_spike_times_fn,sum(~spike_times_kilosort_validtime));
%     spike_times_openephys = nan(size(spike_times_kilosort));
%     spike_times_openephys(spike_times_kilosort_validtime) = ...
%         openephys_ap_timestamps(spike_times_kilosort(spike_times_kilosort_validtime));
% 
%     % (interpolate from first and last sample times given rate)
%     spike_times_openephys(~spike_times_kilosort_validtime) = ...
%         interp1([0,1,length(openephys_ap_timestamps),length(openephys_ap_timestamps)+1], ...
%         sort(reshape([openephys_ap_timestamps([1,end]),openephys_ap_timestamps([1,end])+([-1;1].*ap_sample_time)],1,[])), ...
%         double(spike_times_kilosort(~spike_times_kilosort_validtime)),'linear','extrap');
% end

% Save spike times
save_fn = fullfile(fileparts(ks_spike_times_fn),'spike_times_openephys.npy');
if exist(save_fn,'file')
    % Confirm overwrite if a file already exists
    user_confirm = questdlg(sprintf('spike_times_openephys.npy exists, overwrite? \n\n%s',save_fn));
    if strcmp(user_confirm,'Yes')
        writeNPY(ks_spike_times_oe,save_fn);
    end
end
 
% Print result
fprintf('Converted and saved Open Ephys spike times: %s\n',save_fn);






