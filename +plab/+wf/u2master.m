function [U_master,V_master] = u2master(U,V)
% [U_master,V_master] = u2master(U,V);
%
% Convert widefield U and V into the master U basis set
% (loads U_master, changes basis for V's)

% Load master U
plab.wf.load_master_U;

% Change V basis set from U to U_master
V_master = plab.wf.change_U(U,V,U_master);