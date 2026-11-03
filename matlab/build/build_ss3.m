%% build_ss3.m
% STEP 5: Build Simulink SS3 — Dryer Loads subsystem.
%
% SS3 models Layer 3 of the system:
%   - Two AHT21 humidity sensor models (pchip-interpolated time series)
%   - Two 1-ohm / 150W resistive dryer loads
%   - Two 20A relay switches (controlled by auction controller)
%   - Two PZEM-017 power meter models (V²/R measurement)
%   - Two energy integrators (Wh, feeds JFI in SS2)
%
% Inputs  (from SS2 auction controller):
%   relay_n1    — Node 1 dryer relay command (1=ON, 0=OFF)
%   relay_n2    — Node 2 dryer relay command (1=ON, 0=OFF)
%
% Inputs  (from SS1 power plant):
%   bus_voltage — DC bus bar voltage (V)
%
% Outputs (to SS2 auction controller):
%   rh_n1   — Node 1 relative humidity (0–1)
%   rh_n2   — Node 2 relative humidity (0–1)
%   E1_cum  — Node 1 cumulative energy (Wh)
%   E2_cum  — Node 2 cumulative energy (Wh)
%
% Outputs (to scope / logging):
%   P_dryer1 — Node 1 instantaneous power (W)
%   P_dryer2 — Node 2 instantaneous power (W)
%
% Prerequisites:
%   Run init_microgrid.m first (workspace variables required)
%
% Run: >> build_ss3
% -----------------------------------------------------------------------

