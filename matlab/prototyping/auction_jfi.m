%% auction_jfi.m
% STEP 2: Auction decision + Jain Fairness Index tracking.
%
% Builds on Step 1 (auction_decide.m) by adding:
%   - Cumulative energy accounting per node (Wh)
%   - JFI computation after every auction cycle
%   - A short session simulation (N cycles) to watch JFI evolve
%
% JFI formula (Jain et al.):
%   JFI = (E1 + E2)^2 / (2 * (E1^2 + E2^2))
%   Range: 0.5 (worst, one node gets everything) to 1.0 (perfect fairness)
%   Target for AutaNet: JFI >= 0.85
%
% Run: >> auction_jfi
% -----------------------------------------------------------------------

function auction_jfi()

    fprintf('=== Step 2: Auction + Jain Fairness Index ===\n\n');

    % --- Constants (unchanged from Step 1) ---
    V_GRID   = 11.8;
    RH_CRIT  = 0.80;
    BID_H    = 140;
    BID_L    = 100;

    % --- Load parameters ---
    P_DRYER  = 144;     % W — power consumed by one dryer at 12V (V^2/R = 144/1)
    T_CYCLE  = 10;      % s — auction period

    % Energy delivered per cycle when a node is ON (Wh)
    E_PER_CYCLE = P_DRYER * T_CYCLE / 3600;   % = 0.4 Wh per cycle

    fprintf('  Load: %.0fW per dryer | Cycle: %ds | %.4f Wh per cycle\n\n', ...
        P_DRYER, T_CYCLE, E_PER_CYCLE);

    %% ---------------------------------------------------------------
    %  PART A: JFI formula verification on known values
    %% ---------------------------------------------------------------
    fprintf('--- Part A: JFI formula checks ---\n');
    jfi_checks = [
        100, 100,   1.000;   % equal → perfect fairness
        150,  50,   0.800;   % 3:1 ratio → JFI = (200^2)/(2*(22500+2500)) = 40000/50000
          0,   0,   1.000;   % session start → defined as 1.0
        200,   0,   0.500;   % all to one node → worst case
         80, 120,   0.980;   % mild imbalance
    ];

    fprintf('  %-10s  %-10s  %-12s  %-12s  %s\n', 'E1 (Wh)','E2 (Wh)','Expected','Computed','Result');
    fprintf('  %s\n', repmat('-',1,60));
    for k = 1:size(jfi_checks,1)
        e1  = jfi_checks(k,1);
        e2  = jfi_checks(k,2);
        exp = jfi_checks(k,3);
        jfi = compute_jfi(e1, e2);
        ok  = abs(jfi - exp) < 1e-4;
        fprintf('  %-10.0f  %-10.0f  %-12.4f  %-12.4f  [%s]\n', ...
            e1, e2, exp, jfi, pass_str(ok));
    end
    fprintf('\n');

    %% ---------------------------------------------------------------
    %  PART B: Session simulation — watch JFI evolve over time
    %  Three sub-cases showing how auction fairness plays out
    %% ---------------------------------------------------------------
    fprintf('--- Part B: Session simulation (3 scenarios, 360 cycles = 1 hour) ---\n\n');

    N_CYCLES = 360;   % 360 × 10s = 3600s = 1 hour

    scenarios = {
        'Alternating wins  (N1 odd, N2 even cycles) '
        'N1 wins every cycle                        '
        'Realistic: N1 critical first half          '
    };

    jfi_end_all = zeros(1,3);

    for s = 1:3
        E1 = 0;  E2 = 0;
        jfi_vec = zeros(1, N_CYCLES);

        for k = 1:N_CYCLES

            % Determine winner for this cycle based on scenario
            switch s
                case 1
                    % Alternating: odd cycles N1 wins, even cycles N2 wins
                    winner = 1 + mod(k,2);   % 1 when k odd, 2 when k even
                case 2
                    % N1 wins every cycle (maximum unfairness)
                    winner = 1;
                case 3
                    % First 180 cycles: N1 critical (wins solar)
                    % Last  180 cycles: N2 critical (wins solar)
                    if k <= 180
                        winner = 1;
                    else
                        winner = 2;
                    end
            end

            % Energy accounting:
            % Winner gets E_PER_CYCLE from solar.
            % Loser also gets E_PER_CYCLE from grid (both dryers stay on).
            % JFI tracks solar allocation only — that is what the auction controls.
            E1 = E1 + E_PER_CYCLE * (winner == 1);
            E2 = E2 + E_PER_CYCLE * (winner == 2);

            jfi_vec(k) = compute_jfi(E1, E2);
        end

        jfi_end_all(s) = jfi_vec(end);

        ok = jfi_vec(end) >= 0.85;
        fprintf('  Scenario %d — %s\n', s, scenarios{s});
        fprintf('    Final JFI: %.4f  |  Min JFI: %.4f  |  E1=%.1fWh  E2=%.1fWh  [%s]\n\n', ...
            jfi_vec(end), min(jfi_vec), E1, E2, pass_str(ok));
    end

    %% ---------------------------------------------------------------
    %  PART C: JFI recovery — how quickly fairness recovers after
    %          one node dominates for a while
    %% ---------------------------------------------------------------
    fprintf('--- Part C: JFI recovery after imbalance ---\n');
    fprintf('  N1 wins first 60 cycles (10 min), then alternating.\n\n');

    E1 = 0; E2 = 0;
    jfi_recover = zeros(1, N_CYCLES);
    crossover_cycle = NaN;

    for k = 1:N_CYCLES
        if k <= 60
            winner = 1;
        else
            winner = 1 + mod(k,2);
        end
        E1 = E1 + E_PER_CYCLE * (winner == 1);
        E2 = E2 + E_PER_CYCLE * (winner == 2);
        jfi_recover(k) = compute_jfi(E1, E2);

        % Record first cycle JFI crosses back above 0.85
        if isnan(crossover_cycle) && k > 60 && jfi_recover(k) >= 0.85
            crossover_cycle = k;
        end
    end

    fprintf('  JFI at end of imbalance phase (cycle 60) : %.4f\n', jfi_recover(60));
    if ~isnan(crossover_cycle)
        fprintf('  JFI recovers to ≥0.85 at cycle           : %d  (t = %ds)\n', ...
            crossover_cycle, crossover_cycle * T_CYCLE);
    else
        fprintf('  JFI did not recover to 0.85 within %d cycles.\n', N_CYCLES);
    end
    fprintf('  Final JFI (cycle %d)                      : %.4f\n\n', N_CYCLES, jfi_recover(end));

    %% ---------------------------------------------------------------
    %  SUMMARY
    %% ---------------------------------------------------------------
    fprintf('--- Summary ---\n');
    fprintf('  Alternating wins  → JFI = %.4f  (ideal balanced auction)\n', jfi_end_all(1));
    fprintf('  N1 wins always    → JFI = %.4f  (worst case, auction broken)\n', jfi_end_all(2));
    fprintf('  Realistic profile → JFI = %.4f  (expected in AutaNet operation)\n\n', jfi_end_all(3));
    fprintf('  Ready for Step 3: battery SOC model.\n\n');

end

%% =====================================================================
function jfi = compute_jfi(E1, E2)
%  Jain Fairness Index for two nodes.
%  Returns 1.0 at session start (both zero) by convention.

    if (E1 == 0) && (E2 == 0)
        jfi = 1.0;
        return;
    end
    denom = 2 * (E1^2 + E2^2);
    if denom < 1e-12
        jfi = 1.0;
        return;
    end
    jfi = (E1 + E2)^2 / denom;
    jfi = min(max(jfi, 0.0), 1.0);
end

function s = pass_str(b)
    if b; s = 'PASS'; else; s = 'FAIL'; end
end