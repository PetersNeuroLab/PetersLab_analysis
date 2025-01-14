function U_master = load_master_U

% Load master U
master_U_fn = fullfile(plab.locations.server_path,'Lab', ...
    'widefield_alignment','U_master.mat');

load(master_U_fn);