function oe_bad_samples = find_dropped_ephys(oe_path)
% function oe_bad_samples = find_dropped_ephys(oe_path)
%
% Read Open Ephys MessageCenter to detect dropped data. Open Ephys detects
% dropped data by comparing time stamp to 100kHz clock on Neuropixels
% headstage. It reports the sample where a time jump was detected and the
% time lost (reported as number of 100kHz clock samples).
%
% INPUTS:
% oe_path: path to AP/broadband data folder (e.g. ...\continuous\OneBox-107.ProbeA-AP)
%
% OUTPUTS: 
% oe_bad_samples: structure, .time_jump = missing time, .sample = sample
% where jump was detected

% Read sync messages
% (unused - reports first sample number, which is arbitrary)
oe_sync_messages_fn = fullfile(fileparts(fileparts(oe_path)),"sync_messages.txt");
oe_sync_messages = regexp(readlines(oe_sync_messages_fn), ...
    '- (?<stream>.*) @ (?<sample_rate>.*) Hz: (?<first_sample>\d*)','names');
oe_stream_info = vertcat(oe_sync_messages{:});

% Read MessageCenter text
% (where timestamp jumps are reported)
oe_messages_fn = fullfile(fileparts(fileparts(oe_path)), ...
    "events","MessageCenter","text.npy");
oe_message_center_text = readlines(oe_messages_fn);
oe_bad_samples_string = regexp(oe_message_center_text(2), ...
    'NPX TIMESTAMP JUMP: (?<time_jump>\d+).*?sample number (?<sample>\d+)','names');

% Package time jump information
if ~isempty(oe_bad_samples_string)
    % (convert strings: 'timestamp jump' is 100kHz clock on Npx headstage)
    oe_bad_samples = struct('time_jump', ...
        num2cell(str2double(vertcat(oe_bad_samples_string.time_jump))/1e5), ...
        'sample', ...
        num2cell(str2double(vertcat(oe_bad_samples_string.sample))));

    warning('%s\n Open Ephys had %d drops totalling %.4fs', ...
        oe_path,length(oe_bad_samples),sum(vertcat(oe_bad_samples.time_jump)));
else
    % No dropped data: return empty variable
    oe_bad_samples = [];
end