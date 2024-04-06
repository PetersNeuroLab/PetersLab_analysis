function [V_neuro_hemocorr,hemocorr_t] = hemo_correct(U_neuro,V_neuro,t_neuro,U_hemo,V_hemo,t_hemo)
% [V_neuro_hemocorr,hemocorr_t] = hemo_correct(U_neuro,V_neuro,t_neuro,U_hemo,V_hemo,t_hemo)
%
% Remove hemodynamic signals from widefield
%
% Input: U/V - widefield SVD components (neuro ~ blue, hemo ~ violet)
% Output: V neuro with hemo component subtracted, timestamps (hemo)
%
% Gets scaling factor for hemo signal onto neuro signal, converts hemo V's
% into neuro U-space, baseline-subtracts and scales hemo signal, subtracts
% neuro-estimated hemo signal from neuro signal.
%
% Function based off cortexlab/widefield/hemo_correct_local (Kenneth)

%% Set parameters

% Spatial downsample factor
% (pixel traces reconstructed at this scale, 5 seems fine)
px_downsample = 5;

% Frequency for filtering heartbeat
heartbeat_freq = [8,12];

%% Overlap neuro/hemo signals

% Change hemo V from hemo to neuro U basis
V_hemo_Un = ...
    reshape(U_neuro,[],size(U_neuro,3))' * ...
    reshape(U_hemo,[],size(U_hemo,3)) * ...
    V_hemo;

