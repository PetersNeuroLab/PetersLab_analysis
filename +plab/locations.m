% Definitions for shared locations across the lab

% TO DO:
% Add method to search for filename? like AP_cortexlab filename
% maybe also something like AP_find_experiments

classdef locations
    properties(Constant = true)

        %% Set common lab locations

        % NAS server location
        server_data_path = 'P:\Data';

        % Ports for tcp servers and clients
        bonsai_port = 50001
        timelite_port = 50002
        mousecam_port = 50003
        widefield_port = 50004

        % Local bonsai workflow folder
        local_workflow_path = 'C:\Users\peterslab\Documents\GitHub\PetersLab_rigging\bonsai_workflows';

        % Github paths
        github_rigging = 'C:\Users\peterslab\Documents\GitHub\PetersLab_rigging';

    end

    methods(Static)

        %% Methods to get local data path 
        function x = local_data_path
            
            if exist('D:\','dir')
                % Use D: if available
                local_data_drive = 'D:';
            else
                % Otherwise, use C:
                local_data_drive = 'C:';
            end

            % Set local data path
            x = fullfile(local_data_drive,'LocalData');
  
        end


        %% Methods to construct filenames
        % Filename structure:
        % storage\animal\<YYYY-MM-DD>\<Protocol_HHMM>\filepart1\...\filepartN
        % e.g. P:\AP001\2023-03-21\Protocol_1301\timelite.mat
        %      P:\AP001\2023-03-21\Protocol_1301\widefield\svdSpatialComponents_blue.npy

        function local_filename = make_local_filename(animal,rec_day,rec_time,varargin)
            % Generate local filename
            % local_filename = make_local_filename(animal,rec_day,rec_time,filepart1,...,filepartN)

            % Format components
            if nargin == 2 || isempty(rec_time)
                filename_components = [{plab.locations.local_data_path, ...
                    animal,rec_day},varargin];
            else
                filename_components = [{plab.locations.local_data_path, ...
                    animal,rec_day,sprintf('Recording_%s',rec_time)},varargin];
            end

            % Ensure uniform char type, format as path
            local_filename = cell2mat(join(convertContainedStringsToChars(filename_components),filesep));

        end
        function server_filename = make_server_filename(animal,rec_day,rec_time,varargin)
            % Generate server filename
            % server_filename = make_server_filename(animal,rec_day,rec_time,filepart1,...,filepartN)

            % Format components
            if nargin == 2 || isempty(rec_time)
                filename_components = [{plab.locations.server_data_path, ...
                    animal,rec_day},varargin];
            else
                filename_components = [{plab.locations.server_data_path, ...
                    animal,rec_day,sprintf('Recording_%s',rec_time)},varargin];
            end

            % Ensure uniform char type, format as path
            server_filename = cell2mat(join(convertContainedStringsToChars(filename_components),filesep));

        end


    end

end






