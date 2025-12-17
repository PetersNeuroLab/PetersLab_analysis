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

% Get ephys recording paths
% OneBox multi-probe: in continuous/ProbeA,B
recording_dir = dir(fullfile(data_path,'/**/', ...
    'continuous',filesep,'*Probe*-AP'));
recording_paths = cellfun(@(path,fn) string(fullfile(path,fn)), ...
    {recording_dir.folder},{recording_dir.name});

% Set local save paths
local_kilosort_path = plab.locations.filename('local',animal,day,[],'ephys','kilosort4');

% (probe_n = multi-probe, site_n = serial sites)
if isscalar(recording_paths)
    % Single probe
    save_paths = local_kilosort_path;
else
    % Multiple probes
    save_paths = arrayfun(@(x) string(fullfile(local_kilosort_path, ...
        sprintf('probe_%d',x))),1:length(recording_paths));
end

% Set server paths
server_ephys_path = plab.locations.filename('server',animal,day,[],'ephys');
if ~exist(server_ephys_path,'dir')
    mkdir(server_ephys_path);
end


%% Run kilosort on all datasets

for curr_recording_idx = 1:length(recording_paths)

    curr_recording_path = recording_paths(curr_recording_idx);
    curr_save_path = save_paths(curr_recording_idx);

    if ~exist(curr_save_path,'dir')
        mkdir(curr_save_path)
    end

    % Get Open Ephys filename(s)
    ap_data_filename = fullfile(curr_recording_path,'continuous.dat');
    if ~exist(ap_data_filename,'file')
        error('No AP-band data: %s %s',animal,day)
    end
  
    %% Run kilosort

    % Run common average referencing (CAR)
    apband_car_local_filename = fullfile(curr_save_path,sprintf('%s_%s_apband_car.dat',animal,day));
    ap.ephys_car(ap_data_filename,apband_car_local_filename)

    % Run Kilsort 4
    disp('Running Kilosort 4...');
    pyrunfile('AP_run_kilosort4.py', ...
        data_filename = apband_car_local_filename, ...
        kilosort_output_path = curr_save_path);

    % Terminate Python process
    terminate(kilosort_python_environment);

    %% Convert spike times to Open Ephys timestamps

    % Get metadata filename (for sample rate: just use first file)
    ephys_meta_fn = fullfile(fileparts(fileparts(curr_recording_path)),'structure.oebin');
    ephys_metadata = jsondecode(fileread(ephys_meta_fn));

    % Convert kilosort "spike times" (samples) into timestamps
    % (if multiple files, create concatenated/consecutive sample numbers)
    ks_spike_times_fn = fullfile(curr_save_path,'spike_times.npy');
    oe_ap_sample_fn = fullfile(curr_recording_path,'sample_numbers.npy');
    
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


