function adjust_probe_areas(animal,rec_day,probe)
% adjust_probe_areas(animal,rec_day,probe)
% 
% Manually adjust probe areas based on unit distribution, rate, depth
% correlation.
%
% Click a line to lock in place, click and drag to adjust position.
% Control+click unlocks a line.

arguments
    animal {mustBeNonempty}
    rec_day {mustBeNonempty}
    probe = 1
end

% Load spike data (use first recording)
recordings = plab.find_recordings(animal,rec_day);
rec_time = recordings.recording{1};
load_probe = probe;
load_parts.ephys = true;
load_parts.ephys_axons = true;
verbose = true;
ap.load_recording;

% Grab probe histology areas (fresh - discard previous adjustments)
if exist('probe_vector_histology','var')
    probe_areas = plab.histology.grab_probe_areas(probe_vector_histology);
else
    error('%s %s: no probe histology found',animal,rec_day);
end

% Initialize gui data
gui_data = struct;
gui_data.probe = probe;
gui_data.histology_filename = histology_filename;
gui_data.annotation_idx = histology_annotation_match;
gui_data.probe_areas = probe_areas;

% Create gui
gui_fig = uifigure('Name','Adjust regions on probe', ...
    'Units','normalized','Position',[0,0.1,0.2,0.8]);

shanks = unique(probe_areas.probe_shank);
gui_grid = uigridlayout(gui_fig,[2,1], ...
    'RowHeight',{'7x','1x'}, 'ColumnSpacing',0);

