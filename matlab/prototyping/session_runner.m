%% session_runner.m
% STEP 4: Full session runner — combines Steps 1, 2, and 3.
%
% Runs all five test scenarios in sequence using the same core logic
% as the ESP32 firmware. No Simulink required.
%
% Each scenario runs a complete auction-cycle loop and reports:
%   - Solar fraction        (target >= 65%)
%   - Jain Fairness Index   (target >= 0.85 final and minimum)
%   - Energy utilisation    (target >= 15% gain vs unmanaged baseline)
%   - Battery voltage health (must stay above LVD = 11.6V)
%
% After all scenarios: comparative KPI table + summary plot.
%
% Run: >> session_runner
% -----------------------------------------------------------------------

function session_runner()

    fprintf('=== Step 4: Full Session Runner ===\n');
    fprintf('    Five scenarios | P2P auction | Battery SOC | JFI\n\n');

    %% --- Shared constants (hardware spec values) -----------------------
    C = constants();

    %% --- Define five scenarios -----------------------------------------
    scenarios = define_scenarios(C);

    %% --- Run each scenario ---------------------------------------------
    nS = numel(scenarios);
    results(nS) = result_template();

    for s = 1:nS
        fprintf('[%d/%d] Running: %s\n', s, nS, scenarios(s).label);
        results(s) = run_scenario(scenarios(s), C);
        print_kpi_row(results(s));
        fprintf('\n');
    end

    %% --- Comparative KPI table -----------------------------------------
    print_kpi_table(results);

    %% --- Summary plot --------------------------------------------------
    plot_summary(results, C);

    fprintf('\n  All scenarios complete.\n');
    fprintf('  Next: Step 5 — build Simulink subsystem SS3 (dryer loads).\n\n');

end

%% =====================================================================
%%  CONSTANTS
%% =====================================================================
function C = constants()
    C.V_GRID_SWITCH = 11.8;
    C.V_LVD         = 11.6;
    C.V_BULK        = 14.4;
    C.RH_CRIT       = 0.80;
    C.BID_H         = 140;
    C.BID_L         = 100;
    C.P_DRYER       = 144;     % W per dryer node at 12V
    C.T_CYCLE       = 10;      % s
    C.T_SIM         = 28800;   % s (8 hours)
    C.N_CYCLES      = C.T_SIM / C.T_CYCLE;
    C.BAT_CAP_WH    = 2640;    % 12V × 220Ah
    C.PV_PEAK       = 1410;    % W at STC
    C.PV_EFF        = 0.85;
    C.I_MPPT_MAX    = 150;     % A

    % SOC → voltage lookup (ESP32 table)
    C.SOC_WH = [0, 264, 1320, 1980, 2640];
    C.SOC_V  = [11.6, 11.8, 12.0, 12.4, 12.7];

    % Irradiance profile
    C.irr_time = [0,    1800, 3600, 7200, 10800, 14400, 18000, 21600, 25200, 28800];
    C.irr_vals = [100,  250,  500,  700,  900,   950,   850,   650,   350,   100  ];
end