% Interpolate neuro to hemo timepoints (captured alternating)
% (shifting neuro to hemo works much better than opposite)
V_neuro_th = interp1(t_neuro,V_neuro',t_hemo,'linear','extrap')';

% Set the timestamps
hemocorr_t = t_hemo;

%% Get scale factor to match hemo onto neuro
% (using the heartbeat frequency)

% Set to use (middle percentile: avoid edge artifacts)
use_frame_range = round(prctile(1:size(V_neuro,2),[12.5,87.5]));
use_frames = use_frame_range(1):use_frame_range(2);

% Filter V's at heartbeat frequency
wf_framerate = 1/mean(diff(t_neuro));
[b,a] = butter(2,heartbeat_freq/(wf_framerate/2));

V_neuro_th_heartbeat = filter(b,a,V_neuro_th')';
V_hemo_Un_heartbeat = filter(b,a,V_hemo_Un')';

% Downsample U
U_neuro_downsamp = imresize(U_neuro,1/px_downsample,'nearest');

% Get pixel traces (t x px) from downsampled U
px_neuro_heartbeat = reshape(plab.wf.svd2px(U_neuro_downsamp, ...
    V_neuro_th_heartbeat(:,use_frames)),[],length(use_frames))';
px_hemo_heartbeat = reshape(plab.wf.svd2px(U_neuro_downsamp, ...
    V_hemo_Un_heartbeat(:,use_frames)),[],length(use_frames))';

% Get scaling of violet to blue from heartbeat
% scaling = cov(neuro-mean,hemo-mean)/var(hemo-mean)
hemo_scale_px_downsamp = sum( ...
    normalize(px_neuro_heartbeat,'center','mean').* ...
    normalize(px_hemo_heartbeat,'center','mean'))./ ...
    sum(normalize(px_hemo_heartbeat,'center','mean').^2);

% Get transform matrix to convert scaling from pixel-space to V-space
hemo_scale_V_tform = ...
    pinv(reshape(U_neuro_downsamp,[],size(U_neuro_downsamp,3)))* ...
    diag(hemo_scale_px_downsamp)* ...
    reshape(U_neuro_downsamp,[],size(U_neuro_downsamp,3));


%% Hemo-correct neuro signal

% % Using scaled baseline-corrected hemo signal
% % 1) get hemo baseline (moving mean)
% baseline_seconds = 60; % number of seconds for moving-mean baseline
% movmean_n = neuro_framerate*baseline_seconds;
%
% neuro_movmean = movmean(V_neuro,movmean_n,2);
% hemo_movmean = movmean(V_hemo_tn_Un,movmean_n,2);
%
% % 2) baseline-subtract and scale neuro-basis set hemo signal
% neuro_hemo_estimation = transpose((V_hemo_tn_Un - hemo_movmean)'*hemo_scale_V_tform');
%
% % Hemo-correct neuro: subtract hemo estimation from neuro signal
% V_neuro_hemocorr = (V_neuro-neuro_movmean) - neuro_hemo_estimation;

% % Using scaled highpassed hemo signal
% highpassCutoff = 0.01; % Hz
% [b100s, a100s] = butter(2, highpassCutoff/(neuro_framerate/2), 'high');
% fV_hemo_tn_Un = filter(b100s,a100s,V_hemo_tn_Un,[],2);
% neuro_hemo_estimation = (fV_hemo_tn_Un'*hemo_scale_V_tform')';
% V_neuro_hemocorr = V_neuro - neuro_hemo_estimation;

% Using scaled detrended hemo signal
neuro_hemo_estimation = (detrend(V_hemo_Un')*hemo_scale_V_tform')';
V_neuro_hemocorr = V_neuro_th - neuro_hemo_estimation;

% % Using scaled mean-subtracted hemo signal
% neuro_hemo_estimation = ((V_hemo_tn_Un-mean(V_hemo_tn_Un,2))'*hemo_scale_V_tform')';
% V_neuro_hemocorr = V_neuro - neuro_hemo_estimation;

%% Check results

check_results = false;

if check_results

    % Image the V hemo scale
    figure;
    imagesc(reshape(hemo_scale_px_downsamp, ...
        size(U_neuro_downsamp,1),size(U_neuro_downsamp,2)));
    clim(max(abs(clim)).*[-1,1]);
    colormap(AP_colormap('BWR'));
    colorbar;
    axis image;
    title('Hemo to neuro scale factor');

    % Plot spectrum of ROI trace (look for elimination of heartbeat freqs)
    [neuro_trace,roi] = AP_svd_roi(U_neuro,V_neuro(:,use_frames),U_neuro(:,:,1));
    % hemo_trace = AP_svd_roi(U_hemo,V_hemo(:,use_frames),[],[],roi);
    hemo_trace = AP_svd_roi(U_neuro,V_hemo_Un(:,use_frames),[],[],roi);

    neuro_hemo_estimation_trace = AP_svd_roi(U_neuro,neuro_hemo_estimation(:,use_frames),[],[],roi);
    neuro_hemocorr_trace = AP_svd_roi(U_neuro,V_neuro_hemocorr(:,use_frames),[],[],roi);

    Fs = wf_framerate;
    L = length(neuro_trace);
    NFFT = 2^nextpow2(L);

    [neuro_trace_spectrum,F] = pwelch(double(neuro_trace)',[],[],NFFT,Fs);
    [hemo_trace_spectrum,F] = pwelch(double(hemo_trace)',[],[],NFFT,Fs);
    [neuro_hemo_estimation_spectrum,F] = pwelch(double(neuro_hemo_estimation_trace)',[],[],NFFT,Fs);
    [neuro_hemocorr_trace_spectrum,F] = pwelch(double(neuro_hemocorr_trace)',[],[],NFFT,Fs);

    figure; subplot(2,1,1); hold on;
    plot(neuro_trace,'b');
    plot(hemo_trace,'color',[0.8,0,0]);
    plot(neuro_hemo_estimation_trace,'color',[0.8,0.8,0]);
    plot(neuro_hemocorr_trace,'color',[0,0.8,0]);

    subplot(2,1,2); hold on;
    plot(F,log10(neuro_trace_spectrum),'b');
    plot(F,log10(hemo_trace_spectrum),'color',[0.8,0,0]);
    plot(F,log10(neuro_hemo_estimation_spectrum),'color',[0.8,0.8,0]);
    plot(F,log10(neuro_hemocorr_trace_spectrum),'color',[0,0.8,0]);

    xlabel('Frequency');
    ylabel('Log Power');
    xline(heartbeat_freq,'linewidth',2,'color','r');

    legend({'Neuro','Hemo','Neuro hemo estimation','Neuro hemocorr','Heart Freq'})

    % Hemo spectrogram
    spect_overlap = 50;
    window_length = 5; % in seconds
    window_length_samples = round(window_length/(1/wf_framerate));
    figure;
    spectrogram(hemo_trace,window_length_samples, ...
        round(spect_overlap/100*window_length_samples),[],wf_framerate,'yaxis')
    colormap(hot)
    set(gca,'colorscale','log')
    title('Hemo spectrogram')

    drawnow;

end













