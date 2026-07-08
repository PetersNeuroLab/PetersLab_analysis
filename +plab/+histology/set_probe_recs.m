function set_probe_recs

%%%%% TO DO
% - standalone, or secret PetersLab menu item in AP_histology?


animal = 'AP009';

% Get histology processing filename
histology_filepattern = plab.locations.filename('server',animal,[],[],'histology','**','AP_histology_processing.mat');
histology_dir = dir(histology_filepattern);
histology_filename = fullfile(histology_dir.folder,histology_dir.name);
load(histology_filename);

% Get recordings with ephys
animal_recordings = plab.find_recordings(animal);

%%% % Plot probes from NTE/histology
% ap.plot_probe_positions(animal,false)

% Create day-matching box
histology_labels = {AP_histology_processing.annotation.label}';

ephys_labels_daysplit = cellfun(@(rec_day,probe) ...
    compose('%s: Probe %d',rec_day,1:probe)', ...
    {animal_recordings.day},num2cell([animal_recordings.ephys]),'uni',false);
ephys_labels = vertcat(ephys_labels_daysplit{:});

gui_fig = uifigure('Name','Choose histology -> ephys mapping');
gui_grid = uigridlayout(gui_fig,[2,3], ...
    'RowHeight',{'7x','1x'});

% Add table with drop-downs
uitable(gui_grid, ...
    'Layout',matlab.ui.layout.GridLayoutOptions('Row',1, ...
    'Column',[1,length(gui_grid.ColumnWidth)]), ...
    'Data',[histology_labels, ...
    repmat({'No recording chosen'},size(histology_labels))], ...
    'ColumnName',{'Histology label','Ephys recording'}, ...
    'ColumnEditable',[false,true], ...
    'ColumnFormat',{[],ephys_labels'}, ...
    'CellEditCallback',@color_table, ...
    'BackgroundColor',[1,1,1]);

% Add buttons
uibutton(gui_grid,'text','Save','ButtonPushedFcn',@sum);
uibutton(gui_grid,'text','Reset','ButtonPushedFcn',@sum);
uibutton(gui_grid,'text','Cancel','ButtonPushedFcn',@sum);


end


function color_table(probe_table,eventdata)

unchosen_idx = find(strcmp(probe_table.Data(:,2),'No recording chosen'));

invalid_idx = setdiff(...
    find(sum(string(probe_table.Data(:,2)) == ...
    string(probe_table.Data(:,2)'),2) > 1), ...
    unchosen_idx);

valid_idx = setdiff(1:size(probe_table.Data,1), ...
    vertcat(unchosen_idx,invalid_idx));

unchosen_style = uistyle('BackgroundColor',[1,1,1]);
invalid_style = uistyle('BackgroundColor',[1,0.8,0.8]);
valid_style = uistyle('BackgroundColor',[0.8,1,0.8]);

addStyle(probe_table,unchosen_style,"row",unchosen_idx);
addStyle(probe_table,invalid_style,"row",invalid_idx);
addStyle(probe_table,valid_style,"row",valid_idx);

end
