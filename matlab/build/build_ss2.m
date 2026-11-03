%% build_ss2.m
% STEP 7: Build Simulink SS2 — Auction Controller subsystem.
%         Then assemble the complete closed-loop p2p_microgrid model.
%
% SS2 models Layer 2 of the system:
%   - Zero-Order Hold: samples continuous signals at 10s auction period
%   - MATLAB Function block: full auction protocol (Steps 1-5 of spec)
%   - Outputs relay commands to SS1 (relay_K1) and SS3 (relay_n1, relay_n2)
%
% After SS2 is built, this script assembles p2p_microgrid.slx by
% connecting SS1, SS2, and SS3 with Model Reference blocks.
%
% Inputs to SS2 (from SS1 and SS3):
%   bat_voltage  — battery terminal voltage (V)        from SS1
%   rh_n1        — Node 1 relative humidity (0–1)      from SS3
%   rh_n2        — Node 2 relative humidity (0–1)      from SS3
%   btn_n1       — Node 1 manual override button       constant (0)
%   btn_n2       — Node 2 manual override button       constant (0)
%   E1_cum       — Node 1 cumulative solar energy (Wh) from SS3
%   E2_cum       — Node 2 cumulative solar energy (Wh) from SS3
%
% Outputs from SS2:
%   relay_K1     — DPDT source relay  (1=solar, 0=grid)  → SS1
%   relay_n1     — Node 1 dryer relay (1=ON, 0=OFF)      → SS3
%   relay_n2     — Node 2 dryer relay (1=ON, 0=OFF)      → SS3
%   jfi          — Jain Fairness Index (0–1)             → logging
%   source_mode  — 1=solar, 0=grid                       → logging
%   bid_n1       — Node 1 bid price                      → logging
%   bid_n2       — Node 2 bid price                      → logging
%   winner       — winning node (1, 2, or 0)             → logging
%
% Run: >> build_ss2
% -----------------------------------------------------------------------

function build_ss2()

    fprintf('=== Step 7: Building Simulink SS2 (Auction Controller) ===\n\n');

    if ~evalin('base','exist(''AUC'',''var'')')
        fprintf('[INFO] Running init_microgrid first...\n');
        init_microgrid;
    end

    %% ==============================================================
    %  PART A: Build ss2_auction_ctrl.slx
    %% ==============================================================
    mdl = 'ss2_auction_ctrl';

    if bdIsLoaded(mdl); close_system(mdl, 0); end
    if exist([mdl '.slx'],'file'); delete([mdl '.slx']); end

    new_system(mdl);
    open_system(mdl);

    set_param(mdl, ...
        'SolverType', 'Variable-step', ...
        'Solver',     'ode45', ...
        'StopTime',   '28800', ...
        'MaxStep',    '1');

    fprintf('[Simulink] Model created: %s\n', mdl);

    %% --- Layout ---
    X_IN  = 30;   X_ZOH = 160;  X_MFB = 360;  X_OUT = 620;
    Y_BASE = 60;  DY    = 45;

    inputs  = {'bat_voltage','rh_n1','rh_n2','btn_n1','btn_n2','E1_cum','E2_cum'};
    outputs = {'relay_K1','relay_n1','relay_n2','jfi','source_mode','bid_n1','bid_n2','winner'};

    %% --- Inports ---
    for k = 1:numel(inputs)
        blk_inport(mdl, inputs{k}, X_IN, Y_BASE+(k-1)*DY, k);
    end

    %% --- Zero-Order Holds (sample continuous signals at 10s) ---
    % Discretises inputs to the 10-second auction sample time
    for k = 1:numel(inputs)
        bname = ['ZOH_' inputs{k}];
        add_block('simulink/Discrete/Zero-Order Hold', [mdl '/' bname], ...
            'Position',   blkpos(X_ZOH, Y_BASE+(k-1)*DY, 70, 25), ...
            'SampleTime', 'AUC.cycle_s');
        add_line(mdl, [inputs{k} '/1'], [bname '/1'], 'autorouting','on');
    end

    %% --- MATLAB Function block: auction engine ---
    mfb = [mdl '/Auction_Engine'];
    add_block('simulink/User-Defined Functions/MATLAB Function', mfb, ...
        'Position', blkpos(X_MFB, Y_BASE, 180, numel(inputs)*DY));

    % Inject auction function code
    inject_auction_code(mfb);

    % Connect ZOH outputs → MATLAB Function inputs
    for k = 1:numel(inputs)
        add_line(mdl, ['ZOH_' inputs{k} '/1'], ...
            sprintf('Auction_Engine/%d', k), 'autorouting','on');
    end

    %% --- Outports ---
    for k = 1:numel(outputs)
        blk_outport(mdl, outputs{k}, X_OUT, Y_BASE+(k-1)*DY, k);
        add_line(mdl, sprintf('Auction_Engine/%d',k), ...
            [outputs{k} '/1'], 'autorouting','on');
    end

    %% --- JFI logging scope ---
    add_block('simulink/Sinks/Scope', [mdl '/JFI_Scope'], ...
        'Position',      blkpos(X_OUT+80, Y_BASE+3*DY, 40, 80), ...
        'NumInputPorts', '3');
    add_line(mdl, 'jfi/1',         'JFI_Scope/1', 'autorouting','on');
    add_line(mdl, 'source_mode/1', 'JFI_Scope/2', 'autorouting','on');
    add_line(mdl, 'winner/1',      'JFI_Scope/3', 'autorouting','on');

    save_system(mdl, [mdl '.slx']);
    fprintf('[OK]  Saved: %s.slx\n\n', mdl);

    %% ==============================================================
    %  PART B: Assemble complete p2p_microgrid.slx
    %% ==============================================================
    fprintf('--- Assembling complete closed-loop model ---\n');
    assemble_top_model();