%% =====================================================================
%%  SCENARIO DEFINITIONS
%% =====================================================================
function S = define_scenarios(C)

    % Default RH profiles (realistic 8-hour drying)
    rh1_t = [0,    1800, 3600, 7200,  14400, 21600, 28800];
    rh1_v = [0.40, 0.60, 0.85, 0.90,  0.75,  0.55,  0.40];
    rh2_t = [0,    3600, 7200, 10800, 18000, 25200, 28800];
    rh2_v = [0.40, 0.45, 0.82, 0.90,  0.70,  0.50,  0.38];

    % ---- Scenario 1: Tie-break -----------------------------------------
    S(1).label    = 'tie_break — equal bids, Node 1 wins by rule';
    S(1).soc_init = 0.80;
    S(1).t_run    = 3600;      % 1 hour sufficient
    S(1).rh1_t    = rh1_t;  S(1).rh1_v = repmat(0.60, size(rh1_t));
    S(1).rh2_t    = rh2_t;  S(1).rh2_v = repmat(0.60, size(rh2_t));
    S(1).btn2_on  = [0, 0];    % [start, end] seconds — button not pressed

    % ---- Scenario 2: Node 1 critical -----------------------------------
    S(2).label    = 'critical_n1 — RH1=0.87 critical, RH2=0.55 standard';
    S(2).soc_init = 0.80;
    S(2).t_run    = 3600;
    S(2).rh1_t    = rh1_t;  S(2).rh1_v = repmat(0.87, size(rh1_t));
    S(2).rh2_t    = rh2_t;  S(2).rh2_v = repmat(0.55, size(rh2_t));
    S(2).btn2_on  = [0, 0];

    % ---- Scenario 3: Grid forced ---------------------------------------
    S(3).label    = 'grid_force — battery at 7% SOC, forced grid mode';
    S(3).soc_init = 0.07;     % low battery
    S(3).t_run    = 3600;
    S(3).rh1_t    = rh1_t;  S(3).rh1_v = rh1_v;
    S(3).rh2_t    = rh2_t;  S(3).rh2_v = rh2_v;
    S(3).btn2_on  = [0, 0];

    % ---- Scenario 4: Manual override -----------------------------------
    S(4).label    = 'override_n2 — N1 critical + N2 button 5400-7200s';
    S(4).soc_init = 0.80;
    S(4).t_run    = C.T_SIM;  % full 8 hours to see button effect
    S(4).rh1_t    = rh1_t;  S(4).rh1_v = repmat(0.87, size(rh1_t));
    S(4).rh2_t    = rh2_t;  S(4).rh2_v = repmat(0.55, size(rh2_t));
    S(4).btn2_on  = [5400, 7200];   % button pressed 5400–7200s

    % ---- Scenario 5: Full 8-hour session --------------------------------
    S(5).label    = 'full_session — 8-hour realistic drying profiles';
    S(5).soc_init = 0.80;
    S(5).t_run    = C.T_SIM;
    S(5).rh1_t    = rh1_t;  S(5).rh1_v = rh1_v;
    S(5).rh2_t    = rh2_t;  S(5).rh2_v = rh2_v;
    S(5).btn2_on  = [0, 0];
end

%% =====================================================================
%%  CORE SIMULATION LOOP
%% =====================================================================
function R = run_scenario(S, C)

    N = S.t_run / C.T_CYCLE;
    t_vec = (0 : C.T_CYCLE : S.t_run - C.T_CYCLE);

    % Interpolate profiles onto cycle times
    rh1 = clamp(interp1(S.rh1_t, S.rh1_v, t_vec, 'pchip'));
    rh2 = clamp(interp1(S.rh2_t, S.rh2_v, t_vec, 'pchip'));
    irr = max(interp1(C.irr_time, C.irr_vals, t_vec, 'pchip'), 0);
    P_pv = C.PV_PEAK * C.PV_EFF * (irr / 1000);

    % Button signal: 1 during btn2_on window, else 0
    btn2 = double(t_vec >= S.btn2_on(1) & t_vec <= S.btn2_on(2) & S.btn2_on(2) > 0);

    % State
    E_bat  = S.soc_init * C.BAT_CAP_WH;
    E1_cum = 0;   E2_cum = 0;
    E_per  = C.P_DRYER * C.T_CYCLE / 3600;   % Wh per cycle per node

    % Result arrays
    V_bat_arr  = zeros(1, N);
    src_arr    = zeros(1, N);
    winner_arr = zeros(1, N);
    jfi_arr    = zeros(1, N);
    bid1_arr   = zeros(1, N);
    bid2_arr   = zeros(1, N);

    for k = 1:N

        % Battery voltage
        V_bat = clamp_v(interp1(C.SOC_WH, C.SOC_V, E_bat, 'linear', 'extrap'), 10.5, 14.6);
        V_bat_arr(k) = V_bat;

        % Solar availability
        solar = (V_bat >= C.V_GRID_SWITCH);
        src_arr(k) = double(solar);

        % Bid formulation (Step 1 logic)
        bid1 = C.BID_L + (C.BID_H - C.BID_L) * double(rh1(k) >= C.RH_CRIT);
        bid2 = C.BID_L + (C.BID_H - C.BID_L) * double(rh2(k) >= C.RH_CRIT || btn2(k) >= 0.5);
        bid1_arr(k) = bid1;   bid2_arr(k) = bid2;

        % Market clearing (Step 1 logic)
        if solar
            winner = 1 + double(bid2 > bid1);
        else
            winner = 0;
        end
        winner_arr(k) = winner;

        % Energy accounting (Step 2 logic)
        E1_cum = E1_cum + E_per * double(winner == 1);
        E2_cum = E2_cum + E_per * double(winner == 2);

        % JFI (Step 2 logic)
        jfi_arr(k) = compute_jfi(E1_cum, E2_cum);

        % Battery energy balance (Step 3 logic)
        P_charge = min(P_pv(k), C.I_MPPT_MAX * V_bat);
        P_load   = 2 * C.P_DRYER * double(solar);
        E_bat    = clamp_v(E_bat + (P_charge - P_load) * C.T_CYCLE / 3600, 0, C.BAT_CAP_WH);
    end

    %% Compute KPIs
    solar_frac  = mean(src_arr);
    n1_wins     = sum(winner_arr == 1);
    n2_wins     = sum(winner_arr == 2);
    grid_cycles = sum(winner_arr == 0);

    % Energy utilisation gain vs unmanaged baseline
    % Unmanaged: no auction, solar split equally → each node gets 50% of solar
    E_solar_managed  = (E1_cum + E2_cum);
    E_solar_baseline = solar_frac * S.t_run / 3600 * C.P_DRYER; % 1 node, whole solar window
    util_gain        = max((E_solar_managed - E_solar_baseline) / max(E_solar_baseline,1) * 100, 0);

    R.label       = S.label;
    R.t_run       = S.t_run;
    R.t_vec       = t_vec;
    R.V_bat       = V_bat_arr;
    R.src         = src_arr;
    R.winner      = winner_arr;
    R.jfi         = jfi_arr;
    R.rh1         = rh1;
    R.rh2         = rh2;
    R.bid1        = bid1_arr;
    R.bid2        = bid2_arr;
    R.E1_Wh       = E1_cum;
    R.E2_Wh       = E2_cum;
    R.solar_frac  = solar_frac;
    R.n1_wins     = n1_wins;
    R.n2_wins     = n2_wins;
    R.grid_cycles = grid_cycles;
    R.jfi_final   = jfi_arr(end);
    R.jfi_min     = min(jfi_arr);
    R.jfi_mean    = mean(jfi_arr);
    R.util_gain   = util_gain;
    R.V_final     = V_bat_arr(end);
    R.N_cycles    = N;
