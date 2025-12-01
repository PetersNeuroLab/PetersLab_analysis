function mcms_data = query(mcms_token,mcms_type,mcms_input)
% mcms_data = plab.mcms.query(mcms_token,mcms_type,mcms_input)
%
% Query MCMS API
%
% Available inputs (as mcms_type / mcms_input) 
% - weight / animal name
%
% 
% (general information)
% API index: https://oxford.mcms-pro.com/api/swagger-ui/index.html
% MCMS production database URL: 'https://oxford.mcms-pro.com/api'
% MCMS test database URL: 'https://oxford-uat.mcms-pro.com/api'

switch mcms_type
    case 'weight'
        % Get animal ID via name
        % (RFID field, prepend 'plab-' as lab standard on MCMS)
        % (search both as-is name and all lowercase)
        animal_rfid = sprintf('plab-%s',mcms_input);

        asis_endpoint = strjoin({'animals','rfid',animal_rfid},'/');
        lower_endpoint = strjoin({'animals','rfid',lower(animal_rfid)},'/');

        animal_info = vertcat(mcms_api(mcms_token,asis_endpoint), ...
            mcms_api(mcms_token,lower_endpoint));

        if isempty(animal_info)
            % If none found still: warning-out
            warning('Animal not found on MCMS: %s',animal_rfid);
            return
        end
        animal_id = num2str(animal_info.id);

        % Get weights (sort by date and put into structure)
        endpoint = strjoin({'animalweights','animal',animal_id},'/');
        weight_data = mcms_api(mcms_token,endpoint);
        weight_timestamps = datetime({weight_data.sampleDate}, ...
            'InputFormat','yyyy-MM-dd''T''HH:mm:ss.SSSZ','TimeZone','local');
        [~,sort_idx] = sort(weight_timestamps);
        mcms_data = struct('timestamp',weight_timestamps(sort_idx)', ...
            'weight',vertcat(weight_data(sort_idx).weightValue));
end

end



function mcms_data = mcms_api(mcms_token,endpoint)

mcms_url = 'https://oxford.mcms-pro.com/api';
endpoint_url = strjoin({mcms_url,endpoint},'/');

headers = struct;
headers.Accept = 'application/json';
headers.Authorization = ['Bearer ' mcms_token.token];
header_cell = [fieldnames(headers),struct2cell(headers)];
options = weboptions( ...
    'MediaType','application/json', ...
    'ContentType','json', ...
    'HeaderFields',header_cell);

mcms_data = webread(endpoint_url,options);

end
