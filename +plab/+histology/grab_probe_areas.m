function probe_areas = grab_probe_areas(probe_vector)
% probe_areas = grab_probe_areas(probe_vector)
%
% Grab CCF areas across histology probe trajectory
% (currently assumes last labeled point is actual recording depth)

% Load atlas
[av,~,st] = ap_histology.load_ccf;

% Get areas along each probe
n_shanks = size(probe_vector,3);

shank_areas = cell(n_shanks,1);
for curr_shank = 1:n_shanks

    shank_vector = probe_vector(:,:,curr_shank);

    shank_sample_coords_ccf = ...
        round(interp1([0,norm(diff(shank_vector,[],1))],shank_vector, ...
        0:0.5:norm(size(av)),'linear','extrap'));

    coord_inbounds = find(all(shank_sample_coords_ccf > 0 & ...
        shank_sample_coords_ccf <= size(av),2));

    shank_sample_idx_ccf = ...
        round(sub2ind(size(av), ...
        shank_sample_coords_ccf(coord_inbounds,1), ...
        shank_sample_coords_ccf(coord_inbounds,2), ...
        shank_sample_coords_ccf(coord_inbounds,3)));

    % Get boundaries of areas and area IDs
    shank_sample_areas = av(shank_sample_idx_ccf);

    shank_sample_areas_brainidx = find(shank_sample_areas ~= 1);
    shank_sample_area_boundaries = ...
        [1;find(diff(double(shank_sample_areas(shank_sample_areas_brainidx)))~=0)+1; ...
        length(shank_sample_areas_brainidx)];
    shank_area_idx = shank_sample_areas(shank_sample_areas_brainidx(shank_sample_area_boundaries(1:end-1)));

    % Get distance from tip for each sample coordinate
    % (signed distance: towards tip +, away from tip -)
    ccf2mm = 1/100; % conversion factor: CCF is in 10um voxels (untransformed)
    stored_sample_idx = coord_inbounds(shank_sample_areas_brainidx(shank_sample_area_boundaries));
    shank_tip_distance = ccf2mm*vecnorm((shank_vector(2,:) - ...
        shank_sample_coords_ccf(stored_sample_idx,:))')';
    shank_direction = sign(norm(diff(shank_vector,[],1)) - ...
        (vecnorm((shank_vector(1,:) - ...
        shank_sample_coords_ccf(stored_sample_idx,:))')'));

    shank_tip_distance_signed = shank_tip_distance.*shank_direction;

    % Store probe areas and boundaries (in distance from tip)
    curr_shank_areas = st(shank_area_idx,:);
    curr_shank_areas.tip_distance = ...
        [shank_tip_distance_signed(1:end-1), ...
        shank_tip_distance_signed(2:end)];
    curr_shank_areas.probe_shank(:) = curr_shank;
    shank_areas{curr_shank} = curr_shank_areas;

end

probe_areas = {vertcat(shank_areas{:})};