end

%% =====================================================================
function inject_auction_code(mfb)
%% Injects the auction protocol into the MATLAB Function block

    code = [
'function [relay_K1, relay_n1, relay_n2, jfi, source_mode, bid_n1, bid_n2, winner] = ...' newline ...
'    auction_engine(bat_voltage, rh_n1, rh_n2, btn_n1, btn_n2, E1_cum, E2_cum)' newline ...
'%#codegen' newline ...
'% AutaNet P2P Auction Protocol — 10-second cycle' newline ...
'% Implements all 5 steps of the Layer 2 auction spec.' newline ...
'' newline ...
'V_GRID  = 11.8;   % V  grid-switch threshold' newline ...
'RH_CRIT = 0.80;   % fraction  critical humidity' newline ...
'BID_H   = 140;    % units/kWh  critical/override bid' newline ...
'BID_L   = 100;    % units/kWh  standard bid' newline ...
'' newline ...
'%% Step 1-2: Bid formulation' newline ...
'if btn_n1 >= 0.5' newline ...
'    bid_n1 = BID_H;' newline ...
'elseif rh_n1 >= RH_CRIT' newline ...
'    bid_n1 = BID_H;' newline ...
'else' newline ...
'    bid_n1 = BID_L;' newline ...
'end' newline ...
'' newline ...
'if btn_n2 >= 0.5' newline ...
'    bid_n2 = BID_H;' newline ...
'elseif rh_n2 >= RH_CRIT' newline ...
'    bid_n2 = BID_H;' newline ...
'else' newline ...
'    bid_n2 = BID_L;' newline ...
'end' newline ...
'' newline ...
'%% Step 3-4: Market clearing' newline ...
'if bat_voltage >= V_GRID' newline ...
'    source_mode = 1;' newline ...
'    if bid_n1 >= bid_n2' newline ...
'        winner = 1;' newline ...
'    else' newline ...
'        winner = 2;' newline ...
'    end' newline ...
'    relay_K1 = 1;' newline ...
'    relay_n1 = 1;' newline ...
'    relay_n2 = 1;' newline ...
'else' newline ...
'    source_mode = 0;' newline ...
'    winner      = 0;' newline ...
'    relay_K1    = 0;' newline ...
'    relay_n1    = 1;' newline ...
'    relay_n2    = 1;' newline ...
'end' newline ...
'' newline ...
'%% Step 5: Jain Fairness Index' newline ...
'if E1_cum == 0 && E2_cum == 0' newline ...
'    jfi = 1.0;' newline ...
'elseif (E1_cum^2 + E2_cum^2) < 1e-9' newline ...
'    jfi = 1.0;' newline ...
'else' newline ...
'    jfi = (E1_cum + E2_cum)^2 / (2.0*(E1_cum^2 + E2_cum^2));' newline ...
'end' newline ...
'jfi = min(max(jfi, 0.0), 1.0);' newline ...
'end' newline ...
    ];

    try
        rt = sfroot();
        chart = rt.find('-isa','Stateflow.EMChart', ...
            'Path', [bdroot(mfb) '/' get_param(mfb,'Name')]);
        if isempty(chart)
            chart = rt.find('-isa','Stateflow.EMChart');
        end
        if ~isempty(chart)
            chart(end).Script = code;
            fprintf('[SS2]  Auction code injected into MATLAB Function block.\n');
        else
            write_paste_file(code);
        end
    catch
        write_paste_file(code);
    end
