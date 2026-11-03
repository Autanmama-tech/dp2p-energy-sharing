%% init_microgrid.m
% Workspace initialisation for the P2P Microgrid Simulink model.
%
% MUST be run before build_model.m and run_simulation.m.
% Populates structs (PV, BAT, GRID, DRY, AUC, SIM) AND the flat
% workspace variables that Simulink block parameters reference directly.
%
% Key flat variables exported to base workspace:
%   irr_profile   — [Nx2] irradiance time series  (From Workspace block)
%   N1_rh         — [Nx2] Node 1 RH time series   (From Workspace block)
%   N2_rh         — [Nx2] Node 2 RH time series   (From Workspace block)
%   btn1_ts       — [Nx2] Button 1 signal          (top-level Btn_N1)
%   btn2_ts       — [Nx2] Button 2 signal          (top-level Btn_N2)
%
% -----------------------------------------------------------------------
clc;   % no clearvars — let the caller manage its own workspace
fprintf('=== AutaNet P2P Microgrid: Initialising workspace ===\n');
fprintf('    Running from: %s\n\n', mfilename('fullpath'));

%% ---- 1. PV ARRAY -------------------------------------------------------
PV.n_panels       = 3;
PV.Pmax_panel     = 470;          % W rated per panel
PV.Vmp            = 38.5;         % V at max power
PV.Imp            = 12.2;         % A at max power
PV.Voc            = 47.0;         % V open-circuit
PV.Isc            = 13.0;         % A short-circuit
PV.Pmax_array     = PV.Pmax_panel * PV.n_panels;   % 1410 W
PV.Imp_array      = PV.Imp * PV.n_panels;           % 36.6 A

% 8-hour irradiance profile — [time(s), G(W/m²)]
PV.irr_time   = [0,    1800, 3600, 7200, 10800, 14400, 18000, 21600, 25200, 28800];
PV.irr_values = [100,  250,  500,  700,  900,   950,   850,   650,   350,   100  ];

% Export as Nx2 matrix for Simulink "From Workspace" block
irr_profile = [PV.irr_time', PV.irr_values'];    %#ok<NASGU> — exported below

fprintf('[PV]  %d×%.0fW panels | %.0fW array peak | Vmp=%.1fV\n', ...
    PV.n_panels, PV.Pmax_panel, PV.Pmax_array, PV.Vmp);

%% ---- 2. BATTERY --------------------------------------------------------
BAT.nominal_voltage  = 12;         % V
BAT.capacity_ah      = 220;        % Ah
BAT.capacity_wh      = BAT.nominal_voltage * BAT.capacity_ah;   % 2640 Wh
BAT.usable_wh        = BAT.capacity_wh * 0.50;                  % 1320 Wh
BAT.initial_soc      = 0.80;       % 80 % SOC

% MPPT charge controller thresholds
BAT.V_bulk           = 14.4;       % V
BAT.V_float          = 13.8;       % V
BAT.V_LVD            = 11.6;       % V — low-voltage disconnect
BAT.V_LVR            = 12.6;       % V — low-voltage reconnect
BAT.V_grid_switch    = 11.8;       % V — switch to grid

% Internal resistance (used by Simulink battery block)
BAT.Rint             = 0.015;      % Ohm

fprintf('[BAT] 12V | %dAh | %.0fWh usable | SOC_init=%d%%\n', ...
    BAT.capacity_ah, BAT.usable_wh, round(BAT.initial_soc*100));

%% ---- 3. GRID SMPS ------------------------------------------------------
GRID.voltage     = 12;             % V DC output
GRID.current_max = 50;             % A
GRID.power_max   = GRID.voltage * GRID.current_max;   % 600 W

fprintf('[GRID] %dV | %dA | %dW\n', GRID.voltage, GRID.current_max, GRID.power_max);

%% ---- 4. DRYER LOADS ----------------------------------------------------
DRY.resistance     = 1;            % Ohm (wire-wound 150W)
DRY.power_at_12V   = 12^2 / DRY.resistance;   % 144 W

% AHT21 humidity profiles — realistic 8-hour drying dynamics
% Node 1: rises sharply early (heavily loaded crop)
DRY.N1.rh_time   = [0,    1800, 3600, 7200, 14400, 21600, 28800];
DRY.N1.rh_values = [0.40, 0.60, 0.85, 0.90, 0.75,  0.55,  0.40];

% Node 2: rises later, offset from Node 1
DRY.N2.rh_time   = [0,    3600, 7200, 10800, 18000, 25200, 28800];
DRY.N2.rh_values = [0.40, 0.45, 0.82, 0.90,  0.70,  0.50,  0.38];

% Export as Nx2 [time, value] matrices for From Workspace blocks
N1_rh = [DRY.N1.rh_time', DRY.N1.rh_values'];    %#ok<NASGU>
N2_rh = [DRY.N2.rh_time', DRY.N2.rh_values'];    %#ok<NASGU>

fprintf('[DRY]  1Ω load | %.0fW at 12V nominal\n', DRY.power_at_12V);

