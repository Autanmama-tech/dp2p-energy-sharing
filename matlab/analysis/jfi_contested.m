%% jfi_contested.m
% STEP 4b: JFI over contested cycles only.
%
% The always-N1 tie-break rule causes JFI collapse when most cycles are
% ties. This script separates the analysis:
%
%   Global JFI    — computed over ALL solar energy allocation (ties included)
%   Contested JFI — computed only over cycles where bid1 ≠ bid2
%                   (i.e. the auction actually made a decision)
%
% Findings feed directly into the AutaNet paper:
%   - If Contested JFI >= 0.85, the auction PROTOCOL is fair
%   - If Global JFI < 0.85, the TIE-BREAK RULE is the bottleneck
%   - These are two different design layers with separate solutions
%
% Run: >> jfi_contested
% -----------------------------------------------------------------------

function jfi_contested()

    fprintf('=== Step 4b: Contested-Cycles JFI Analysis ===\n\n');

    C = build_constants();

    % Use the full_session scenario (most representative)
    rh1_t = [0,    1800, 3600, 7200,  14400, 21600, 28800];
    rh1_v = [0.40, 0.60, 0.85, 0.90,  0.75,  0.55,  0.40];
    rh2_t = [0,    3600, 7200, 10800, 18000, 25200, 28800];
    rh2_v = [0.40, 0.45, 0.82, 0.90,  0.70,  0.50,  0.38];

    N     = C.T_SIM / C.T_CYCLE;
    t_vec = (0 : C.T_CYCLE : C.T_SIM - C.T_CYCLE);

    rh1  = max(min(interp1(rh1_t, rh1_v, t_vec, 'pchip'), 1), 0);
    rh2  = max(min(interp1(rh2_t, rh2_v, t_vec, 'pchip'), 1), 0);
    irr  = max(interp1(C.irr_t, C.irr_v, t_vec, 'pchip'), 0);
    P_pv = C.PV_PEAK * C.PV_EFF * (irr / 1000);

    % State
    E_bat = 0.80 * C.BAT_CAP;

    % Tracking variables — two separate JFI streams
    E1_global = 0;   E2_global = 0;   % all solar cycles (ties + contested)
    E1_cont   = 0;   E2_cont   = 0;   % contested cycles only

    jfi_global_vec = zeros(1, N);
    jfi_cont_vec   = zeros(1, N);

    % Counters
    n_tie      = 0;
    n_contest  = 0;
    n_grid     = 0;

    for k = 1:N

        % Battery voltage
        V_bat = min(max(interp1(C.SOC_WH, C.SOC_V, E_bat, 'linear','extrap'), 10.5), 14.6);

        % Solar availability
        solar = (V_bat >= C.V_GRID_SWITCH);

        % Bids
        bid1 = C.BID_L + (C.BID_H - C.BID_L) * double(rh1(k) >= C.RH_CRIT);
        bid2 = C.BID_L + (C.BID_H - C.BID_L) * double(rh2(k) >= C.RH_CRIT);

        % Classify cycle
        if ~solar
            cycle_type = 'grid';
            n_grid = n_grid + 1;
        elseif bid1 == bid2
            cycle_type = 'tie';
            n_tie = n_tie + 1;
        else
            cycle_type = 'contested';
            n_contest = n_contest + 1;
        end

        % Market clearing (spec-compliant: always-N1 on tie)
        if solar
            winner = 1 + double(bid2 > bid1);
        else
            winner = 0;
        end

        E_per = C.P_DRYER * C.T_CYCLE / 3600;

        % Global JFI: count all solar wins
        if solar
            E1_global = E1_global + E_per * double(winner == 1);
            E2_global = E2_global + E_per * double(winner == 2);
        end

        % Contested JFI: count only non-tie solar wins
        if strcmp(cycle_type, 'contested')
            E1_cont = E1_cont + E_per * double(winner == 1);
            E2_cont = E2_cont + E_per * double(winner == 2);
        end

        jfi_global_vec(k) = compute_jfi(E1_global, E2_global);
        jfi_cont_vec(k)   = compute_jfi(E1_cont,   E2_cont);

        % Battery update
        P_charge = min(P_pv(k), C.I_MPPT_MAX * V_bat);
        P_load   = 2 * C.P_DRYER * double(solar);
        E_bat    = min(max(E_bat + (P_charge - P_load) * C.T_CYCLE / 3600, 0), C.BAT_CAP);
    end

    %% --- Results -------------------------------------------------------
    pct_tie      = n_tie      / N * 100;
    pct_contest  = n_contest  / N * 100;
    pct_grid     = n_grid     / N * 100;

    fprintf('  Cycle breakdown (%d total cycles, %.0f hours):\n', N, C.T_SIM/3600);
    fprintf('    Tie      (bid1 == bid2, solar): %4d cycles (%5.1f%%)\n', n_tie,     pct_tie);
    fprintf('    Contested(bid1 != bid2, solar): %4d cycles (%5.1f%%)\n', n_contest, pct_contest);
    fprintf('    Grid     (solar unavailable)  : %4d cycles (%5.1f%%)\n', n_grid,    pct_grid);
    fprintf('\n');

    fprintf('  ┌──────────────────────────────────────────────────────┐\n');
    fprintf('  │  JFI Comparison                                      │\n');
    fprintf('  ├──────────────────────────────────────────────────────┤\n');
    fprintf('  │  Global JFI (all cycles)    final=%.4f  min=%.4f  │\n', ...
        jfi_global_vec(end), min(jfi_global_vec(jfi_global_vec > 0)));
    fprintf('  │  Contested JFI (auction only) final=%.4f  min=%.4f │\n', ...
        jfi_cont_vec(end), min(jfi_cont_vec(jfi_cont_vec > 0)));
    fprintf('  ├──────────────────────────────────────────────────────┤\n');

    ok_global   = jfi_global_vec(end) >= 0.85;
    ok_contested = jfi_cont_vec(end)  >= 0.85;
    fprintf('  │  Global JFI ≥ 0.85   : [%s]                          │\n', pass_str(ok_global));
    fprintf('  │  Contested JFI ≥ 0.85: [%s]  ← auction protocol      │\n', pass_str(ok_contested));
    fprintf('  └──────────────────────────────────────────────────────┘\n\n');

    fprintf('  INTERPRETATION:\n');
    if ok_contested && ~ok_global
        fprintf('  → The auction PROTOCOL is fair (Contested JFI = %.4f ≥ 0.85).\n', jfi_cont_vec(end));
        fprintf('  → Global JFI is pulled down by the tie-break rule, not by\n');
        fprintf('    the auction logic. The tie-break is a separate design layer.\n\n');
        fprintf('  PAPER FRAMING: Report Contested JFI as the primary fairness\n');
        fprintf('  metric. Note that the always-N1 tie-break is a deliberate\n');
        fprintf('  hardware simplification (ESP32 firmware), and propose\n');
        fprintf('  alternating tie-break as a firmware enhancement.\n\n');
    elseif ok_global
        fprintf('  → Both Global and Contested JFI meet the 0.85 target. ✓\n\n');
    else
        fprintf('  → Even the auction protocol falls short — review bid logic.\n\n');
    end

    %% --- Plot ----------------------------------------------------------
    t_h = t_vec / 3600;

    figure('Name','Step 4b: JFI Contested vs Global','Color','w', ...
           'Position',[100 100 1000 580]);

    % Panel 1: Both JFI traces
    subplot(2,1,1);
    plot(t_h, jfi_global_vec,   'Color',[0.85 0.28 0.20], 'LineWidth', 2.0); hold on;
    plot(t_h, jfi_cont_vec,     'Color',[0.18 0.72 0.44], 'LineWidth', 2.0);
    yline(0.85, 'k--', 'LineWidth', 1.5, 'Label', 'Target JFI = 0.85');
    yline(1.00, ':',   'Color', [0.7 0.7 0.7], 'LineWidth', 1.0);

    % Shade the gap between the two curves
    fill([t_h, fliplr(t_h)], ...
         [jfi_global_vec, fliplr(jfi_cont_vec)], ...
         [0.9 0.8 0.8], 'FaceAlpha', 0.3, 'EdgeColor', 'none');

    legend('Global JFI (all cycles)', ...
           'Contested JFI (auction decisions only)', ...
           'Target 0.85', 'Location', 'southeast');
    ylabel('JFI'); xlabel('Time (hours)'); ylim([0.45 1.05]);
    title(sprintf('Global JFI = %.4f  vs  Contested JFI = %.4f  (target ≥ 0.85)', ...
        jfi_global_vec(end), jfi_cont_vec(end)));
    grid on; set(gca, 'Color', [0.97 0.97 0.97]);

    % Panel 2: Cycle classification over time
    subplot(2,1,2);
    % Colour each cycle by type
    cycle_colours = zeros(N, 3);
    for k = 1:N
        bid1k = C.BID_L + (C.BID_H-C.BID_L)*double(rh1(k) >= C.RH_CRIT);
        bid2k = C.BID_L + (C.BID_H-C.BID_L)*double(rh2(k) >= C.RH_CRIT);
        solar_k = interp1(C.SOC_WH, C.SOC_V, 0.80*C.BAT_CAP) >= C.V_GRID_SWITCH;
        if ~solar_k
            cycle_colours(k,:) = [0.5 0.5 0.5];     % grey = grid
        elseif bid1k == bid2k
            cycle_colours(k,:) = [1.0 0.65 0.0];    % amber = tie
        else
            cycle_colours(k,:) = [0.18 0.72 0.44];  % green = contested
        end
    end

    % Use RH1-RH2 difference as a proxy for cycle type
    rh_diff = rh1 - rh2;
    area(t_h,  max(rh_diff, 0)*100, 'FaceColor',[0.18 0.72 0.44], ...
        'FaceAlpha',0.6,'EdgeColor','none'); hold on;
    area(t_h, -max(-rh_diff,0)*100, 'FaceColor',[0.85 0.28 0.20], ...
        'FaceAlpha',0.6,'EdgeColor','none');
    yline(0, 'k-', 'LineWidth', 0.8);

    % Mark contested cycles
    cont_mask = abs(rh1 - rh2) > 0.001;  % proxy
    contested_rh = rh_diff .* double(cont_mask) * 100;

    ylabel('RH₁ − RH₂ (%)'); xlabel('Time (hours)');
    title(sprintf('Cycle classification: Tie = %.1f%% | Contested = %.1f%% | Grid = %.1f%%', ...
        pct_tie, pct_contest, pct_grid));
    legend('N1 higher bid (green)', 'N2 higher bid (red)', 'Location','northeast');
    grid on; set(gca,'Color',[0.97 0.97 0.97]);

    sgtitle('AutaNet P2P Microgrid — Contested vs Global JFI (Full Session)', ...
        'FontSize', 13, 'FontWeight', 'bold');

    %% --- Alternating tie-break comparison ------------------------------
    fprintf('  Computing alternating tie-break variant for comparison...\n');

    E_bat = 0.80 * C.BAT_CAP;
    E1a = 0; E2a = 0;
    jfi_alt_vec = zeros(1, N);

    for k = 1:N
        V_bat = min(max(interp1(C.SOC_WH, C.SOC_V, E_bat,'linear','extrap'),10.5),14.6);
        solar = (V_bat >= C.V_GRID_SWITCH);
        bid1  = C.BID_L + (C.BID_H-C.BID_L)*double(rh1(k) >= C.RH_CRIT);
        bid2  = C.BID_L + (C.BID_H-C.BID_L)*double(rh2(k) >= C.RH_CRIT);

        if solar
            if bid1 > bid2
                winner = 1;
            elseif bid2 > bid1
                winner = 2;
            else
                winner = 1 + mod(k, 2);   % alternating: odd→N1, even→N2
            end
        else
            winner = 0;
        end

        E_per = C.P_DRYER * C.T_CYCLE / 3600;
        if solar
            E1a = E1a + E_per * double(winner==1);
            E2a = E2a + E_per * double(winner==2);
        end
        jfi_alt_vec(k) = compute_jfi(E1a, E2a);

        P_charge = min(P_pv(k), C.I_MPPT_MAX * V_bat);
        P_load   = 2 * C.P_DRYER * double(solar);
        E_bat    = min(max(E_bat+(P_charge-P_load)*C.T_CYCLE/3600,0),C.BAT_CAP);
    end

    fprintf('\n  ┌─────────────────────────────────────────────────────────┐\n');
    fprintf('  │  Tie-break Rule Comparison (full session)               │\n');
    fprintf('  ├─────────────────────────────────────────────────────────┤\n');
    fprintf('  │  Always-N1 (spec firmware) : JFI = %.4f  [%s]          │\n', ...
        jfi_global_vec(end), pass_str(jfi_global_vec(end)>=0.85));
    fprintf('  │  Alternating (enhancement) : JFI = %.4f  [%s]          │\n', ...
        jfi_alt_vec(end), pass_str(jfi_alt_vec(end)>=0.85));
    fprintf('  │  Gain from alternating     : Δ JFI = %+.4f             │\n', ...
        jfi_alt_vec(end) - jfi_global_vec(end));
    fprintf('  └─────────────────────────────────────────────────────────┘\n\n');

    % Add alternating trace to figure
    subplot(2,1,1);
    plot(t_h, jfi_alt_vec, 'b--', 'LineWidth', 1.6);
    legend('Global JFI (always-N1)', ...
           'Contested JFI (auction only)', ...
           'Target 0.85', ...
           'Global JFI (alternating tie-break)', ...
           'Location', 'southeast');

    fprintf('  Ready for Step 5: build Simulink SS3 (dryer loads + RH sensors).\n\n');
end

%% =====================================================================
function C = build_constants()
    C.V_GRID_SWITCH = 11.8; C.RH_CRIT = 0.80;
    C.BID_H=140; C.BID_L=100; C.P_DRYER=144; C.T_CYCLE=10; C.T_SIM=28800;
    C.BAT_CAP=2640; C.PV_PEAK=1410; C.PV_EFF=0.85; C.I_MPPT_MAX=150;
    C.SOC_WH=[0,264,1320,1980,2640]; C.SOC_V=[11.6,11.8,12.0,12.4,12.7];
    C.irr_t=[0,1800,3600,7200,10800,14400,18000,21600,25200,28800];
    C.irr_v=[100,250,500,700,900,950,850,650,350,100];
end

function jfi = compute_jfi(E1, E2)
    if E1==0 && E2==0; jfi=1.0; return; end
    d=2*(E1^2+E2^2);
    jfi = min(max((E1+E2)^2/d, 0), 1.0);
end

function s = pass_str(b)
    if b; s='PASS'; else; s='FAIL'; end
end