end

%% =====================================================================
%%  PRINT HELPERS
%% =====================================================================
function print_kpi_row(R)
    ok = @(b) char('✗' + double(b)*2);
    fprintf('    Solar: %4.1f%% %s | JFI: %.3f %s (min %.3f %s) | Gain: %+5.1f%% %s | Vbat: %.2fV %s\n', ...
        R.solar_frac*100,  ok(R.solar_frac >= 0.65), ...
        R.jfi_final,       ok(R.jfi_final  >= 0.85), ...
        R.jfi_min,         ok(R.jfi_min    >= 0.85), ...
        R.util_gain,       ok(R.util_gain  >= 15), ...
        R.V_final,         ok(R.V_final    >= 11.6));
end

function print_kpi_table(results)
    fprintf('\n');
    fprintf('  ╔══════════════════════════╦════════╦═══════╦═══════╦════════╦════════╗\n');
    fprintf('  ║ Scenario                 ║ Solar  ║ JFI   ║ JFI   ║ Util   ║ Vbat   ║\n');
    fprintf('  ║                          ║ %%      ║ final ║ min   ║ gain%% ║ final  ║\n');
    fprintf('  ╠══════════════════════════╬════════╬═══════╬═══════╬════════╬════════╣\n');
    ok = @(b) char('✗' + double(b)*2);
    for s = 1:numel(results)
        R = results(s);
        lbl = strtrim(strsplit(R.label,' —')); lbl = lbl{1};
        fprintf('  ║ %-24s ║ %4.1f%% %s ║ %.3f%s ║ %.3f%s ║ %+5.1f%% %s ║ %.2fV %s ║\n', ...
            lbl, ...
            R.solar_frac*100,  ok(R.solar_frac >= 0.65), ...
            R.jfi_final,       ok(R.jfi_final  >= 0.85), ...
            R.jfi_min,         ok(R.jfi_min    >= 0.85), ...
            R.util_gain,       ok(R.util_gain  >= 15), ...
            R.V_final,         ok(R.V_final    >= 11.6));
    end
    fprintf('  ╚══════════════════════════╩════════╩═══════╩═══════╩════════╩════════╝\n');
    fprintf('  Targets: Solar ≥65%% | JFI ≥0.85 | Util gain ≥15%% | Vbat ≥11.6V\n\n');
