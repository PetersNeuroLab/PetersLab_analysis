function mcms_token = login(mcms_username,mcms_password)
% mcms_token = plab.mcms.login(username,password)
%
% Create authentication token for MCMS
%
% username and password are optional: will be prompted if no inputs
% 
% (general information)
% API index: https://oxford.mcms-pro.com/api/swagger-ui/index.html
% MCMS production database URL: 'https://oxford.mcms-pro.com/api'
% MCMS test database URL: 'https://oxford-uat.mcms-pro.com/api'

% Get authentication token

if nargin < 2
    mcms_login = inputdlg({'MCMS username','MCMS password'});
    [mcms_username,mcms_password] = mcms_login{:};
end

mcms_url = 'https://oxford.mcms-pro.com/api';
authenticateEndpoint = sprintf('%s%s',mcms_url,'/authenticate');

headers = struct;
headers.Accept = '*/*';
headers.username = mcms_username;
headers.password = mcms_password;

header_cell = [fieldnames(headers),struct2cell(headers)];

options = weboptions( ...
    'MediaType','application/json', ...
    'ContentType','json', ...
    'RequestMethod','post', ...
    'HeaderFields',header_cell);

mcms_token = webread(authenticateEndpoint,options);

