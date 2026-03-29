function probe = oe_probe_info(oe_settings_fn)
% probe = oe_probe_info(settings_fn)
%
% Grab probe geometry from Open Ephys to pass to Kilosort
% Organize as Kilosort probe dictionary expects, as detailed here: 
% https://kilosort.readthedocs.io/en/latest/tutorials/make_probe.html

oe_settings = readstruct(oe_settings_fn,'filetype','xml');

% Get probe type and number of channels
probe_type = oe_settings.SIGNALCHAIN.PROCESSOR(1).STREAM(1).device_nameAttribute;
n_chan = oe_settings.SIGNALCHAIN.PROCESSOR(1).STREAM(1).channel_countAttribute;

% Get probe channels (not necessarily in order)
channels_str = oe_settings.SIGNALCHAIN.PROCESSOR(1).EDITOR.CUSTOM_PARAMETERS.NP_PROBE.CHANNELS;
channel_idx = cellfun(@(x) sscanf(x,'CH%dAttribute'),fieldnames(channels_str));
[~,channel_sort_idx] = sort(channel_idx);

% Get x/y/shank (shank stored as probe:shank)
electrode_x = struct2array(oe_settings.SIGNALCHAIN.PROCESSOR(1).EDITOR.CUSTOM_PARAMETERS.NP_PROBE.ELECTRODE_XPOS)';
electrode_y = struct2array(oe_settings.SIGNALCHAIN.PROCESSOR(1).EDITOR.CUSTOM_PARAMETERS.NP_PROBE.ELECTRODE_YPOS)';

% Get shank if multishank (stored as probe:shank)
if contains(probe_type,'multishank','IgnoreCase',true)
    electrode_shank = cellfun(@(x) sscanf(x,'%*d:%d'),struct2array(channels_str)');
else
    electrode_shank = ones(size(channel_idx));
end

% Structure data into Kilosort probe dictionary format
% (sort channels)
probe = struct( ...
    'chanMap',((1:n_chan)-1)', ... % channel indicies included in data
    'xc',electrode_x(channel_sort_idx),...
    'yc',electrode_y(channel_sort_idx),...
    'kcoords',electrode_shank(channel_sort_idx),... % shank or channel group
    'n_chan',n_chan, ...
    'probe_type',probe_type ... % (not for kilosort - just for convenience
    );

