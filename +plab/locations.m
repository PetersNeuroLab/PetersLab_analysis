% Definitions for shared locations across the lab

classdef locations
    properties(Constant = true)

        %% Set common lab locations

        % NAS server location
        server_path = '\\qnap-ap001.dpag.ox.ac.uk\APlab\';
        server_data_path = fullfile(plab.locations.server_path,'Data');

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
        % drive\animal\<YYYY-MM-DD>\<Protocol_HHMM>\filepart1\...\filepartN
        % e.g. P:\AP001\2023-03-21\Protocol_1301\timelite.mat
        %      P:\AP001\2023-03-21\Protocol_1301\widefield\svdSpatialComponents_blue.npy

        function constructed_filename = filename(drive,animal,rec_day,rec_time,varargin)
            % Construct server filename
            % constructed_filename = filename('server | local',animal,rec_day,rec_time,varargin)

            switch drive
                case 'server'
                    use_drive = plab.locations.server_data_path;
                case 'local'
                    use_drive = plab.locations.local_data_path;
                otherwise
                    error('Filename drive option invalid: "%s"',drive)
            end

            if ~exist('rec_day','var')
                rec_day = [];
            end

            % Format recording time path
            if exist('rec_time','var') && ~isempty(rec_time)
                rec_time_path = sprintf('Recording_%s',rec_time);
            else
                rec_time_path = [];
            end

            filename_components = [{use_drive,animal,rec_day,rec_time_path},varargin];
            filename_components_filled = ...
                filename_components(cellfun(@(x) ~isempty(x),filename_components));

            % Ensure uniform char type, format as path
            constructed_filename = cell2mat(join(convertContainedStringsToChars(filename_components_filled),filesep));

        end

    end

end






