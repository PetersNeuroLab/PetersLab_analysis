function frame_pixels = svd2px(U,V)
% frame_pixels = svd2px(U,V)
% 
% Reconstruct pixels from SVD components (U: spatial, V: temporal)
%
% U is Y x X x nSVD
% V is nSVD x nFrames x ...[nConditions]

U_size = size(U);
V_size = size(V);

frame_pixels = reshape(reshape(U,[],size(U,3)) * ...
    reshape(V,size(V,1),[]),[U_size(1:2),V_size(2:end)]);