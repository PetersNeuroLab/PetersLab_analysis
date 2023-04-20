function mousecam_header = read_mousecam_header(mousecam_header_fn, flipper_pin)
% mousecam_header = read_mousecam_header(mousecam_header_fn, flipper_pin)
%
% Get embedded info from face camera videos
%
% INPUTS
% mousecam_header_fn - filename with mousecam header (mousecam_header.bin)
% flipper_pin - GPIO pin that the flipper is plugged into
%
% OUTPUTS
% mousecam_header - structure with:
% .timestamps - timestamp of each frame
% .frame_num - number of each frame
% .flipper - flipper signal on each frame
%
% Embedded information: each component is 4 pixels (40 total) x n frames
% (from: https://www.flir.co.uk/support-center/iis/machine-vision/knowledge-base/embedding-frame-specific-data-into-the-first-n-pixels-of-an-image/)
% Timestamp
% Gain 
% Shutter
% Brightness
% Exposure
% White Balance
% Frame Counter
% Strobe pattern
% GPIO Pin State
% ROI position

%% Load and reshape data

fid = fopen(mousecam_header_fn,'r');
embedded_pixels = fread(fid,[40,Inf]);
fclose(fid);

n_frames = size(embedded_pixels,2);

% Initialize header structure
mousecam_header = struct( ...
    'timestamps',cell(1), ...
    'frame_num',cell(1), ...
    'flipper',cell(1));

%%  Timestamp

timestamp_pixels = embedded_pixels(1:4,:);
bin_val_pixels = dec2bin(timestamp_pixels, 8);
bin_val_pixels = reshape(bin_val_pixels', 32, n_frames)';

% timestamp value that we can use is only in the first 20 bits
timestamp_bin_val = bin_val_pixels(:, 1:20);
% extract miliseconds
miliseconds = (bin2dec(timestamp_bin_val(:,8:20)))'/8000;
% extract seconds
seconds = (bin2dec(timestamp_bin_val(:,1:7)))';
% get total in seconds
seconds = seconds + miliseconds;

% make sure the seconds trace is continuous - it resets at 127
reset_counter_idx = find(diff([0 seconds])<0);
for i=1:length(reset_counter_idx)
    seconds(reset_counter_idx(i):end) = seconds(reset_counter_idx(i):end) + 128;
end % can replace this with a recursive function??? 

% report timestamp in seconds
mousecam_header.timestamps = seconds';

%% Frame counter

frame_num_pixels = embedded_pixels(25:28,:);
bin_val_pixels = dec2bin(frame_num_pixels, 8);
bin_val_pixels = reshape(bin_val_pixels', 32, n_frames)';
mousecam_header.frame_num = bin2dec(bin_val_pixels);

%% GPIO pin states

pin_state_pixels = embedded_pixels(33:36,:);
bin_val_pixels = dec2bin(pin_state_pixels, 8);
bin_val_pixels = reshape(bin_val_pixels', 32, n_frames)';
mousecam_header.flipper = logical(str2num(bin_val_pixels(:, flipper_pin+1))); % pin numbering starts from 0 





