function V_neuro_hemocorr = hemo_correct(U_neuro,V_neuro,t_neuro,U_hemo,V_hemo,t_hemo)
% V_neuro_hemocorr = hemo_correct(U_neuro,V_neuro,t_neuro,U_hemo,V_hemo,t_hemo)
%
% Remove hemodynamic signals from widefield
% 
% Input: U/V - widefield SVD components (neuro ~ blue, hemo ~ violet)
% Output: V neuro with hemo component subtracted
%
% Gets scaling factor for hemo signal onto neuro signal, converts hemo V's
% into neuro U-space, baseline-subtracts and scales hemo signal, subtracts
% neuro-estimated hemo signal from neuro signal.
% 
% Function based off one written by Kenneth Harris (hemo_correct_local)

%% Set parameters

px_downsample = 3;
heartbeat_freq = [5,15];

%% Get scale factor to match hemo onto neuro
% (using the heartbeat frequency)

% Interpolate V hemo timestamps into neuro timestamps
% (to estimate simultaneous from alternating measures)
% (extrapolate last point if unpaired)
V_hemo_tn = interp1(t_hemo,V_hemo',t_neuro,'linear','extrap')';

% Downsample U
U_neuro_downsamp = imresize(U_neuro,1/px_downsample,'bilinear');
U_hemo_downsamp = imresize(U_hemo,1/px_downsample,'bilinear');

% Get all pixel traces (t x px) from downsampled U
px_neuro = reshape(plab.wf.svd2px(U_neuro_downsamp,V_neuro),[],size(V_neuro,2))';
px_hemo = reshape(plab.wf.svd2px(U_hemo_downsamp,V_hemo_tn),[],size(V_hemo_tn,2))';

% Filter both colors at heartbeat frequency, subtract mean
neuro_framerate = 1/mean(diff(t_neuro));
[b,a] = butter(2,heartbeat_freq/(neuro_framerate/2));
px_neuro_heartbeat = filter(b,a,px_neuro);
px_hemo_heartbeat = filter(b,a,px_hemo);

% Get scaling of violet to blue from heartbeat (don't use trace edges)
skip_frames_scale = 500;
use_frames_scale = skip_frames_scale:size(px_neuro_heartbeat,1)-skip_frames_scale;
% scaling = cov(neuro-mean,hemo-mean)/var(hemo-mean)
hemo_scale_px_downsamp = sum(...
    detrend(px_neuro_heartbeat(use_frames_scale,:),'constant').*...
    detrend(px_hemo_heartbeat(use_frames_scale,:),'constant'))./ ...
    sum(detrend(px_hemo_heartbeat(use_frames_scale,:),'constant').^2);

% Get transform matrix to convert scaling from pixel-space to V-space
hemo_scale_V_tform = pinv(reshape(U_neuro_downsamp,[],size(U_neuro_downsamp,3)))* ...
    diag(hemo_scale_px_downsamp)* ...
    reshape(U_neuro_downsamp,[],size(U_neuro_downsamp,3));

%% Hemo-correct neuro signal

% Estimate hemo signal in neuro:
% 1) convert V hemo basis set (U_hemo) into the neuro basis set (U_neuro)
V_hemo_tn_Un = ...
    reshape(U_neuro,[],size(U_neuro,3))' * ...
    reshape(U_hemo,[],size(U_hemo,3)) * ...
    V_hemo_tn;

% 2) get hemo baseline (moving mean)
baseline_minutes = 2; % number of minutes for moving-mean baseline
movmed_n = neuro_framerate*60*baseline_minutes;
hemo_movmean = movmean(V_hemo_tn_Un,movmed_n,2);

% 3) baseline-subtract and scale neuro-basis set hemo signal
neuro_hemo_estimation = transpose((V_hemo_tn_Un - hemo_movmean)'*hemo_scale_V_tform');

% Hemo-correct neuro: subtract hemo estimation from neuro signal
V_neuro_hemocorr = V_neuro - neuro_hemo_estimation;


%% Check results

% Plot spectrum of ROI trace (look for elimination of heartbeat freqs)
% [neuro_trace,roi] = AP_svd_roi(U_neuro,V_neuro,U_neuro(:,:,1));
% neuro_hemocorr_trace = AP_svd_roi(U_neuro,V_neuro_hemocorr,[],[],roi);
% 
% Fs = neuro_framerate;
% L = length(neuro_trace);
% NFFT = 2^nextpow2(L);
% 
% [neuro_trace_spectrum,F] = pwelch(double(neuro_trace)',[],[],NFFT,Fs);
% [neuro_hemocorr_trace_spectrum,F] = pwelch(double(neuro_hemocorr_trace)',[],[],NFFT,Fs);
% 
% figure; subplot(1,2,1); hold on;
% plot(neuro_trace,'b');
% plot(neuro_hemocorr_trace,'color',[0.8,0,0]);
% 
% subplot(1,2,2); hold on;
% plot(F,log10(smooth(neuro_trace_spectrum,50)),'b');
% plot(F,log10(smooth(neuro_hemocorr_trace_spectrum,50)),'color',[0.8,0,0]);
% 
% xlabel('Frequency');
% ylabel('Log Power');
% xline(heartbeat_freq,'linewidth',2,'color','r');
% 
% legend({'Neuro','Neuro hemocorr','Heart Freq'})