function build_ss3()

    fprintf('=== Step 5: Building Simulink SS3 (Dryer Loads) ===\n\n');

    %% Ensure workspace is populated
    if ~evalin('base','exist(''DRY'',''var'')')
        fprintf('[INFO] Running init_microgrid first...\n');
        init_microgrid;
    end

    mdl = 'ss3_dryer_loads';

    %% Close and recreate cleanly
    if bdIsLoaded(mdl); close_system(mdl, 0); end
    if exist([mdl '.slx'], 'file'); delete([mdl '.slx']); end

    new_system(mdl);
    open_system(mdl);

    set_param(mdl, ...
        'SolverType', 'Variable-step', ...
        'Solver',     'ode45', ...
        'StopTime',   '28800', ...
        'MaxStep',    '1', ...
        'MinStep',    '0.001', ...
        'RelTol',     '1e-3');

    fprintf('[Simulink] Model created: %s\n', mdl);

    %% ---------------------------------------------------------------
    %  LAYOUT — x/y positions for clean block placement
    %% ---------------------------------------------------------------
    X_IN   = 30;   X_SENS = 180;  X_CALC = 360;
    X_SWIT = 510;  X_INTG = 660;  X_SCAL = 790;  X_OUT  = 930;

    Y_RH1  = 75;   Y_N1   = 140;
    Y_RH2  = 310;  Y_N2   = 375;

    BH = 30;  BW = 80;

    %% ---------------------------------------------------------------
    %  INPORTS
    %% ---------------------------------------------------------------
    blk_inport(mdl, 'relay_n1',    X_IN, Y_N1,  1);
    blk_inport(mdl, 'relay_n2',    X_IN, Y_N2,  2);
    blk_inport(mdl, 'bus_voltage', X_IN, 240,   3);

    %% ---------------------------------------------------------------
    %  AHT21 SENSOR MODELS
    %  From Workspace uses N1_rh / N2_rh — set by init_microgrid
    %  Format: [time_col, value_col] Nx2 matrix
    %% ---------------------------------------------------------------
    add_block('simulink/Sources/From Workspace', [mdl '/RH_N1'], ...
        'Position',      blkpos(X_SENS, Y_RH1, BW, BH), ...
        'VariableName',  'N1_rh', ...
        'Interpolate',   'on');

    add_block('simulink/Sources/From Workspace', [mdl '/RH_N2'], ...
        'Position',      blkpos(X_SENS, Y_RH2, BW, BH), ...
        'VariableName',  'N2_rh', ...
        'Interpolate',   'on');

    %% ---------------------------------------------------------------
    %  PZEM-017 POWER METER MODELS:  P = V² / R
    %  Product (squaring) + Gain (1/R)
    %% ---------------------------------------------------------------
    % Node 1
    add_block('simulink/Math Operations/Product', [mdl '/Vsq_N1'], ...
        'Position', blkpos(X_CALC, Y_N1, 45, BH), ...
        'Inputs',   '**');
    add_block('simulink/Math Operations/Gain', [mdl '/Rinv_N1'], ...
        'Position', blkpos(X_CALC+65, Y_N1, 55, BH), ...
        'Gain',     '1/DRY.resistance');

    % Node 2
    add_block('simulink/Math Operations/Product', [mdl '/Vsq_N2'], ...
        'Position', blkpos(X_CALC, Y_N2, 45, BH), ...
        'Inputs',   '**');
    add_block('simulink/Math Operations/Gain', [mdl '/Rinv_N2'], ...
        'Position', blkpos(X_CALC+65, Y_N2, 55, BH), ...
        'Gain',     '1/DRY.resistance');

    %% ---------------------------------------------------------------
    %  20A RELAY SWITCHES
    %  Switch: u1=power, u2=relay_cmd, u3=zero → output power or 0
    %% ---------------------------------------------------------------
    % Node 1
    add_block('simulink/Signal Routing/Switch', [mdl '/Relay_N1'], ...
        'Position',  blkpos(X_SWIT, Y_N1-5, 50, BH+10), ...
        'Criteria',  'u2 >= Threshold', ...
        'Threshold', '0.5');
    add_block('simulink/Sources/Constant', [mdl '/Zero_N1'], ...
        'Position', blkpos(X_SWIT, Y_N1+45, 40, 22), ...
        'Value',    '0');

    % Node 2
    add_block('simulink/Signal Routing/Switch', [mdl '/Relay_N2'], ...
        'Position',  blkpos(X_SWIT, Y_N2-5, 50, BH+10), ...
        'Criteria',  'u2 >= Threshold', ...
        'Threshold', '0.5');
    add_block('simulink/Sources/Constant', [mdl '/Zero_N2'], ...
        'Position', blkpos(X_SWIT, Y_N2+45, 40, 22), ...
        'Value',    '0');

    %% ---------------------------------------------------------------
    %  ENERGY INTEGRATORS  (W → Wh)
    %  Integrates switched power; Gain 1/3600 converts J to Wh
    %% ---------------------------------------------------------------
    % Node 1
    add_block('simulink/Continuous/Integrator', [mdl '/E1_int'], ...
        'Position',         blkpos(X_INTG, Y_N1, 50, BH), ...
        'InitialCondition', '0');
    add_block('simulink/Math Operations/Gain', [mdl '/E1_Wh'], ...
        'Position', blkpos(X_SCAL, Y_N1, 55, BH), ...
        'Gain',     '1/3600');

    % Node 2
    add_block('simulink/Continuous/Integrator', [mdl '/E2_int'], ...
        'Position',         blkpos(X_INTG, Y_N2, 50, BH), ...
        'InitialCondition', '0');
    add_block('simulink/Math Operations/Gain', [mdl '/E2_Wh'], ...
        'Position', blkpos(X_SCAL, Y_N2, 55, BH), ...
        'Gain',     '1/3600');

    %% ---------------------------------------------------------------
    %  OUTPORTS
    %% ---------------------------------------------------------------
    blk_outport(mdl, 'rh_n1',    X_OUT, Y_RH1,   1);
    blk_outport(mdl, 'rh_n2',    X_OUT, Y_RH2,   2);
    blk_outport(mdl, 'P_dryer1', X_OUT, Y_N1,    3);
    blk_outport(mdl, 'P_dryer2', X_OUT, Y_N2,    4);
    blk_outport(mdl, 'E1_cum',   X_OUT, Y_N1+55, 5);
    blk_outport(mdl, 'E2_cum',   X_OUT, Y_N2+55, 6);

    %% ---------------------------------------------------------------
    %  SCOPE for monitoring during standalone test
    %% ---------------------------------------------------------------
    add_block('simulink/Sinks/Scope', [mdl '/Monitor'], ...
        'Position',      blkpos(X_OUT+80, 190, 40, 40), ...
        'NumInputPorts', '4');

    %% ---------------------------------------------------------------
    %  WIRING
    %% ---------------------------------------------------------------
    fprintf('[Simulink] Wiring connections...\n');

    % bus_voltage → both squaring Product blocks (all four ports)
    add_line(mdl, 'bus_voltage/1', 'Vsq_N1/1', 'autorouting','on');
    add_line(mdl, 'bus_voltage/1', 'Vsq_N1/2', 'autorouting','on');
    add_line(mdl, 'bus_voltage/1', 'Vsq_N2/1', 'autorouting','on');
    add_line(mdl, 'bus_voltage/1', 'Vsq_N2/2', 'autorouting','on');

    % V² → 1/R → power
    add_line(mdl, 'Vsq_N1/1', 'Rinv_N1/1', 'autorouting','on');
    add_line(mdl, 'Vsq_N2/1', 'Rinv_N2/1', 'autorouting','on');

    % power → switch port 1
    add_line(mdl, 'Rinv_N1/1', 'Relay_N1/1', 'autorouting','on');
    add_line(mdl, 'Rinv_N2/1', 'Relay_N2/1', 'autorouting','on');

    % relay command → switch port 2
    add_line(mdl, 'relay_n1/1', 'Relay_N1/2', 'autorouting','on');
    add_line(mdl, 'relay_n2/1', 'Relay_N2/2', 'autorouting','on');

    % zero → switch port 3
    add_line(mdl, 'Zero_N1/1', 'Relay_N1/3', 'autorouting','on');
    add_line(mdl, 'Zero_N2/1', 'Relay_N2/3', 'autorouting','on');

    % switched power → integrators
    add_line(mdl, 'Relay_N1/1', 'E1_int/1', 'autorouting','on');
    add_line(mdl, 'Relay_N2/1', 'E2_int/1', 'autorouting','on');

    % integrators → Wh gains
    add_line(mdl, 'E1_int/1', 'E1_Wh/1', 'autorouting','on');
    add_line(mdl, 'E2_int/1', 'E2_Wh/1', 'autorouting','on');

    % RH sensors → outports
    add_line(mdl, 'RH_N1/1', 'rh_n1/1',  'autorouting','on');
    add_line(mdl, 'RH_N2/1', 'rh_n2/1',  'autorouting','on');

    % switched power → power outports
    add_line(mdl, 'Relay_N1/1', 'P_dryer1/1', 'autorouting','on');
    add_line(mdl, 'Relay_N2/1', 'P_dryer2/1', 'autorouting','on');

    % Wh → energy outports
    add_line(mdl, 'E1_Wh/1', 'E1_cum/1', 'autorouting','on');
    add_line(mdl, 'E2_Wh/1', 'E2_cum/1', 'autorouting','on');

    % RH + power → monitor scope
    add_line(mdl, 'RH_N1/1',    'Monitor/1', 'autorouting','on');
    add_line(mdl, 'RH_N2/1',    'Monitor/2', 'autorouting','on');
    add_line(mdl, 'Relay_N1/1', 'Monitor/3', 'autorouting','on');
    add_line(mdl, 'Relay_N2/1', 'Monitor/4', 'autorouting','on');

    %% ---------------------------------------------------------------
    %  SAVE
    %% ---------------------------------------------------------------
    save_system(mdl, [mdl '.slx']);
    fprintf('[OK]  Saved: %s.slx\n\n', mdl);

    %% ---------------------------------------------------------------
    %  VERIFICATION: what to expect
    %% ---------------------------------------------------------------
    fprintf('--- Expected outputs (relay ON, V_bus = 12V) ---\n');
    R   = evalin('base','DRY.resistance');
    V   = 12;
    P   = V^2 / R;
    Wh_1h = P * 3600 / 3600;
    fprintf('  P_dryer1 = P_dryer2 = %.0f W  (%.0f²/%.0f)\n', P, V, R);
    fprintf('  E1_cum after 1h = E2_cum = %.0f Wh\n', Wh_1h);
    fprintf('  RH_N1: ramps 0.40→0.90 per profile\n');
    fprintf('  RH_N2: ramps 0.40→0.90 per profile (offset)\n\n');

    fprintf('--- How to test SS3 standalone ---\n');
    fprintf('  1. Open ss3_dryer_loads.slx\n');
    fprintf('  2. Connect three Constant source blocks to the inports:\n');
    fprintf('       relay_n1 = 1, relay_n2 = 1, bus_voltage = 12\n');
    fprintf('  3. Set StopTime = 3600, run\n');
    fprintf('  4. Check Monitor scope: RH profiles + 144W power traces\n');
    fprintf('  5. Confirm E1_cum = E2_cum ≈ 144 Wh at t=3600s\n\n');
    fprintf('  Ready for Step 6: build SS1 (Power Plant).\n\n');

end

%% =====================================================================
%%  HELPER FUNCTIONS
%% =====================================================================
function p = blkpos(x, y, w, h)
    p = [x, y, x+w, y+h];
end

function blk_inport(mdl, name, x, y, n)
    add_block('built-in/Inport', [mdl '/' name], ...
        'Position', blkpos(x, y, 50, 20), 'Port', num2str(n));
end

function blk_outport(mdl, name, x, y, n)
    add_block('built-in/Outport', [mdl '/' name], ...
        'Position', blkpos(x, y, 50, 20), 'Port', num2str(n));
end