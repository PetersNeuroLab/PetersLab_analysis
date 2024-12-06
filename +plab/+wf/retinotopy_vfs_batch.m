function retinotopy_vfs_batch(animal)
% retinotopy_vfs_batch(animal)
%
% Create vfs maps across all sparse noise recordings for an animal, average
% and save.

workflow = 'sparse_noise';
recordings = plab.find_recordings(animal,[],workflow);
recordings_wf = recordings(cellfun(@any,{recordings.widefield}));

vfs_all = cell(length(recordings_wf),1);
disp('Creating retinotopy...');
for curr_day = 1:length(recordings_wf)
    rec_day = recordings_wf(curr_day).day;
    rec_time = recordings_wf(curr_day).recording{end};

    load_parts.widefield = true;
    load_parts.widefield_align = false;
    verbose = false;
    try
        vfs = plab.wf.retinotopy_vfs(animal,rec_day,rec_time);
        vfs_all{curr_day} = vfs;
    catch me
        % If there's an error, remove day and skip to next
        warning('%s %s %s: error processing retinotopy, omitting', ...
            animal,rec_day,rec_time);
        continue
    end
end

% Save retinotopy from all days which have VFS
retinotopy_fn = fullfile(plab.locations.server_path, ...
    'Lab','widefield_alignment','retinotopy', ...
    sprintf('retinotopy_%s.mat',animal));

% (only keep data with filled VFS)
use_recordings = cellfun(@(x) ~isempty(x),vfs_all);

retinotopy = struct;
retinotopy.animal = animal;
retinotopy.day = {recordings(use_recordings).day};
retinotopy.vfs = vfs_all(use_recordings);

save(retinotopy_fn,'retinotopy');
fprintf('Saved %s\n',retinotopy_fn);





