function neuropixels_preprocess(animal,day,data_path)
% neuropixels_preprocess(animal,day)
%
% Currently assumes Neuropixels 3A or 1.0 recorded with Open Ephys

% Display start
fprintf('Preprocessing Neuropixels: %s %s\n',animal,day);

%% Set path for kilosort python environment

system_path = split(getenv("Path"),';');
anaconda_path = system_path{endsWith(system_path,'anaconda3')};
kilosort_environment_path = fullfile(anaconda_path,'envs','kilosort','pythonw.exe');
kilosort_python_environment = pyenv('Version',kilosort_environment_path,'ExecutionMode','OutOfProcess');

%% Get paths and filenames

% Get Open Ephys probe info
oe_settings_dir = dir(fullfile(data_path,'/**/','settings.xml'));
probe_info = plab.ephys.oe_probe_info(fullfile(oe_settings_dir.folder,oe_settings_dir.name));

% Get all data paths (continuous.dat)
data_dir = dir(fullfile(data_path,'/**/','continuous.dat'));
data_filenames = string(fullfile({data_dir.folder},{data_dir.name}))';

% Get paths following Open Ephys conventions: 
% \experimentN : incremented whenever ACQUISITION is stopped (resets sample numbers/timestamps)
% |-> \recordingN : incremented when RECORDING is stopped (continuous sample numbers / timestamps)
%     |-> \continuous : data
%         |-> [Neuropix-PIX/OneBox]-NNN.Probe[A,B...] : One folder per probe, lettered
%                                                       NPX1.0: split into -AP and -LFP folders by band
%                                                       NPX2.0: broadband in one folder
oe_experiments = unique(regexprep(data_filenames, '.*experiment(\d*).*', '$1'));
oe_recordings = unique(regexprep(data_filenames, '.*recording(\d*).*', '$1'));
oe_probes = unique(regexprep(data_filenames, '.*Probe([A-Z]).*', '$1'));

% Set local save path(s)
local_kilosort_path = plab.locations.filename('local',animal,day,[],'ephys','kilosort4');

if isscalar(oe_probes)
    % (single probe: no subfolders)
    save_paths = string(local_kilosort_path);
else
    % (multiple probes: subfolders probe_N)
    save_paths = arrayfun(@(x) string(fullfile(local_kilosort_path, ...
        sprintf('probe_%d',x))),(1:length(oe_probes))');
end

% Set server paths
server_ephys_path = plab.locations.filename('server',animal,day,[],'ephys');
if ~exist(server_ephys_path,'dir')
    mkdir(server_ephys_path);
end


%% Run kilosort on all probes

for curr_probe = 1:length(oe_probes)

    %% Set folders for processing and saving

    % Find all AP/broadband recordings on single probe
    curr_ap_data_path_idx = ...
        contains(data_filenames,['Probe',oe_probes{curr_probe}]) & ... % From current probe
        ~contains(data_filenames,{'LFP','ADC'});                       % AP/broadband (not LFP or ADC)
    ap_data_filename = sort(data_filenames(curr_ap_data_path_idx));  % Ensure temporal order (expN>recN)

    % Set/create save path
    curr_save_path = save_paths(curr_probe);
    if ~exist(curr_save_path,'dir')
        mkdir(curr_save_path)
    end

    %% Common average reference

    % Run common average referencing (CAR)
    apband_car_local_filename = fullfile(curr_save_path,sprintf('%s_%s_apband_car.dat',animal,day));
    ap.ephys_car(ap_data_filename,apband_car_local_filename,probe_info)

    %% Kilosort

    % Run Kilsort 4
    % (include probe geometry from Open Ephys)
    disp('Running Kilosort 4...');
    pyrunfile('AP_run_kilosort4.py', ...
        data_filename = apband_car_local_filename, ...
        kilosort_output_path = curr_save_path, ...
        chanMap = probe_info.chanMap, ...
        xc = probe_info.xc, ...
        yc = probe_info.yc, ...
        kcoords = probe_info.kcoords, ...
        n_chan = int32(probe_info.n_chan));

    % Terminate Python process
    terminate(kilosort_python_environment);

    %% Convert spike times to Open Ephys timestamps

    % Get metadata filename (for sample rate: just use first file)
    ephys_meta_fn = fullfile(fileparts(fileparts(fileparts(ap_data_filename))),'structure.oebin');
    ephys_metadata = jsondecode(fileread(ephys_meta_fn(1)));

    % Convert kilosort "spike times" (samples) into timestamps
    % (if multiple files, create concatenated/consecutive sample numbers)
    ks_spike_times_fn = fullfile(curr_save_path,'spike_times.npy');
    oe_ap_sample_fn = fullfile(ap_data_filename,'sample_numbers.npy');
    
    plab.ephys.ks2oe_timestamps(ks_spike_times_fn,oe_ap_sample_fn, ...
        ephys_metadata(1).continuous(1).sample_rate);

    %% Run bombcell (using CAR data)

    % Run bombcell
    kilosort_version = 4;
    ap.run_bombcell( ...
        char(apband_car_local_filename), ...
        char(curr_save_path), ...
        char(ephys_meta_fn), ...
        kilosort_version);

    %% Delete CAR data
    delete(apband_car_local_filename)

end

%% Move kilosort results to server
disp('Moving sorted data to server...');
server_kilosort_path = strrep(local_kilosort_path, ...
    plab.locations.local_data_path, ...
    plab.locations.server_data_path);
[status,message] = movefile(local_kilosort_path,server_kilosort_path);
if ~status
    warning('Failed moving to server: %s',message);
else
    fprintf('Moved %s --> %s \n',local_kilosort_path,server_kilosort_path);
end

%% Move raw data to server

local_ephys_path = fullfile(data_path,'Record Node 101','*');

disp('Moving raw data to server...');
[status,message] = movefile(local_ephys_path,server_ephys_path);
if ~status
    warning('Failed moving to server: %s',message);
else
    fprintf('Moved %s --> %s \n',local_ephys_path,server_ephys_path);
end

%% Print end message
fprintf('\nDone preprocessing Neuropixels: %s %s\n',animal,day);


