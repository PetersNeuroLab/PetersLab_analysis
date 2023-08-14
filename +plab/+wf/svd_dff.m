function Vdf = svd_dff(U, V, mean_image)
% Vdf = svd_dff(U, V, meanImage)
% (from cortexlab)

% Get the mean image in U-space (meanV)
[nX, nY, nSVD] = size(U);
flatU = reshape(U, nX*nY,nSVD);
meanV = flatU'*mean_image(:);

% Define the baseline V as the reconstructed mean (meanV) + mean activity
V0 = meanV + mean(V,2);

% Define the new V as the old V with a zero-mean
Vdf= bsxfun(@minus,V,mean(V,2));

% Get (soft) dF/F in U-space by dividing U by average + soft
df_softnorm = median(mean_image(:))*1;
nonnormU = reshape(bsxfun(@rdivide,flatU,reshape(mean_image,[],1)+df_softnorm), [nX nY nSVD]);

% New df/f U's aren't orthonormal: change df/f V basis set into old U space
Vdf = plab.wf.change_U(nonnormU,Vdf,U);