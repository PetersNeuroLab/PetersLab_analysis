function map_probe_ephys(animal)
% map_probe_ephys(animal)
%
% Choose mappings from histology annotations to ephys recordings

% Get histology processing filename
histology_filepattern = plab.locations.filename('server',animal,[],[],'histology','**','AP_histology_processing.mat');
histology_dir = dir(histology_filepattern);
if isempty(histology_dir)
    error('%s: no histology processing found',animal);
end
histology_filename = fullfile(histology_dir.folder,histology_dir.name);
load(histology_filename);

% Get recordings with ephys
animal_recordings = plab.find_recordings(animal);
animal_ephys_recordings = animal_recordings([animal_recordings.ephys]>0);

% Create day-matching box
% (labels from histology annotation)
histology_labels = {AP_histology_processing.annotation.label}';
if isempty(histology_labels)
    error('%s: no histology annotations found',animal)
end

% (display labels for recordings)
ephys_labels_daysplit = cellfun(@(rec_day,probe) ...
    compose('%s: Probe %d',rec_day,1:probe)', ...
    {animal_ephys_recordings.day}, ...
    num2cell([animal_ephys_recordings.ephys]),'uni',false);
ephys_labels = vertcat({'<No ephys>'},ephys_labels_daysplit{:});

% (paths for ephys recordings)
ephys_paths_dayspit = arrayfun(@(curr_rec) ...
    {dir(fullfile(...
    plab.locations.filename('server',animal, ...
    animal_ephys_recordings(curr_rec).day), ...
    'ephys','kilosort4','**','spike_times.npy')).folder}, ...
    1:length(animal_ephys_recordings),'uni',false);
ephys_paths = horzcat({''},ephys_paths_dayspit{:})';

% Create gui
gui_fig = uifigure('Name','Set histology-ephys mapping');
gui_grid = uigridlayout(gui_fig,[3,3], ...
    'RowHeight',{'0.5x','7x','1x'});

% Label animal
uilabel(gui_grid,'Text',animal,'FontSize',16);

% Add table with drop-downs
% (put histology/ephys paths in UserData)
probe_mapping_table_ud = ...
    struct('histology_filename',histology_filename,'ephys_paths',{ephys_paths});

