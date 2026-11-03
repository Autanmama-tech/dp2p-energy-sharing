%% build_ss1.m
% STEP 6: Build Simulink SS1 — Power Plant subsystem.
%
% SS1 models Layer 1 of the system:
%   - PV array (1410W, 3x470W panels): irradiance lookup → power
%   - MPPT controller: P&O algorithm as MATLAB Function block
%   - Battery: 12V 220Ah SLA — energy integrator + SOC→voltage lookup
%   - Grid SMPS: 12V 50A constant voltage source
%   - DPDT relay K1: Switch block (solar=NO / grid=NC)
%
% Inputs  (from SS2 auction controller):
%   relay_K1  — DPDT source relay command (1=solar, 0=grid)
%
% Outputs (to SS2 auction controller):
%   bat_voltage — battery terminal voltage (V), used for grid-switch decision
%
% Outputs (to SS3 dryer loads):
%   bus_voltage — DC distribution bus voltage (V)
%
% Outputs (to scope/logging):
%   pv_power    — instantaneous PV array power (W)
%   bat_soc     — battery state of charge (0–1)
%
% Prerequisites:
%   Run init_microgrid.m first
%
% Run: >> build_ss1
% -----------------------------------------------------------------------

function build_ss1()

    fprintf('=== Step 6: Building Simulink SS1 (Power Plant) ===\n\n');

    if ~evalin('base','exist(''BAT'',''var'')')
        fprintf('[INFO] Running init_microgrid first...\n');
        init_microgrid;
    end

    mdl = 'ss1_power_plant';

    if bdIsLoaded(mdl); close_system(mdl, 0); end
    if exist([mdl '.slx'],'file'); delete([mdl '.slx']); end

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
    %  LAYOUT
    %% ---------------------------------------------------------------
    X_IN   = 30;
    X_PV   = 160;    % PV source blocks
    X_MPPT = 340;    % MPPT / charge current
    X_BAT  = 520;    % battery integrator
    X_SOC  = 660;    % SOC→voltage lookup
    X_RELAY= 820;    % DPDT relay switch
    X_OUT  = 990;

    Y_PV   = 60;     % PV row
    Y_BAT  = 200;    % battery row
    Y_GRID = 340;    % grid row
    Y_LOAD = 270;    % load current row

    BH = 30; BW = 80;

    %% ---------------------------------------------------------------
    %  INPORT: relay_K1 control signal from SS2
    %% ---------------------------------------------------------------
    blk_inport(mdl, 'relay_K1', X_IN, Y_BAT, 1);

    %% ---------------------------------------------------------------
    %  PV ARRAY MODEL
    %  Irradiance profile → PV power via lookup table
    %  irr_profile variable: [time, G(W/m²)] Nx2, set by init_microgrid
    %% ---------------------------------------------------------------

    % Irradiance time series
    add_block('simulink/Sources/From Workspace', [mdl '/Irr_Profile'], ...
        'Position',     blkpos(X_PV, Y_PV, BW, BH), ...
        'VariableName', 'irr_profile', ...
        'Interpolate',  'on');

    % PV power: P = PV_PEAK * PV_EFF * (G / 1000)
    % Implemented as: Gain(PV_PEAK * PV_EFF / 1000) × irradiance
    add_block('simulink/Math Operations/Gain', [mdl '/PV_Scale'], ...
        'Position', blkpos(X_PV+100, Y_PV, 70, BH), ...
        'Gain',     'PV.Pmax_array * 0.85 / 1000');

    % Saturate PV power to 0–PV_PEAK (can't go negative)
    add_block('simulink/Discontinuities/Saturation', [mdl '/PV_Sat'], ...
        'Position',   blkpos(X_PV+190, Y_PV, 60, BH), ...
        'UpperLimit', 'PV.Pmax_array', ...
        'LowerLimit', '0');

    %% ---------------------------------------------------------------
    %  MPPT CONTROLLER MODEL
    %  Simplified: charging current = P_pv / V_bat
    %  Clamped to I_MPPT_MAX = 150A
    %  Implemented as: Divide + Saturation
    %% ---------------------------------------------------------------

    % Divide: P_pv / V_bat → I_charge_raw
    add_block('simulink/Math Operations/Divide', [mdl '/MPPT_Div'], ...
        'Position', blkpos(X_MPPT, Y_PV, 50, BH), ...
        'Inputs',   '*/');

    % Clamp to [0, 150A]
    add_block('simulink/Discontinuities/Saturation', [mdl '/MPPT_Sat'], ...
        'Position',   blkpos(X_MPPT+70, Y_PV, 60, BH), ...
        'UpperLimit', '150', ...
        'LowerLimit', '0');

    %% ---------------------------------------------------------------
    %  BATTERY ENERGY INTEGRATOR
    %  Integrates net power (charge - load) to get stored energy (Wh)
    %  dE/dt = P_charge - P_load  [W]
    %  E_bat = ∫(P_net)dt  [J] → ÷3600 → [Wh]
    %
    %  Initial condition: BAT.initial_soc × BAT.capacity_wh
    %  Limits: [0, BAT.capacity_wh]
    %% ---------------------------------------------------------------

    % Sum: P_charge (positive) - P_load (negative)
    add_block('simulink/Math Operations/Sum', [mdl '/P_net_Sum'], ...
        'Position',   blkpos(X_BAT-80, Y_BAT, 40, 40), ...
        'Inputs',     '+-', ...
        'IconShape',  'round');

    % Integrator: ∫P_net dt → Joules
    add_block('simulink/Continuous/Integrator', [mdl '/E_bat_J'], ...
        'Position',         blkpos(X_BAT, Y_BAT, 50, BH), ...
        'InitialCondition', 'BAT.initial_soc * BAT.capacity_wh * 3600', ...
        'LimitOutput',      'on', ...
        'UpperSaturationLimit', 'BAT.capacity_wh * 3600', ...
        'LowerSaturationLimit', '0');

    % Convert J → Wh
    add_block('simulink/Math Operations/Gain', [mdl '/J_to_Wh'], ...
        'Position', blkpos(X_BAT+70, Y_BAT, 55, BH), ...
        'Gain',     '1/3600');

    %% ---------------------------------------------------------------
    %  SOC → VOLTAGE LOOKUP TABLE
    %  Maps stored energy (Wh) to terminal voltage (V)
    %  Breakpoints: [0, 264, 1320, 1980, 2640] Wh
    %  Values:      [11.6, 11.8, 12.0, 12.4, 12.7] V
    %% ---------------------------------------------------------------
    add_block('simulink/Lookup Tables/1-D Lookup Table', [mdl '/SOC_to_V'], ...
        'Position',                  blkpos(X_SOC, Y_BAT, 80, BH), ...
        'BreakpointsForDimension1',  '[0, 264, 1320, 1980, 2640]', ...
        'Table',                     '[11.6, 11.8, 12.0, 12.4, 12.7]', ...
        'ExtrapMethod',              'Clip');

    %% ---------------------------------------------------------------
    %  LOAD POWER MODEL
    %  When solar active: both dryers ON = 2 × 144W = 288W
    %  When grid: battery not discharged by loads (grid supplies them)
    %  Implemented as: relay_K1 × 2 × P_DRYER
    %% ---------------------------------------------------------------
    add_block('simulink/Math Operations/Gain', [mdl '/Load_Gain'], ...
        'Position', blkpos(X_BAT-170, Y_LOAD, 70, BH), ...
        'Gain',     '2 * 144');   % 2 dryers × 144W each

    %% ---------------------------------------------------------------
    %  GRID SMPS MODEL
    %  Ideal 12V constant voltage source
    %% ---------------------------------------------------------------
    add_block('simulink/Sources/Constant', [mdl '/Grid_V'], ...
        'Position', blkpos(X_PV, Y_GRID, 60, BH), ...
        'Value',    'GRID.voltage');

    %% ---------------------------------------------------------------
    %  DPDT RELAY K1 — SOURCE SELECTOR
    %  Switch block:
    %    u1 = solar/battery bus voltage  (from SOC_to_V)
    %    u2 = relay_K1 control (from SS2)
    %    u3 = grid voltage (12V constant)
    %  When relay_K1 >= 0.5 → solar; else → grid
    %% ---------------------------------------------------------------
    add_block('simulink/Signal Routing/Switch', [mdl '/DPDT_K1'], ...
        'Position',  blkpos(X_RELAY, Y_BAT-30, 50, 80), ...
        'Criteria',  'u2 >= Threshold', ...
        'Threshold', '0.5');

    %% ---------------------------------------------------------------
    %  OUTPORTS
    %% ---------------------------------------------------------------
    blk_outport(mdl, 'bat_voltage', X_OUT, Y_BAT,    1);  % → SS2
    blk_outport(mdl, 'bus_voltage', X_OUT, Y_BAT+50, 2);  % → SS3
    blk_outport(mdl, 'pv_power',   X_OUT, Y_PV,     3);  % → logging
    blk_outport(mdl, 'bat_soc',    X_OUT, Y_BAT+100, 4); % → logging

    %% ---------------------------------------------------------------
    %  MONITOR SCOPE
    %% ---------------------------------------------------------------
    add_block('simulink/Sinks/Scope', [mdl '/SS1_Monitor'], ...
        'Position',      blkpos(X_OUT+80, 100, 40, 80), ...
        'NumInputPorts', '4');

    % SOC fraction output (for scope): E_Wh / capacity
    add_block('simulink/Math Operations/Gain', [mdl '/SOC_frac'], ...
        'Position', blkpos(X_SOC+110, Y_BAT+50, 70, BH), ...
        'Gain',     sprintf('1/%g', evalin('base','BAT.capacity_wh')));

    %% ---------------------------------------------------------------
    %  WIRING
    %% ---------------------------------------------------------------
    fprintf('[Simulink] Wiring SS1 connections...\n');

    % Irradiance → PV scale → saturation → PV power
    add_line(mdl, 'Irr_Profile/1', 'PV_Scale/1',  'autorouting','on');
    add_line(mdl, 'PV_Scale/1',    'PV_Sat/1',    'autorouting','on');

    % PV power → MPPT divide (numerator)
    add_line(mdl, 'PV_Sat/1', 'MPPT_Div/1', 'autorouting','on');

    % Battery voltage → MPPT divide (denominator) and P_net sum
    % (bat_voltage feeds back from SOC_to_V output)
    add_line(mdl, 'SOC_to_V/1', 'MPPT_Div/2',  'autorouting','on');

    % MPPT divide → clamp → charging power = I_charge × V_bat
    % We need P_charge = I_charge × V_bat
    % Implement as: Product(MPPT_Sat output × SOC_to_V output)
    add_block('simulink/Math Operations/Product', [mdl '/P_charge'], ...
        'Position', blkpos(X_MPPT+150, Y_PV, 50, BH));
    add_line(mdl, 'MPPT_Div/1',  'MPPT_Sat/1',   'autorouting','on');
    add_line(mdl, 'MPPT_Sat/1',  'P_charge/1',   'autorouting','on');
    add_line(mdl, 'SOC_to_V/1',  'P_charge/2',   'autorouting','on');

    % P_charge → P_net sum (positive input)
    add_line(mdl, 'P_charge/1', 'P_net_Sum/1', 'autorouting','on');

    % relay_K1 → Load_Gain (load only active when solar is selected)
    add_line(mdl, 'relay_K1/1', 'Load_Gain/1', 'autorouting','on');

    % Load_Gain → P_net sum (negative input — discharge)
    add_line(mdl, 'Load_Gain/1', 'P_net_Sum/2', 'autorouting','on');

    % P_net → integrator → J_to_Wh → SOC_to_V
    add_line(mdl, 'P_net_Sum/1', 'E_bat_J/1',  'autorouting','on');
    add_line(mdl, 'E_bat_J/1',   'J_to_Wh/1', 'autorouting','on');
    add_line(mdl, 'J_to_Wh/1',   'SOC_to_V/1','autorouting','on');

    % SOC_to_V → DPDT switch port 1 (solar voltage)
    add_line(mdl, 'SOC_to_V/1', 'DPDT_K1/1', 'autorouting','on');

    % relay_K1 → DPDT switch port 2 (control)
    add_line(mdl, 'relay_K1/1', 'DPDT_K1/2', 'autorouting','on');

    % Grid voltage → DPDT switch port 3 (grid fallback)
    add_line(mdl, 'Grid_V/1', 'DPDT_K1/3', 'autorouting','on');

    % DPDT output → bus_voltage outport
    add_line(mdl, 'DPDT_K1/1', 'bus_voltage/1', 'autorouting','on');

    % Battery voltage → bat_voltage outport
    add_line(mdl, 'SOC_to_V/1', 'bat_voltage/1', 'autorouting','on');

    % PV power → pv_power outport
    add_line(mdl, 'PV_Sat/1', 'pv_power/1', 'autorouting','on');

    % SOC fraction → bat_soc outport
    add_line(mdl, 'J_to_Wh/1',  'SOC_frac/1',  'autorouting','on');
    add_line(mdl, 'SOC_frac/1', 'bat_soc/1',   'autorouting','on');

    % Monitor scope connections
    add_line(mdl, 'PV_Sat/1',   'SS1_Monitor/1', 'autorouting','on');
    add_line(mdl, 'SOC_to_V/1', 'SS1_Monitor/2', 'autorouting','on');
    add_line(mdl, 'DPDT_K1/1',  'SS1_Monitor/3', 'autorouting','on');
    add_line(mdl, 'SOC_frac/1', 'SS1_Monitor/4', 'autorouting','on');

    %% ---------------------------------------------------------------
    %  SAVE
    %% ---------------------------------------------------------------
    save_system(mdl, [mdl '.slx']);
    fprintf('[OK]  Saved: %s.slx\n\n', mdl);

    %% ---------------------------------------------------------------
    %  EXPECTED OUTPUTS SUMMARY
    %% ---------------------------------------------------------------
    BAT  = evalin('base','BAT');
    PV   = evalin('base','PV');
    GRID = evalin('base','GRID');

    V_init = interp1([0,264,1320,1980,2640],[11.6,11.8,12.0,12.4,12.7], ...
        BAT.initial_soc * BAT.capacity_wh);

    fprintf('--- Expected outputs (relay_K1=1, 8h session) ---\n');
    fprintf('  Initial bat_voltage : %.2f V  (SOC=%.0f%%)\n', V_init, BAT.initial_soc*100);
    fprintf('  PV power at peak    : %.0f W  (G=950 W/m²)\n', PV.Pmax_array*0.85*950/1000);
    fprintf('  bus_voltage (solar) : ≈ %.1f–%.1f V  (follows battery SOC)\n', 11.8, 12.7);
    fprintf('  bus_voltage (grid)  : %.1f V  (SMPS constant)\n', GRID.voltage);
    fprintf('\n');
    fprintf('--- How to test SS1 standalone ---\n');
    fprintf('  1. Open ss1_power_plant.slx\n');
    fprintf('  2. Connect relay_K1 inport to a Constant = 1\n');
    fprintf('  3. Set StopTime = 28800, run\n');
    fprintf('  4. Check SS1_Monitor scope:\n');
    fprintf('     Ch1: PV power (0→peak→0 over 8h day)\n');
    fprintf('     Ch2: Battery voltage (should stay 11.8–13.0V)\n');
    fprintf('     Ch3: Bus voltage (= bat_voltage when K1=1)\n');
    fprintf('     Ch4: SOC fraction (0.8 initial, varies with net power)\n\n');
    fprintf('  Ready for Step 7: build SS2 (Auction Controller).\n\n');
end

%% =====================================================================
function p = blkpos(x, y, w, h)
    p = [x, y, x+w, y+h];
end
function blk_inport(mdl, name, x, y, n)
    add_block('built-in/Inport', [mdl '/' name], ...
        'Position', blkpos(x,y,50,20), 'Port', num2str(n));
end
function blk_outport(mdl, name, x, y, n)
    add_block('built-in/Outport', [mdl '/' name], ...
        'Position', blkpos(x,y,50,20), 'Port', num2str(n));
end