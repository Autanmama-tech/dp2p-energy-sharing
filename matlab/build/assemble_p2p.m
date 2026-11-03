%% assemble_p2p.m
% Assembles p2p_microgrid.slx from the three already-built subsystems.
% Run this if SS1, SS2, SS3 are already built but the top model is missing.
%
% Prerequisites (must exist in current folder):
%   ss1_power_plant.slx
%   ss2_auction_ctrl.slx
%   ss3_dryer_loads.slx
%
% Run: >> assemble_p2p
% -----------------------------------------------------------------------

function assemble_p2p()

    fprintf('=== Assembling p2p_microgrid.slx ===\n\n');

    % Check all three subsystems exist
    needed = {'ss1_power_plant','ss2_auction_ctrl','ss3_dryer_loads'};
    for k = 1:numel(needed)
        if ~exist([needed{k} '.slx'],'file')
            error('[ERROR] %s.slx not found. Run build_ss%d first.', needed{k}, k);
        end
        fprintf('  [OK] Found %s.slx\n', needed{k});
    end
    fprintf('\n');

    top = 'p2p_microgrid';
    if bdIsLoaded(top); close_system(top, 0); end
    if exist([top '.slx'],'file'); delete([top '.slx']); end

    new_system(top);
    open_system(top);

    set_param(top, ...
        'SolverType', 'Variable-step', ...
        'Solver',     'ode45', ...
        'StopTime',   '28800', ...
        'MaxStep',    '1', ...
        'MinStep',    '0.001', ...
        'RelTol',     '1e-3');

    %% --- Three Model Reference blocks ---
    add_block('simulink/Ports & Subsystems/Model', [top '/SS1_PowerPlant'], ...
        'Position',  [100, 150, 320, 310], ...
        'ModelName', 'ss1_power_plant');

    add_block('simulink/Ports & Subsystems/Model', [top '/SS2_AuctionCtrl'], ...
        'Position',  [420, 80, 640, 380], ...
        'ModelName', 'ss2_auction_ctrl');

    add_block('simulink/Ports & Subsystems/Model', [top '/SS3_DryerLoads'], ...
        'Position',  [740, 150, 960, 390], ...
        'ModelName', 'ss3_dryer_loads');

    %% --- Button inputs ---
    add_block('simulink/Sources/Constant', [top '/Btn_N1'], ...
        'Position', [180, 420, 240, 445], 'Value','0');
    add_block('simulink/Sources/Constant', [top '/Btn_N2'], ...
        'Position', [180, 460, 240, 485], 'Value','0');

    %% --- To Workspace logging ---
    log_vars      = {'jfi','source_mode','bid_n1','bid_n2','winner'};
    ss2_log_ports = [4, 5, 6, 7, 8];
    for k = 1:numel(log_vars)
        add_block('simulink/Sinks/To Workspace', [top '/Log_' log_vars{k}], ...
            'Position',     [1050, 60+(k-1)*55, 1150, 85+(k-1)*55], ...
            'VariableName', log_vars{k}, ...
            'SaveFormat',   'Array');
    end

    %% --- Main Scope (4 channels) ---
    add_block('simulink/Sinks/Scope', [top '/Main_Scope'], ...
        'Position',      [1050, 340, 1100, 420], ...
        'NumInputPorts', '4');

    %% --- Inter-subsystem wiring ---
    fprintf('[Top]  Wiring connections...\n');

    % SS1 → SS2: bat_voltage
    add_line(top, 'SS1_PowerPlant/1', 'SS2_AuctionCtrl/1', 'autorouting','on');

    % SS3 → SS2: rh signals
    add_line(top, 'SS3_DryerLoads/1', 'SS2_AuctionCtrl/2', 'autorouting','on');
    add_line(top, 'SS3_DryerLoads/2', 'SS2_AuctionCtrl/3', 'autorouting','on');

    % Buttons → SS2
    add_line(top, 'Btn_N1/1', 'SS2_AuctionCtrl/4', 'autorouting','on');
    add_line(top, 'Btn_N2/1', 'SS2_AuctionCtrl/5', 'autorouting','on');

    % SS3 → SS2: cumulative energy
    add_line(top, 'SS3_DryerLoads/5', 'SS2_AuctionCtrl/6', 'autorouting','on');
    add_line(top, 'SS3_DryerLoads/6', 'SS2_AuctionCtrl/7', 'autorouting','on');

    % SS2 → SS1: relay_K1
    add_line(top, 'SS2_AuctionCtrl/1', 'SS1_PowerPlant/1', 'autorouting','on');

    % SS2 → SS3: relay commands
    add_line(top, 'SS2_AuctionCtrl/2', 'SS3_DryerLoads/1', 'autorouting','on');
    add_line(top, 'SS2_AuctionCtrl/3', 'SS3_DryerLoads/2', 'autorouting','on');

    % SS1 → SS3: bus_voltage
    add_line(top, 'SS1_PowerPlant/2', 'SS3_DryerLoads/3', 'autorouting','on');

    % SS2 → To Workspace logging
    for k = 1:numel(log_vars)
        add_line(top, sprintf('SS2_AuctionCtrl/%d', ss2_log_ports(k)), ...
            ['Log_' log_vars{k} '/1'], 'autorouting','on');
    end

    % SS2 + SS3 → Main Scope
    add_line(top, 'SS2_AuctionCtrl/4', 'Main_Scope/1', 'autorouting','on'); % JFI
    add_line(top, 'SS2_AuctionCtrl/5', 'Main_Scope/2', 'autorouting','on'); % source_mode
    add_line(top, 'SS3_DryerLoads/3',  'Main_Scope/3', 'autorouting','on'); % P_dryer1
    add_line(top, 'SS3_DryerLoads/4',  'Main_Scope/4', 'autorouting','on'); % P_dryer2

    save_system(top, [top '.slx']);
    fprintf('[OK]  Saved: %s.slx\n\n', top);

    fprintf('=== Ready to simulate ===\n');
    fprintf('  >> init_microgrid\n');
    fprintf('  >> sim(''p2p_microgrid'')\n\n');
    fprintf('  Main_Scope channels:\n');
    fprintf('    1: JFI          (target ≥ 0.85)\n');
    fprintf('    2: source_mode  (1=solar, 0=grid)\n');
    fprintf('    3: P_dryer1     (W, 0 or 144)\n');
    fprintf('    4: P_dryer2     (W, 0 or 144)\n\n');
end