probe_mapping_table = uitable(gui_grid, ...
    'Layout',matlab.ui.layout.GridLayoutOptions('Row',2, ...
    'Column',[1,length(gui_grid.ColumnWidth)]), ...
    'Data',[histology_labels, ...
    repmat({'<No ephys>'},size(histology_labels)), ...
    repmat({'<No shank>'},size(histology_labels))], ...
    'ColumnName',{'Histology label','Ephys recording','Shank'}, ...
    'ColumnEditable',[false,true,true], ...
    'ColumnFormat',{[],ephys_labels',cellstr(string(1:4))}, ...
    'CellEditCallback',@probe_mapping_update, ...
    'BackgroundColor',[1,1,1], ...
    'UserData',probe_mapping_table_ud);

% Add buttons
uibutton(gui_grid,'text','Save','ButtonPushedFcn',{@probe_mapping_save,probe_mapping_table});
uibutton(gui_grid,'text','Reset','ButtonPushedFcn',{@probe_mapping_reset,probe_mapping_table});
uibutton(gui_grid,'text','3D plot','ButtonPushedFcn',{@probe_plot,animal});

% Apply previously saved mappings
load(probe_mapping_table.UserData.histology_filename);
if isfield(AP_histology_processing.annotation,'ephys_path')
        [~,ephys_idx] = ismember(...
            {AP_histology_processing.annotation.ephys_path}, ...
            probe_mapping_table.UserData.ephys_paths);
        mapped_recording_idx = find(ephys_idx ~= 0);

        % (set ephys)
        probe_mapping_table.Data(mapped_recording_idx,2) = ...
            probe_mapping_table.ColumnFormat{2}(ephys_idx(ephys_idx~=0));

        % (set shank)
        probe_mapping_table.Data(mapped_recording_idx,3) = ...
            {AP_histology_processing.annotation(mapped_recording_idx).ephys_shank};
        
        probe_mapping_update(probe_mapping_table,[]);
end

end

function probe_mapping_update(probe_mapping_table,eventdata)

if ~isempty(eventdata)
    % If ephys selected, default shank to 1
    if eventdata.Indices(2) == 2
        probe_mapping_table.Data{eventdata.Indices(1),3} = 1;
    end

    % If shank selected without ephys, reset to no shank
    if eventdata.Indices(2) == 3 && ...
            strcmp(probe_mapping_table.Data(eventdata.Indices(1),2),'<No ephys>')
        probe_mapping_table.Data(eventdata.Indices(1),eventdata.Indices(2)) = {'<No shank>'};
    end
end

% Find repeated selections (to flag as invalid)
unchosen_idx = intersect(1:size(probe_mapping_table.Data(:,2),1), ...
    find(strcmp(probe_mapping_table.Data(:,2),'<No ephys>')));

selection_address = arrayfun(@(x) strjoin(string( ...
    probe_mapping_table.Data(x,2:3))), ...
    1:height(probe_mapping_table.Data))';
same_selection_idx = find(sum(selection_address == selection_address',2) > 1);

invalid_idx = setdiff(same_selection_idx,unchosen_idx);

valid_idx = setdiff(1:size(probe_mapping_table.Data,1), ...
    vertcat(unchosen_idx,invalid_idx));

% Find saved mappings (histology file with matching data)
load(probe_mapping_table.UserData.histology_filename);

if isfield(AP_histology_processing.annotation,'ephys_path')

    [~,ephys_idx] = ismember(probe_mapping_table.Data(:,2), ...
        probe_mapping_table.ColumnFormat{2});

    recording_paths = cell(size(probe_mapping_table.Data,1),1);
    recording_paths(ephys_idx ~= 0) = ...
        probe_mapping_table.UserData.ephys_paths(ephys_idx(ephys_idx ~= 0));

    saved_recordings = strcmp(recording_paths,{AP_histology_processing.annotation.ephys_path}') & ...
        string(probe_mapping_table.Data(:,3)) == string({AP_histology_processing.annotation.ephys_shank})';
else 
    saved_recordings = false(size(probe_mapping_table.Data,1),1);
end
saved_idx = intersect(1:size(probe_mapping_table.Data(:,2),1), ...
    setdiff(find(saved_recordings),unchosen_idx));

% Color table cells based on unchosen(w)/invalid(r)/valid(y)/saved(g)
unchosen_style = uistyle('BackgroundColor',[1,1,1]);
invalid_style = uistyle('BackgroundColor',[1,0.8,0.8]);
valid_style = uistyle('BackgroundColor',[1,1,0.8]);
saved_style = uistyle('BackgroundColor',[0.8,1,0.8]);

removeStyle(probe_mapping_table)
addStyle(probe_mapping_table,unchosen_style,"row",unchosen_idx);
addStyle(probe_mapping_table,valid_style,"row",valid_idx);
addStyle(probe_mapping_table,saved_style,"row",saved_idx);
addStyle(probe_mapping_table,invalid_style,"row",invalid_idx);

end

function probe_mapping_save(hObject,~,probe_mapping_table)
% Save mappings

% If any invalid (doubled) mappings, warn and abort)
if ~isempty(probe_mapping_table.StyleConfigurations.TargetIndex{2})
    uialert(hObject.Parent.Parent,'Cannot save: invalid mappings present','Save error');
    return
end

user_confirm = uiconfirm(hObject.Parent.Parent, ...
    'Save probe mappings?','Confirm save');
if ~strcmpi(user_confirm,'ok')
    return
end

% Get ephys paths for each mapped histology label
[~,ephys_idx] = ismember(probe_mapping_table.Data(:,2), ...
    probe_mapping_table.ColumnFormat{2});

% Load histology file
load(probe_mapping_table.UserData.histology_filename);

% For all mapped annotations, save to histology file
mapped_recording_idx = find(ephys_idx ~= 0);
% (ephys path)
[AP_histology_processing.annotation(mapped_recording_idx).ephys_path] = ...
    probe_mapping_table.UserData.ephys_paths{ephys_idx(mapped_recording_idx)};
% (ephys shank)
[AP_histology_processing.annotation(mapped_recording_idx).ephys_shank] = ...
    probe_mapping_table.Data{mapped_recording_idx,3};

% Save histology file
save(probe_mapping_table.UserData.histology_filename,'AP_histology_processing');
uialert(hObject.Parent.Parent, ...
    sprintf('Saved histology -> ephys mappings:\n %s', ...
    probe_mapping_table.UserData.histology_filename),'Saved','Icon','success');

% Update gui colors
probe_mapping_update(probe_mapping_table,[]);

end

function probe_mapping_reset(hObject,~,probe_mapping_table)
% Reset all mappings
user_confirm = uiconfirm(hObject.Parent.Parent, ...
    'Reset probe mappings?','Confirm reset');
if ~strcmpi(user_confirm,'ok')
    return
end
probe_mapping_table.Data(:,2) = {'<No ephys>'};
probe_mapping_table.Data(:,3) = {'<No shank>'};
probe_mapping_update(probe_mapping_table,[])
end


function probe_plot(hObject,~,animal)
% Draw 3D plot of histology/NTE
progress_box = ...
    uiprogressdlg(hObject.Parent.Parent, ...
    'Message','Plotting histology/ephys probes...', ...
    'indeterminate','on');
ap.plot_probe_positions(animal,false);
close(progress_box);
end