%% ---- 5. AUCTION PROTOCOL -----------------------------------------------
AUC.cycle_s       = 10;            % seconds — auction period
AUC.bid_critical  = 140;          % units/kWh
AUC.bid_standard  = 100;          % units/kWh
AUC.rh_threshold  = 0.80;         % fraction — triggers critical bid
AUC.tiebreak_node = 1;            % Node 1 wins on equal bids
AUC.jfi_target    = 0.85;         % Jain Fairness Index minimum

fprintf('[AUC]  Cycle=%ds | Critical=%d | Standard=%d | JFI_target=%.2f\n', ...
    AUC.cycle_s, AUC.bid_critical, AUC.bid_standard, AUC.jfi_target);

%% ---- 6. SIMULATION CONFIG ----------------------------------------------
SIM.model_name    = 'p2p_microgrid';
SIM.t_stop        = 28800;         % 8 hours (s)
SIM.t_step        = 0.1;           % solver max step (s)
SIM.solver        = 'ode45';

Tsim = SIM.t_stop;                 %#ok<NASGU> — flat var for Simulink

fprintf('[SIM]  %.0fh | model: %s\n\n', SIM.t_stop/3600, SIM.model_name);

%% ---- 7. BUTTON SIGNALS (top-level Constant blocks, override below) ----
% Default: both buttons not pressed throughout session
btn1_ts = [0, 0; SIM.t_stop, 0];  %#ok<NASGU>
btn2_ts = [0, 0; SIM.t_stop, 0];  %#ok<NASGU>

% For the override scenario (Node 2 button pressed 5400–7200s):
%   >> btn2_ts = [0,0; 5399,0; 5400,1; 7200,1; 7201,0; 28800,0];
%   >> assignin('base','btn2_ts',btn2_ts)
%   Then change Btn_N2 block to use From Workspace variable btn2_ts

%% ---- 8. HELPER VARIABLES used by Simulink block parameters ------------
% These are evaluated in the base workspace by Simulink parameter expressions
Ts_power = SIM.t_step;             % sample time for power measurement blocks
Ts_auctionCtrl = AUC.cycle_s;     %#ok<NASGU>

%% ---- 9. EXPORT EVERYTHING TO BASE WORKSPACE ---------------------------
vars = {'PV','BAT','GRID','DRY','AUC','SIM', ...
        'irr_profile','N1_rh','N2_rh', ...
        'btn1_ts','btn2_ts', ...
        'Tsim','Ts_power','Ts_auctionCtrl'};

for k = 1:numel(vars)
    assignin('base', vars{k}, eval(vars{k}));
end

% Also export a flat RH base for initial value on From Workspace blocks
RH1_base = DRY.N1.rh_values(1);
RH2_base = DRY.N2.rh_values(1);
RH1_ts   = N1_rh;  % duplicate alias %#ok<NASGU>
RH2_ts   = N2_rh;
assignin('base','RH1_base', RH1_base);
assignin('base','RH2_base', RH2_base);
assignin('base','RH1_ts',   RH1_ts);
assignin('base','RH2_ts',   RH2_ts);

fprintf('[OK]  %d variables exported to base workspace.\n', numel(vars)+4);
fprintf('      Next: >> build_model\n\n');

%% ---- 10. SELF-TEST: run auction logic on representative inputs ---------
fprintf('--- Quick auction self-check ---\n');
run_auction_check();
fprintf('--------------------------------\n\n');

%% =========================================================================
function run_auction_check()
%% Verifies the auction logic inline — no external dependencies

    V_GRID  = 11.8;
    RH_CRIT = 0.80;
    BH = 140; BL = 100;

    tests = {
      %  Vbat   rh1   rh2  b1 b2   expected_winner  expected_solar
        12.5,  0.60, 0.60, 0, 0,   1,               1;   % tie → N1
        12.5,  0.85, 0.60, 0, 0,   1,               1;   % N1 critical
        12.5,  0.60, 0.90, 0, 0,   2,               1;   % N2 critical
        11.5,  0.85, 0.60, 0, 0,   0,               0;   % bat low → grid
        12.5,  0.85, 0.60, 0, 1,   1,               1;   % N2 override, still tie→N1
    };

    descs = {'Tie-break','N1 critical','N2 critical','Grid-force','N2 override+N1 crit'};
    all_pass = true;

    for k = 1:size(tests,1)
        Vb=tests{k,1}; r1=tests{k,2}; r2=tests{k,3};
        b1=tests{k,4}; b2=tests{k,5};
        exp_w=tests{k,6}; exp_s=tests{k,7};

        solar = Vb >= V_GRID;
        bid1 = BH*(b1>=0.5 || r1>=RH_CRIT) + BL*(b1<0.5 && r1<RH_CRIT);
        bid2 = BH*(b2>=0.5 || r2>=RH_CRIT) + BL*(b2<0.5 && r2<RH_CRIT);
        if solar
            win = 1 + (bid2 > bid1);
            src = 1;
        else
            win = 0; src = 0;
        end
        ok = (win == exp_w) && (src == exp_s);
        all_pass = all_pass && ok;
        fprintf('  [%s] Test %-2d (%s): winner=%d src=%d\n', ...
            char('✗'+(ok*2)), k, descs{k}, win, src);
    end

    if all_pass
        fprintf('  All checks passed.\n');
    else
        fprintf('  WARNING: one or more checks failed — review auction logic.\n');
    end
end