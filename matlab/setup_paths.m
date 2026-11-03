%% setup_paths.m
% Adds every project folder to the MATLAB path. Run once per MATLAB session,
% from inside the matlab/ folder:  >> setup_paths
root = fileparts(mfilename('fullpath'));
addpath(root, fullfile(root,'model'), fullfile(root,'build'), ...
        fullfile(root,'analysis'), fullfile(root,'prototyping'));
fprintf('Paths added. Next: >> init_microgrid\n');