end

%% =====================================================================
%%  SUMMARY PLOT
%% =====================================================================
function plot_summary(results, C)

    % Colours
    col_n1  = [0.18, 0.72, 0.44];
    col_n2  = [0.85, 0.28, 0.20];
    col_sol = [1.00, 0.65, 0.00];
    col_jfi = [0.50, 0.20, 0.80];

    nS = numel(results);
    fig = figure('Name','Step 4: Session Runner — All Scenarios', ...
                 'Color','w','Position',[60 40 1200 800]);

    for s = 1:nS
        R = results(s);
        t_h = R.t_vec / 3600;

        % Each scenario gets one column of 3 rows
        % Row 1: Battery voltage
        subplot(3, nS, s);
        plot(t_h, R.V_bat, 'k-', 'LineWidth', 1.4); hold on;
        yline(C.V_GRID_SWITCH, 'b--', 'LineWidth', 1.2);
        yline(C.V_LVD,         'r:',  'LineWidth', 1.0);
        ylim([11.0 13.5]);
        ylabel('V_{bat} (V)'); xlabel('t (h)');
        title(format_title(R.label), 'FontSize', 8, 'Interpreter','none');
        grid on; set(gca,'Color',[0.97 0.97 0.97]);
        if s == 1
            legend('V_{bat}','Grid sw 11.8V','LVD 11.6V','Location','southeast','FontSize',7);
        end

        % Row 2: Source mode + RH
        subplot(3, nS, nS + s);
        yyaxis left
        area(t_h, R.src * 100, 'FaceColor', col_sol, 'FaceAlpha', 0.5, 'EdgeColor','none');
        ylabel('Solar (%)'); ylim([0 130]);
        yyaxis right
        plot(t_h, R.rh1 * 100, 'Color', col_n1, 'LineWidth', 1.4); hold on;
        plot(t_h, R.rh2 * 100, 'Color', col_n2, 'LineWidth', 1.4);
        yline(80, 'k--', 'LineWidth', 0.9);
        ylabel('RH (%)'); ylim([20 110]); xlabel('t (h)');
        grid on; set(gca,'Color',[0.97 0.97 0.97]);
        if s == 1
            legend('','N1 RH','N2 RH','80% crit','Location','northeast','FontSize',7);
        end

        % Row 3: JFI
        subplot(3, nS, 2*nS + s);
        plot(t_h, R.jfi, 'Color', col_jfi, 'LineWidth', 1.6); hold on;
        yline(0.85, 'r--', 'LineWidth', 1.2);
        ylim([0.45 1.05]);
        ylabel('JFI'); xlabel('t (h)');
        title(sprintf('JFI=%.3f min=%.3f', R.jfi_final, R.jfi_min), 'FontSize', 8);
        grid on; set(gca,'Color',[0.97 0.97 0.97]);
    end

    sgtitle('AutaNet P2P Microgrid — Step 4: All Scenarios', ...
        'FontSize', 13, 'FontWeight', 'bold');
end

function t = format_title(label)
    % Extract short name before ' —'
    parts = strsplit(label, ' —');
    t = strtrim(parts{1});
    t = strrep(t, '_', '\_');
end

%% =====================================================================
%%  HELPER FUNCTIONS
%% =====================================================================
function jfi = compute_jfi(E1, E2)
    if E1 == 0 && E2 == 0; jfi = 1.0; return; end
    d = 2*(E1^2 + E2^2);
    if d < 1e-12; jfi = 1.0; return; end
    jfi = min(max((E1+E2)^2 / d, 0.0), 1.0);
end

function v = clamp(x); v = max(min(x, 1.0), 0.0); end
function v = clamp_v(x, lo, hi); v = min(max(x, lo), hi); end

function R = result_template()
    R = struct('label','','t_run',0,'t_vec',[],'V_bat',[],'src',[], ...
        'winner',[],'jfi',[],'rh1',[],'rh2',[],'bid1',[],'bid2',[], ...
        'E1_Wh',0,'E2_Wh',0,'solar_frac',0,'n1_wins',0,'n2_wins',0, ...
        'grid_cycles',0,'jfi_final',0,'jfi_min',0,'jfi_mean',0, ...
        'util_gain',0,'V_final',0,'N_cycles',0);
end