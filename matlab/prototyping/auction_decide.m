%% auction_decide.m
% STEP 1: Core auction decision function.
%
% Given sensor readings and battery state, returns:
%   - who wins solar this cycle
%   - what each node bid
%   - whether solar is available at all
%
% No Simulink. No structs. No dependencies.
% Run this file directly: >> auction_decide
% -----------------------------------------------------------------------

function auction_decide()

    fprintf('=== Step 1: Auction Decision Logic ===\n\n');

    % --- System constants (from hardware spec) --------------------------
    V_GRID_SWITCH = 11.8;   % V  — battery threshold below which grid is forced
    RH_CRITICAL   = 0.80;   % fraction — AHT21 reading that triggers critical bid
    BID_HIGH      = 140;    % units/kWh — critical or override bid
    BID_LOW       = 100;    % units/kWh — standard bid

    % --- Five test cases (mirrors the five Simulink scenarios) ----------
    %   [ bat_V,  rh1,   rh2,  btn1, btn2,  expected_winner, expected_solar ]
    cases = [
        12.5,  0.60,  0.60,   0,    0,     1,   1;   % tie-break → Node 1
        12.5,  0.85,  0.60,   0,    0,     1,   1;   % N1 critical
        12.5,  0.60,  0.90,   0,    0,     2,   1;   % N2 critical
        11.5,  0.85,  0.60,   0,    0,     0,   0;   % bat low → grid forced
        12.5,  0.85,  0.60,   0,    1,     1,   1;   % N2 override + N1 critical → tie → N1
    ];

    labels = {
        'Tie-break (equal bids)        '
        'Node 1 critical (RH=0.85)     '
        'Node 2 critical (RH=0.90)     '
        'Battery low (V=11.5)          '
        'N2 override + N1 critical     '
    };

    fprintf('  %-33s  bid1  bid2  solar  winner  result\n', 'Scenario');
    fprintf('  %s\n', repmat('-', 1, 68));

    all_pass = true;

    for k = 1:size(cases, 1)

        % Unpack inputs
        bat_V = cases(k, 1);
        rh1   = cases(k, 2);
        rh2   = cases(k, 3);
        btn1  = cases(k, 4);
        btn2  = cases(k, 5);
        exp_w = cases(k, 6);
        exp_s = cases(k, 7);

        % --- Bid formulation ---
        % Button (manual override) takes priority over sensor reading
        if btn1 >= 0.5
            bid1 = BID_HIGH;
        elseif rh1 >= RH_CRITICAL
            bid1 = BID_HIGH;
        else
            bid1 = BID_LOW;
        end

        if btn2 >= 0.5
            bid2 = BID_HIGH;
        elseif rh2 >= RH_CRITICAL
            bid2 = BID_HIGH;
        else
            bid2 = BID_LOW;
        end

        % --- Solar availability ---
        solar = (bat_V >= V_GRID_SWITCH);   % true/false

        % --- Market clearing ---
        if solar
            if bid1 >= bid2
                winner = 1;   % Node 1 wins (also handles tie-break)
            else
                winner = 2;
            end
        else
            winner = 0;       % 0 = no solar winner, both fall back to grid
        end

        % --- Check against expected ---
        pass = (winner == exp_w) && (solar == logical(exp_s));
        all_pass = all_pass && pass;

        if pass; tag = 'PASS'; else; tag = 'FAIL'; end

        fprintf('  %-33s  %3d   %3d     %d      %d     [%s]\n', ...
            labels{k}, bid1, bid2, solar, winner, tag);
    end

    fprintf('  %s\n', repmat('-', 1, 68));
    if all_pass
        fprintf('  All 5 tests passed.\n\n');
        fprintf('  Ready for Step 2: add JFI fairness tracking.\n\n');
    else
        fprintf('  One or more tests FAILED — review logic above.\n\n');
    end

end