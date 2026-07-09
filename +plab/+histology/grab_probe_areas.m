function probe_areas = grab_probe_areas(probe_vector)
% probe_areas = grab_probe_areas(probe_vector)
%
% Grab CCF areas across histology probe trajectory
% Returns same format as NTE (structure tree of boundary areas, plus some)
% (assumes last labeled point is actual recording depth)

% Load atlas
[av,~,st] = ap_histology.load_ccf;

% Get areas along each probe
n_shanks = size(probe_vector,3);

shank_areas = cell(n_shanks,1);
for curr_shank = 1:n_shanks

    % Sample areas across full probe trajectory in brain
    shank_vector = probe_vector(:,:,curr_shank);

    shank_sample_coords_ccf_fullrange = ...
        round(interp1([0,norm(diff(shank_vector,[],1))],shank_vector, ...
        0:0.5:norm(size(av)),'linear','extrap'));

    % Remove points out-of-bounds of CCF
    coord_inbounds = find(all(shank_sample_coords_ccf_fullrange > 0 & ...
        shank_sample_coords_ccf_fullrange <= size(av),2));

    shank_sample_ccf_sub = shank_sample_coords_ccf_fullrange(coord_inbounds,:);

    % Get sample points for CCF in indicies
    shank_sample_ccf_idx = ...
        round(sub2ind(size(av), ...
        shank_sample_ccf_sub(:,1), ...
        shank_sample_ccf_sub(:,2), ...
        shank_sample_ccf_sub(:,3)));

    % Get boundaries of areas and area IDs
    shank_sample_areas = av(shank_sample_ccf_idx);

    shank_sample_areas_brainidx = find(shank_sample_areas ~= 1);
    shank_sample_area_boundaries = ...
        [1;find(diff(double(shank_sample_areas(shank_sample_areas_brainidx)))~=0)+1; ...
        length(shank_sample_areas_brainidx)];
    
    shank_area_idx = shank_sample_areas(shank_sample_areas_brainidx( ...
        shank_sample_area_boundaries(1:end-1)));

    % Get distance from tip for each sample coordinate
    % (signed distance: towards tip +, away from tip -)
    ccf2mm = 1/100; % conversion factor: CCF is in 10um voxels (untransformed)

    shank_tip_distance = ccf2mm*vecnorm((shank_vector(2,:) - ...
        shank_sample_ccf_sub(shank_sample_area_boundaries,:))')';
    shank_direction = sign(norm(diff(shank_vector,[],1)) - ...
        (vecnorm((shank_vector(1,:) - ...
        shank_sample_ccf_sub(shank_sample_area_boundaries,:))')'));

    shank_tip_distance_signed = shank_tip_distance.*shank_direction;

    % Store probe areas, boundaries (in distance from tip), CCF coords
    shank_areas{curr_shank} = st(shank_area_idx,:);

    shank_areas{curr_shank}.tip_distance = ...
        [shank_tip_distance_signed(1:end-1),shank_tip_distance_signed(2:end)];

    shank_sample_ccf_sub_boundary = ...
        mat2cell(shank_sample_ccf_sub(shank_sample_area_boundaries,:), ...
        ones(length(shank_sample_area_boundaries),1),3);
    shank_areas{curr_shank}.ccf = ...
        [shank_sample_ccf_sub_boundary(1:end-1), ...
        shank_sample_ccf_sub_boundary(2:end)];

    shank_areas{curr_shank}.probe_shank(:) = curr_shank;

end

probe_areas = {vertcat(shank_areas{:})};