end

function write_paste_file(code)
    fname = 'auction_engine_paste.m';
    fid = fopen(fname,'w');
    fprintf(fid, '%s', code);
    fclose(fid);
    fprintf('[SS2]  Auto-inject failed.\n');
    fprintf('       MANUAL STEP REQUIRED:\n');
    fprintf('       1. Double-click "Auction_Engine" block in ss2_auction_ctrl.slx\n');
    fprintf('       2. Select all (Ctrl+A) and delete existing code\n');
    fprintf('       3. Open "%s" and paste its contents\n', fname);
    fprintf('       4. Save and close the MATLAB Function editor\n\n');
end

%% =====================================================================
function assemble_top_model()
%% Builds p2p_microgrid.slx connecting SS1, SS2, SS3 via Model blocks

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

    %% --- Place three Model Reference blocks ---
    add_block('simulink/Ports & Subsystems/Model', [top '/SS1_PowerPlant'], ...
        'Position',  [100, 150, 320, 310], ...
        'ModelName', 'ss1_power_plant');

    add_block('simulink/Ports & Subsystems/Model', [top '/SS2_AuctionCtrl'], ...
        'Position',  [420, 80, 640, 380], ...
        'ModelName', 'ss2_auction_ctrl');

    add_block('simulink/Ports & Subsystems/Model', [top '/SS3_DryerLoads'], ...
        'Position',  [740, 150, 960, 390], ...
        'ModelName', 'ss3_dryer_loads');

    %% --- Button inputs (both OFF by default) ---
    add_block('simulink/Sources/Constant', [top '/Btn_N1'], ...
        'Position', [100, 420, 160, 445], 'Value','0');
    add_block('simulink/Sources/Constant', [top '/Btn_N2'], ...
        'Position', [100, 460, 160, 485], 'Value','0');

    %% --- To Workspace blocks for logging ---
    log_vars = {'jfi','source_mode','bid_n1','bid_n2','winner'};
    for k = 1:numel(log_vars)
        add_block('simulink/Sinks/To Workspace', ...
            [top '/Log_' log_vars{k}], ...
            'Position',      [1050, 80+(k-1)*50, 1150, 105+(k-1)*50], ...
            'VariableName',  log_vars{k}, ...
            'SaveFormat',    'Array');
    end

    %% --- Main scope ---
    add_block('simulink/Sinks/Scope', [top '/Main_Scope'], ...
        'Position',      [1050, 340, 1100, 420], ...
        'NumInputPorts', '4');

    %% --- INTER-SUBSYSTEM CONNECTIONS ---
    fprintf('[Top]  Wiring inter-subsystem connections...\n');

    % SS1 → SS2: bat_voltage (SS1 output 1 → SS2 input 1)
    add_line(top, 'SS1_PowerPlant/1', 'SS2_AuctionCtrl/1', 'autorouting','on');

    % SS3 → SS2: rh_n1 (SS3 out 1 → SS2 in 2)
    add_line(top, 'SS3_DryerLoads/1', 'SS2_AuctionCtrl/2', 'autorouting','on');

    % SS3 → SS2: rh_n2 (SS3 out 2 → SS2 in 3)
    add_line(top, 'SS3_DryerLoads/2', 'SS2_AuctionCtrl/3', 'autorouting','on');

    % Btn_N1 → SS2 input 4, Btn_N2 → SS2 input 5
    add_line(top, 'Btn_N1/1', 'SS2_AuctionCtrl/4', 'autorouting','on');
    add_line(top, 'Btn_N2/1', 'SS2_AuctionCtrl/5', 'autorouting','on');

    % SS3 → SS2: E1_cum (SS3 out 5 → SS2 in 6)
    add_line(top, 'SS3_DryerLoads/5', 'SS2_AuctionCtrl/6', 'autorouting','on');

    % SS3 → SS2: E2_cum (SS3 out 6 → SS2 in 7)
    add_line(top, 'SS3_DryerLoads/6', 'SS2_AuctionCtrl/7', 'autorouting','on');

    % SS2 → SS1: relay_K1 (SS2 out 1 → SS1 in 1)
    add_line(top, 'SS2_AuctionCtrl/1', 'SS1_PowerPlant/1', 'autorouting','on');

    % SS2 → SS3: relay_n1 (SS2 out 2 → SS3 in 1)
    add_line(top, 'SS2_AuctionCtrl/2', 'SS3_DryerLoads/1', 'autorouting','on');

    % SS2 → SS3: relay_n2 (SS2 out 3 → SS3 in 2)
    add_line(top, 'SS2_AuctionCtrl/3', 'SS3_DryerLoads/2', 'autorouting','on');

    % SS1 → SS3: bus_voltage (SS1 out 2 → SS3 in 3)
    add_line(top, 'SS1_PowerPlant/2', 'SS3_DryerLoads/3', 'autorouting','on');

    % SS2 logging outputs → To Workspace
    ss2_log_ports = [4, 5, 6, 7, 8];  % jfi, source_mode, bid_n1, bid_n2, winner
    for k = 1:numel(log_vars)
        add_line(top, sprintf('SS2_AuctionCtrl/%d', ss2_log_ports(k)), ...
            ['Log_' log_vars{k} '/1'], 'autorouting','on');
    end

    % Main scope: JFI, source_mode, P_dryer1, P_dryer2
    add_line(top, 'SS2_AuctionCtrl/4', 'Main_Scope/1', 'autorouting','on'); % JFI
    add_line(top, 'SS2_AuctionCtrl/5', 'Main_Scope/2', 'autorouting','on'); % source_mode
    add_line(top, 'SS3_DryerLoads/3',  'Main_Scope/3', 'autorouting','on'); % P_dryer1
    add_line(top, 'SS3_DryerLoads/4',  'Main_Scope/4', 'autorouting','on'); % P_dryer2

    save_system(top, [top '.slx']);
    fprintf('[OK]  Saved: %s.slx\n\n', top);

    %% --- Summary ---
    fprintf('=== Assembly complete ===\n\n');
    fprintf('  Files created:\n');
    fprintf('    ss2_auction_ctrl.slx  — auction controller\n');
    fprintf('    p2p_microgrid.slx     — complete closed-loop model\n\n');
    fprintf('  Signal map (top-level):\n');
    fprintf('    SS1 bat_voltage  ──►  SS2 (auction decision)\n');
    fprintf('    SS3 rh_n1/rh_n2  ──►  SS2 (bid formulation)\n');
    fprintf('    SS3 E1/E2_cum    ──►  SS2 (JFI computation)\n');
    fprintf('    SS2 relay_K1     ──►  SS1 (DPDT source switch)\n');
    fprintf('    SS2 relay_n1/n2  ──►  SS3 (dryer ON/OFF)\n');
    fprintf('    SS1 bus_voltage  ──►  SS3 (power calculation)\n\n');
    fprintf('  To run the full simulation:\n');
    fprintf('    >> init_microgrid\n');
    fprintf('    >> sim(''p2p_microgrid'')\n\n');
    fprintf('  Or open p2p_microgrid.slx and press Run (▶).\n\n');
    fprintf('  NOTE: If Auction_Engine block needs manual code entry,\n');
    fprintf('        open auction_engine_paste.m and follow the\n');
    fprintf('        instructions printed above.\n\n');
end

%% =====================================================================
function p = blkpos(x, y, w, h); p = [x, y, x+w, y+h]; end
function blk_inport(mdl, name, x, y, n)
    add_block('built-in/Inport', [mdl '/' name], ...
        'Position', blkpos(x,y,60,20), 'Port', num2str(n));
end
function blk_outport(mdl, name, x, y, n)
    add_block('built-in/Outport', [mdl '/' name], ...
        'Position', blkpos(x,y,60,20), 'Port', num2str(n));
end