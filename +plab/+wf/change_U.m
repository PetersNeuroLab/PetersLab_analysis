function new_V = change_U(U,V,newU)
% new_V = change_U(U,V,newU)
%
% (adapted from cortexlab ChangeU)
% Given SVD-compressed movie (U,V), changes the V's from the U basis set to
% the newU basis set
%
% newV = U' * newU * V

new_V = ...
    reshape(newU,[],size(newU,3))' * ...
    reshape(U,[],size(U,3)) * ...
    V;