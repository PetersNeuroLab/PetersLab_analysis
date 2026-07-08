function U_master = load_master_U(n_components)
% U_master = load_master_U(n_components)
% 
% Load master U basis set
% n_components - return only first n components (all by default)

% Load master U
master_U_fn = fullfile(plab.locations.server_path,'Lab', ...
    'widefield_alignment','U_master.mat');

load(master_U_fn);

if nargin==1
    U_master = U_master(:,:,1:n_components);
end