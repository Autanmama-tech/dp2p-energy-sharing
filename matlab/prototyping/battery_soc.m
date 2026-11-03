%% battery_soc.m
% STEP 3: Battery State of Charge model with voltage tracking.
%
% Builds on Steps 1-2 by adding:
%   - Energy balance: battery charges from PV, discharges to dryer loads
%   - SOC → voltage lookup (the same table the hub ESP32 uses)
%   - Grid-switch logic responding to live voltage
%   - Source mode timeline over a full session
%
% No Simulink yet — everything is a simple for-loop over time.
%
% Run: >> battery_soc
% -----------------------------------------------------------------------

function battery_soc()

    fprintf('=== Step 3: Battery SOC Model ===\n\n');

    %% --- System constants ---
    V_GRID_SWITCH = 11.8;   % V  — switch to grid below this
    V_LVD         = 11.6;   % V  — low-voltage disconnect (MPPT threshold)
    V_BULK        = 14.4;   % V  — bulk charge ceiling
    V_FLOAT       = 13.8;   % V  — float charge setpoint

    BAT_CAP_WH    = 2640;   % Wh — 12V × 220Ah
    BAT_SOC_INIT  = 0.80;   % 80% initial SOC
    E_INIT        = BAT_SOC_INIT * BAT_CAP_WH;   % 2112 Wh

    P_DRYER       = 144;    % W  — one dryer at 12V (V²/R = 144/1)
    T_CYCLE       = 10;     % s  — auction period
    T_SIM         = 28800;  % s  — 8 hours
    N_CYCLES      = T_SIM / T_CYCLE;   % 2880 auction cycles

    % SOC-to-voltage lookup (from hardware spec, hub ESP32 table)
    %   Stored energy (Wh) → terminal voltage (V)
    SOC_WH  = [0, 0.10, 0.50, 0.75, 1.00] .* BAT_CAP_WH;  % [0, 264, 1320, 1980, 2640]
    SOC_V   = [11.6, 11.8, 12.0, 12.4, 12.7];

    %% --- Irradiance profile (W/m²) → PV power (W) ---------------------
    % 8-hour day profile, sampled at auction cycle resolution
    irr_time = [0,    1800, 3600, 7200, 10800, 14400, 18000, 21600, 25200, 28800];
    irr_vals = [100,  250,  500,  700,  900,   950,   850,   650,   350,   100  ];

    % PV array: 3 × 470W panels. Simple linear scaling from irradiance.
    % At 1000 W/m² → 1410 W. Efficiency curve captured by scale factor 0.85.
    PV_PEAK  = 1410;        % W at STC
    PV_EFF   = 0.85;        % combined MPPT + mismatch efficiency factor
    I_MPPT_MAX = 150;       % A — controller current limit

    %% --- Pre-compute PV power at each cycle time step ------------------
    t_vec   = (0 : T_CYCLE : T_SIM - T_CYCLE);   % cycle start times (s)
    irr_vec = interp1(irr_time, irr_vals, t_vec, 'pchip');
    irr_vec = max(irr_vec, 0);
    P_pv    = PV_PEAK * PV_EFF * (irr_vec / 1000);   % W

    %% --- Session simulation --------------------------------------------
    E_bat   = E_INIT;       % Wh stored in battery
    E1_cum  = 0;            % cumulative solar Wh to Node 1
    E2_cum  = 0;            % cumulative solar Wh to Node 2

    % Pre-allocate result arrays
    V_bat_vec    = zeros(1, N_CYCLES);
    src_mode_vec = zeros(1, N_CYCLES);   % 1=solar, 0=grid
    winner_vec   = zeros(1, N_CYCLES);
    jfi_vec      = zeros(1, N_CYCLES);
    P_pv_vec     = P_pv;

    % Realistic humidity profiles (same as system description)
    rh1_time = [0,    1800, 3600, 7200,  14400, 21600, 28800];
    rh1_vals = [0.40, 0.60, 0.85, 0.90,  0.75,  0.55,  0.40];
    rh2_time = [0,    3600, 7200, 10800, 18000, 25200, 28800];
    rh2_vals = [0.40, 0.45, 0.82, 0.90,  0.70,  0.50,  0.38];

    rh1_vec = max(min(interp1(rh1_time, rh1_vals, t_vec, 'pchip'), 1), 0);
    rh2_vec = max(min(interp1(rh2_time, rh2_vals, t_vec, 'pchip'), 1), 0);

    for k = 1:N_CYCLES

        % --- Battery voltage from stored energy (lookup table) ---
        V_bat = interp1(SOC_WH, SOC_V, E_bat, 'linear', 'extrap');
        V_bat = min(max(V_bat, 10.5), 14.6);   % hard clamp
        V_bat_vec(k) = V_bat;

        % --- Solar availability decision ---
        solar = (V_bat >= V_GRID_SWITCH);
        src_mode_vec(k) = double(solar);

        % --- Bid formulation (from Step 1) ---
        rh1 = rh1_vec(k);
        rh2 = rh2_vec(k);
        bid1 = 100 + 40 * (rh1 >= 0.80);
        bid2 = 100 + 40 * (rh2 >= 0.80);

        % --- Market clearing ---
        % NOTE: The hardware spec says Node 1 always wins ties.
        % That rule is correct for the ESP32 firmware.
        % However, over a full 8-hour session where 78% of cycles are ties,
        % always-N1 collapses JFI to ~0.59. In the Simulink model (Step 4)
        % the JFI feedback loop will flag this so operators can intervene.
        % For this standalone simulation we use the spec-compliant rule.
        if solar
            winner = 1 + (bid2 > bid1);   % 1 if bid1>=bid2 (includes tie), else 2
        else
            winner = 0;
        end
        winner_vec(k) = winner;

        % --- Energy accounting ---
        E_per_cycle = P_DRYER * T_CYCLE / 3600;   % 0.4 Wh

        % Solar energy allocation (JFI tracks this)
        E1_cum = E1_cum + E_per_cycle * (winner == 1);
        E2_cum = E2_cum + E_per_cycle * (winner == 2);

        % Battery energy balance:
        %   Charge: PV power * cycle duration
        %   Discharge: both dryers running (2 × 144W), regardless of source
        %   (when on grid, battery is not being discharged by loads — only self-discharge)
        P_charge  = min(P_pv(k), I_MPPT_MAX * V_bat);   % W, MPPT-clamped
        P_load    = 2 * P_DRYER * double(solar);         % discharge only when on solar
        P_net     = P_charge - P_load;                   % W

        dE = P_net * T_CYCLE / 3600;                     % Wh this cycle
        E_bat = min(max(E_bat + dE, 0), BAT_CAP_WH);    % clamp to [0, 2640 Wh]

        % --- JFI ---
        jfi_vec(k) = compute_jfi(E1_cum, E2_cum);
    end

    %% --- Results -------------------------------------------------------
    solar_fraction = mean(src_mode_vec);
    n1_wins = sum(winner_vec == 1);
    n2_wins = sum(winner_vec == 2);
    grid_cycles = sum(winner_vec == 0);

    fprintf('  Session: %d cycles (%.0f hours)\n\n', N_CYCLES, T_SIM/3600);
    fprintf('  %-28s : %.2f V\n', 'Initial battery voltage',   interp1(SOC_WH, SOC_V, E_INIT));
    fprintf('  %-28s : %.2f V\n', 'Final battery voltage',     V_bat_vec(end));
    fprintf('  %-28s : %.1f%%\n', 'Solar fraction',            solar_fraction*100);
    fprintf('  %-28s : %d / %d / %d\n', 'Wins N1 / N2 / Grid', n1_wins, n2_wins, grid_cycles);
    fprintf('  %-28s : %.0f Wh / %.0f Wh\n', 'Solar energy N1 / N2',  E1_cum, E2_cum);
    fprintf('  %-28s : %.4f\n', 'Final JFI',                  jfi_vec(end));
    fprintf('  %-28s : %.4f\n', 'Minimum JFI',                min(jfi_vec));
    fprintf('\n');

    %% --- KPI checks ----------------------------------------------------
    fprintf('  KPI Checks:\n');
    kpi(solar_fraction >= 0.65,  sprintf('Solar fraction %.1f%%  (target ≥65%%)',  solar_fraction*100));
    kpi(jfi_vec(end)   >= 0.85,  sprintf('JFI final %.4f       (target ≥0.85)',   jfi_vec(end)));
    kpi(min(jfi_vec)   >= 0.85,  sprintf('JFI minimum %.4f     (target ≥0.85)',   min(jfi_vec)));
    kpi(V_bat_vec(end) >= V_LVD, sprintf('Final voltage %.2fV   (LVD = %.1fV)',   V_bat_vec(end), V_LVD));
    fprintf('\n');

    %% --- Plot ----------------------------------------------------------
    t_h = t_vec / 3600;   % time in hours

    figure('Name','Step 3: Battery SOC Model','Color','w', ...
           'Position',[100 80 1000 650]);

    % Panel 1: PV power and source mode
    subplot(4,1,1);
    yyaxis left
    plot(t_h, P_pv_vec, 'Color',[1 0.6 0], 'LineWidth', 1.8);
    ylabel('PV Power (W)'); ylim([0 1600]);
    yyaxis right
    area(t_h, src_mode_vec * 100, 'FaceColor',[0.2 0.7 0.3], ...
        'EdgeColor','none', 'FaceAlpha', 0.4);
    ylabel('Solar mode (%)'); ylim([0 130]);
    xlabel('Time (hours)');
    title('PV Array Power and Source Mode (green = solar active)');
    grid on;

    % Panel 2: Battery voltage with thresholds
    subplot(4,1,2);
    plot(t_h, V_bat_vec, 'k-', 'LineWidth', 2.0); hold on;
    yline(V_GRID_SWITCH, 'b--', 'LineWidth', 1.4, 'Label', 'Grid switch 11.8V');
    yline(V_LVD,         'r:',  'LineWidth', 1.4, 'Label', 'LVD 11.6V');
    yline(V_BULK,        'g--', 'LineWidth', 1.4, 'Label', 'Bulk 14.4V');
    ylabel('Battery Voltage (V)'); xlabel('Time (hours)');
    title('Battery Terminal Voltage'); ylim([11.0 15.0]); grid on;

    % Panel 3: Humidity profiles and auction winners
    subplot(4,1,3);
    plot(t_h, rh1_vec * 100, 'Color',[0.18 0.72 0.44], 'LineWidth',1.8); hold on;
    plot(t_h, rh2_vec * 100, 'Color',[0.85 0.28 0.20], 'LineWidth',1.8);
    yline(80, 'k--', 'LineWidth',1.2, 'Label','Critical 80%');
    ylabel('RH (%)'); xlabel('Time (hours)'); ylim([30 100]);
    legend('Node 1 RH','Node 2 RH','Location','northeast');
    title('Chamber Humidity (AHT21)'); grid on;

    % Panel 4: JFI trajectory
    subplot(4,1,4);
    plot(t_h, jfi_vec, 'Color',[0.5 0.2 0.8], 'LineWidth', 2.0); hold on;
    yline(0.85, 'r--', 'LineWidth', 1.5, 'Label','Target JFI = 0.85');
    yline(1.00, ':',   'Color',[0.7 0.7 0.7], 'LineWidth', 1.0);
    ylabel('JFI'); xlabel('Time (hours)'); ylim([0.6 1.05]);
    title(sprintf('Jain Fairness Index  (final=%.4f, min=%.4f)', jfi_vec(end), min(jfi_vec)));
    grid on;

    sgtitle('AutaNet P2P Microgrid — Step 3: Battery SOC + Auction', ...
        'FontSize', 13, 'FontWeight', 'bold');

    fprintf('  Ready for Step 4: combine all three into the full session runner.\n\n');

end

%% =====================================================================
function jfi = compute_jfi(E1, E2)
    if (E1 == 0) && (E2 == 0); jfi = 1.0; return; end
    d = 2 * (E1^2 + E2^2);
    if d < 1e-12; jfi = 1.0; return; end
    jfi = min(max((E1 + E2)^2 / d, 0.0), 1.0);
end

function kpi(pass, msg)
    if pass; tag = '[PASS]'; else; tag = '[FAIL]'; end
    fprintf('    %s  %s\n', tag, msg);
end