% Loop through shanks and draw gui
shank_grid = uigridlayout(gui_grid,[1,length(shanks)],'ColumnSpacing',0);
shank_data = struct;
for shank = reshape(shanks,1,[])

    % Calculate MUA depth correlelogram
    mua_depth_window = 10; % MUA depth window (microns)
    mua_depth_smooth = 5; % Moving window to smooth MUA depth bins
    mua_t_window = 0.2; % MUA temporal window (seconds)

    mua_depth_bins = min(template_tipdist):mua_depth_window:max(template_tipdist);
    mua_depth_bin_centers = movmean(mua_depth_bins,2,'Endpoints','discard')/1000;

    mua_t_bins = nanmin(spike_times_timelite):mua_t_window:nanmax(spike_times_timelite);
    use_spikes = template_shanks(spike_templates) == shank;
    mua_corr = corrcoef(histcounts2(spike_times_timelite(use_spikes),spike_tipdist(use_spikes), ...
        mua_t_bins,mua_depth_bins));
    mua_corr_smooth = fillmissing(smoothdata2(mua_corr,'movmean',mua_depth_smooth),'constant',0);

    % Create grid and axes
    unit_grid = uigridlayout(shank_grid,[1,3], ...
        'RowHeight',{'7x','1x'},'BackgroundColor','k', ...
        'ColumnSpacing',0);

    unit_axes = uiaxes(unit_grid, ...
        'Layout',matlab.ui.layout.GridLayoutOptions('Column',1),'Color','w','Interactions',[]);
    unit_plot_handles = ap.plot_unit_depthrate(unit_axes,false,shank);
    axis(unit_axes,'tight');

    mua_corr_axes = uiaxes(unit_grid, ...
        'Layout',matlab.ui.layout.GridLayoutOptions('Column',[2,length(unit_grid.ColumnWidth)]),'Color','k','Interactions',[]);
    imagesc(mua_corr_axes,mua_depth_bin_centers,mua_depth_bin_centers,mua_corr_smooth);
    clim(mua_corr_axes,[-1,1].*max(tril(abs(mua_corr),-1)*0.5,[],'all'));
    colormap(mua_corr_axes,ap.colormap('BKR'))
    set(mua_corr_axes,'YDir','normal','XDir','reverse');

    line_axes = uiaxes(unit_grid, ...
        'Layout',matlab.ui.layout.GridLayoutOptions('Row',1, ...
        'Column',[1,length(unit_grid.ColumnWidth)]),'Color','none','Interactions',[]);

    % Get areas on current shank
    curr_shank_areas = probe_areas.probe_shank == shank;
    probe_areas_shank = probe_areas(curr_shank_areas,:);

    % Plot UI area line borders (add brain end)
    draw_area_line = @(y,area_label,color) images.roi.Line(line_axes, ...
        'Position',[xlim(line_axes)',repelem(y,2,1)], ...
        'color',hex2rgb(color),'InteractionsAllowed','translate', ...
        'Label',area_label,'LabelVisible','hover', ...
        'SelectedColor','y');

    area_y = vertcat(probe_areas_shank.tip_distance(:,1), ...
        probe_areas_shank.tip_distance(end,2));
    area_labels = vertcat(string(probe_areas_shank.safe_name),"BRAIN END");
    area_colors = rgb2hex(vertcat(min(1,0.1+hex2rgb("#" + ...
        string(probe_areas_shank.color_hex_triplet))),[1,1,1]));

    area_ui_lines = arrayfun(@(y,label,color) draw_area_line(y,label,color),area_y,area_labels,area_colors);

    % Add listener for move function
    addlistener(area_ui_lines,'MovingROI',@(src,event) area_move(src,event,gui_fig));

    % Link axes and set limits
    axis([unit_axes,mua_corr_axes,line_axes],'off')
    linkaxes([unit_axes,mua_corr_axes,line_axes],'y')
    xlim(mua_corr_axes,prctile(template_tipdist(template_shanks==shank)/1000,[0,100]))
    % ylim([unit_axes,mua_corr_axes,line_axes],prctile(area_y,[0,100]))
    ylim([unit_axes,mua_corr_axes,line_axes], ...
        prctile(template_tipdist/1000,[0,100]) + ...
        [-0.5,0.5]);

    drawnow;

    % Keep initial positions
    area_positions_initial = {unit_plot_handles.area_rectangles.Position};
    area_ui_lines_initial = {area_ui_lines.Position};

    % Add guidata
    shank_data.unit_plot_handles(shank,1) = unit_plot_handles;
    shank_data.area_ui_lines{shank} = area_ui_lines;

    shank_data.initial.area_positions{shank} = area_positions_initial';
    shank_data.initial.area_ui_lines{shank} = area_ui_lines_initial';


end

% Add buttons
button_grid = uigridlayout(gui_grid,[1,3],'ColumnSpacing',0);
uibutton(button_grid,'text','Unlock all','ButtonPushedFcn', ...
    @(varargin) set(vertcat(shank_data.area_ui_lines{:}),'selected',false));
uibutton(button_grid,'text','Reset','ButtonPushedFcn',{@reset_areas,gui_fig});
uibutton(button_grid,'text','Save','ButtonPushedFcn',{@save_areas,gui_fig});

% Store guidata
% (handles)
gui_data.area_rectangles = vertcat(shank_data.unit_plot_handles.area_rectangles);
gui_data.area_ui_lines = vertcat(shank_data.area_ui_lines{:});
% (shank index)
gui_data.shank_idx = cell2mat(cellfun(@(shank,areas) ...
    repelem(shank,length(areas)+1,1), ...
    num2cell(shanks),shank_data.initial.area_positions','uni',false));
% (initial positions)
gui_data.initial.area_positions = vertcat(shank_data.initial.area_positions{:});
gui_data.initial.area_ui_lines = vertcat(shank_data.initial.area_ui_lines{:});

guidata(gui_fig,gui_data);

end

function area_move(src,eventdata,gui_fig)

% Get gui data
gui_data = guidata(gui_fig);

% Get line info
curr_line = find(eventdata.Source == gui_data.area_ui_lines);
curr_shank_idx = gui_data.shank_idx == gui_data.shank_idx(curr_line);
locked_lines = cat(1,gui_data.area_ui_lines.Selected);

% Set lines to lock in place
% (if >1 line locked, lock all non-shank lines)
if sum(locked_lines) > 1
    locked_lines(~curr_shank_idx) = true;
end
locked_lines_idx = find(locked_lines);

curr_line_ypos_new = eventdata.CurrentPosition(1,2);

ypos_prev = cellfun(@(x) x(1,2),{gui_data.area_ui_lines.Position})';
ypos_prev(curr_line) = eventdata.PreviousPosition(1,2);

ydiff = curr_line_ypos_new - ypos_prev(curr_line);

% Get lines to accordion between
accordion_start = intersect(locked_lines_idx(find(locked_lines_idx < curr_line,1,'last')),find(curr_shank_idx));
accordion_end = intersect(locked_lines_idx(find(locked_lines_idx > curr_line,1,'first')),find(curr_shank_idx));

% Get new positions
if ~isempty(accordion_start) & ~isempty(accordion_end)
    % Interpolate between 2 locked lines
    ypos_new = interp1(ypos_prev([accordion_start,curr_line,accordion_end]), ...
        [ypos_prev(accordion_start),curr_line_ypos_new,ypos_prev(accordion_end)], ...
        ypos_prev);

elseif isempty(accordion_start) | isempty(accordion_end)
    % Interpolate between 1 locked line and moved point, shift others
    accordion_idx = [accordion_start,accordion_end];

    if ~isempty(accordion_idx)
        ypos_new = interp1(ypos_prev([accordion_idx,curr_line]), ...
            [ypos_prev(accordion_idx),curr_line_ypos_new], ...
            ypos_prev);

        if accordion_idx > curr_line
            move_lines = find(curr_shank_idx,1,'first'):curr_line-1;
        elseif accordion_idx < curr_line
            move_lines = curr_line+1:find(curr_shank_idx,1,'last');
        end
        ypos_new(move_lines) = ypos_prev(move_lines) + ydiff;

    else
        ypos_new = ypos_prev + ydiff;
    end
end

nonmove_lines = setdiff(find(isnan(ypos_new) | locked_lines),curr_line);
ypos_new(nonmove_lines) = ypos_prev(nonmove_lines);

% If change re-orders lines, return all positions to previous
[~,line_sort_prev] = sort(ypos_prev(curr_shank_idx));
[~,line_sort_new] = sort(ypos_new(curr_shank_idx));
if ~isequal(line_sort_new,line_sort_prev)
    ypos_new = ypos_prev;
end

% Set new positions for area rectangles
ypos_new_lengths = diff(ypos_new);
brain_ends = strcmp({gui_data.area_ui_lines.Label},'BRAIN END');

area_rec_pos_new = cellfun(@(pos,y,y_length) ...
    [pos(1),y-abs(y_length),pos(3),abs(y_length)], ...
    {gui_data.area_rectangles.Position}', ...
    num2cell(ypos_new(~brain_ends)), ...
    num2cell(ypos_new_lengths(~brain_ends(1:end-1))),'uni',false);

[gui_data.area_rectangles.Position] = deal(area_rec_pos_new{:});

% Set new positions for area lines
area_line_pos_new = cellfun(@(pos,y) ...
    [pos(:,1),repelem(y,2,1)], ...
    {gui_data.area_ui_lines.Position}',num2cell(ypos_new),'uni',false);

[gui_data.area_ui_lines.Position] = deal(area_line_pos_new{:});

end


function reset_areas(src,eventdata,gui_fig)
% Reset all areas to inital positions

% Get gui data
gui_data = guidata(gui_fig);

% Reset rectangles
[gui_data.area_rectangles.Position] = deal(gui_data.initial.area_positions{:});
[gui_data.area_ui_lines.Position] = deal(gui_data.initial.area_ui_lines{:});

end


function save_areas(src,eventdata,gui_fig)

% Confirm save
user_confirm = uiconfirm(gui_fig, ...
    'Save probe areas?','Confirm save');
if ~strcmpi(user_confirm,'ok')
    return
end

% Get gui data
gui_data = guidata(gui_fig);

% Load histology file
load(gui_data.histology_filename)

% Write adjusted tip distances (use area rectangles)
probe_areas = gui_data.probe_areas;

area_tipdist = cell2mat(cellfun(@(pos) [pos(2)+pos(4),pos(2)], ...
    {gui_data.area_rectangles.Position}','uni',false));
probe_areas.tip_distance = area_tipdist;

% Store areas in histology processing file
for curr_shank = 1:length(gui_data.annotation_idx)
    AP_histology_processing.annotation(gui_data.annotation_idx(curr_shank)).probe_areas = ...
        probe_areas(probe_areas.probe_shank == curr_shank,:);
end

% Save histology file
save(gui_data.histology_filename,'AP_histology_processing');
fprintf('Saved: %s\n',gui_data.histology_filename);

end