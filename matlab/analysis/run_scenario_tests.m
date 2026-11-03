%% run_scenario_tests.m
% STEP 11: Run all five test scenarios through the closed-loop Simulink model.
%
% Scenarios (from system specification):
%   1. tie_break   — both nodes RH=0.60 (equal bids) → Node 1 wins by rule
%   2. critical_n1 — Node 1 RH=0.87, Node 2 RH=0.55 → Node 1 wins solar
%   3. grid_force  — battery at 7% SOC → voltage <11.8V → forced grid mode
%   4. override_n2 — Node 1 critical + Node 2 button pressed 5400–7200s
%   5. full_session— realistic 8-hour RH profiles (default)
%
% NOTE: Logged signals (jfi, source_mode, winner, etc.) are written to
%       the BASE WORKSPACE by Simulink To Workspace blocks — not into
%       the simOut struct. This script reads them via evalin('base',...).
%
% Run: >> init_microgrid
%      >> run_scenario_tests
% -----------------------------------------------------------------------

function run_scenario_tests()

fprintf('=== Step 11: Simulink Scenario Tests ===\n\n');

mdl = 'p2p_microgrid';
if ~bdIsLoaded(mdl)
    if exist([mdl '.slx'],'file'); load_system(mdl);
    else; error('[ERROR] %s.slx not found. Run assemble_p2p first.', mdl); end
end
set_param(mdl,'AlgebraicLoopMsg','none');

%% Define and run all scenarios
S  = define_scenarios();
nS = numel(S);
R(nS) = blank_result();

for k = 1:nS
    fprintf('[%d/%d] %s\n', k, nS, S(k).label);
    R(k) = run_one(S(k), mdl);
    print_result(R(k));
end

%% Summary table
print_table(R);

%% Comparison figure
plot_comparison(R, S);

fprintf('=== Scenario testing complete ===\n\n');
end

%% =====================================================================
function S = define_scenarios()

rh1_t = [0,    1800, 3600, 7200,  14400, 21600, 28800];
rh1_v = [0.40, 0.60, 0.85, 0.90,  0.75,  0.55,  0.40];
rh2_t = [0,    3600, 7200, 10800, 18000, 25200, 28800];
rh2_v = [0.40, 0.45, 0.82, 0.90,  0.70,  0.50,  0.38];

% 1 — Tie-break
S(1).label    = 'tie_break';
S(1).title    = 'Tie-break (equal bids)';
S(1).t_run    = 3600;
S(1).soc_init = 0.80;
S(1).rh1_t    = rh1_t; S(1).rh1_v = repmat(0.60, size(rh1_t));
S(1).rh2_t    = rh2_t; S(1).rh2_v = repmat(0.60, size(rh2_t));

% 2 — Node 1 critical
S(2).label    = 'critical_n1';
S(2).title    = 'Node 1 critical';
S(2).t_run    = 3600;
S(2).soc_init = 0.80;
S(2).rh1_t    = rh1_t; S(2).rh1_v = repmat(0.87, size(rh1_t));
S(2).rh2_t    = rh2_t; S(2).rh2_v = repmat(0.55, size(rh2_t));

% 3 — Grid forced
S(3).label    = 'grid_force';
S(3).title    = 'Grid forced (low SOC)';
S(3).t_run    = 3600;
S(3).soc_init = 0.07;
S(3).rh1_t    = rh1_t; S(3).rh1_v = rh1_v;
S(3).rh2_t    = rh2_t; S(3).rh2_v = rh2_v;

% 4 — Override Node 2
S(4).label    = 'override_n2';
S(4).title    = 'Node 2 manual override';
S(4).t_run    = 28800;
S(4).soc_init = 0.80;
S(4).rh1_t    = rh1_t; S(4).rh1_v = repmat(0.87, size(rh1_t));
S(4).rh2_t    = rh2_t; S(4).rh2_v = repmat(0.55, size(rh2_t));

% 5 — Full session
S(5).label    = 'full_session';
S(5).title    = 'Full 8-hour session';
S(5).t_run    = 28800;
S(5).soc_init = 0.80;
S(5).rh1_t    = rh1_t; S(5).rh1_v = rh1_v;
S(5).rh2_t    = rh2_t; S(5).rh2_v = rh2_v;
end

%% =====================================================================
function R = run_one(S, mdl)

R          = blank_result();
R.label    = S.label;
R.title    = S.title;
R.t_run    = S.t_run;

%% Reconfigure workspace
DRY = evalin('base','DRY');
BAT = evalin('base','BAT');

DRY.N1.rh_time   = S.rh1_t;
DRY.N1.rh_values = S.rh1_v;
DRY.N2.rh_time   = S.rh2_t;
DRY.N2.rh_values = S.rh2_v;
BAT.initial_soc   = S.soc_init;

assignin('base','DRY', DRY);
assignin('base','BAT', BAT);
assignin('base','N1_rh', [DRY.N1.rh_time', DRY.N1.rh_values']);
assignin('base','N2_rh', [DRY.N2.rh_time', DRY.N2.rh_values']);

% Battery integrator initial condition
E_init = S.soc_init * BAT.capacity_wh * 3600;
try
    set_param([mdl '/SS1_PowerPlant/E_bat_J'], ...
        'InitialCondition', num2str(E_init));
catch
end

% Set stop time
set_param(mdl,'StopTime', num2str(S.t_run));

%% Run simulation
fprintf('   Simulating %.0fh... ', S.t_run/3600);
tic;
try
    simOut    = sim(mdl,'ReturnWorkspaceOutputs','on');
    elapsed   = toc;
    fprintf('done (%.1fs)\n', elapsed);
    R.success = true;
    R.tout    = simOut.tout;
    R         = extract_signals(R);
    R         = compute_kpis(R);
    R.verify  = verify(R, S);
catch ME
    toc;
    fprintf('\n   [ERROR] %s\n', ME.message);
    R.success   = false;
    R.error_msg = ME.message;
    R.verify    = struct('pass',false,'msg',['Error: ' ME.message]);
end
end

%% =====================================================================
function R = extract_signals(R)
%% All signals are in BASE WORKSPACE via To Workspace blocks

vars = {'jfi','source_mode','bid_n1','bid_n2','winner'};
for k = 1:numel(vars)
    try
        R.(vars{k}) = evalin('base', vars{k});
    catch
        R.(vars{k}) = [];
    end
end

% Time vector — trim to match signal length
if ~isempty(R.source_mode)
    n = numel(R.source_mode);
    if numel(R.tout) >= n
        R.t_sig = R.tout(1:n);
    else
        R.t_sig = R.tout;
    end
else
    R.t_sig = R.tout;
end
end

%% =====================================================================
function R = compute_kpis(R)

if isempty(R.source_mode); return; end

src = R.source_mode;
win = R.winner;
b1  = R.bid_n1;
b2  = R.bid_n2;

R.solar_frac  = mean(src);
R.n1_wins     = sum(win == 1);
R.n2_wins     = sum(win == 2);
R.grid_cycles = sum(win == 0);
R.n_cycles    = numel(win);
R.n_contested = sum(b1 ~= b2);
R.n_tie       = sum(b1 == b2 & src == 1);

if ~isempty(R.jfi) && numel(R.jfi) > 1
    R.jfi_final = R.jfi(end);
    R.jfi_min   = min(R.jfi);
    R.jfi_mean  = mean(R.jfi);
end
end

%% =====================================================================
function v = verify(R, S)
v = struct('pass',false,'msg','');

if ~R.success || isempty(R.source_mode)
    v.msg = 'No data'; return;
end

switch S.label

    case 'tie_break'
        % All solar cycles must go to Node 1 (no N2 wins)
        ok    = (R.n2_wins == 0) && (R.n1_wins > 0);
        v.pass = ok;
        v.msg  = sprintf('N1=%d N2=%d Grid=%d — %s', ...
            R.n1_wins, R.n2_wins, R.grid_cycles, pf(ok));

    case 'critical_n1'
        % Node 1 should win > 90% of contested solar cycles
        solar_cyc = R.n1_wins + R.n2_wins;
        frac      = R.n1_wins / max(solar_cyc, 1);
        ok        = frac > 0.90;
        v.pass    = ok;
        v.msg     = sprintf('N1 won %.1f%% of solar cycles — %s', frac*100, pf(ok));

    case 'grid_force'
        % At least some grid cycles must exist (battery starts depleted)
        ok    = R.grid_cycles > 0;
        v.pass = ok;
        gfrac = R.grid_cycles / max(R.n_cycles, 1) * 100;
        v.msg  = sprintf('Grid cycles=%d (%.1f%%) — %s', ...
            R.grid_cycles, gfrac, pf(ok));

    case 'override_n2'
        % During override window 5400–7200s: check for any N1 wins
        % (N1 should win tie since both bid 140)
        if ~isempty(R.t_sig) && ~isempty(R.winner)
            win_window = R.winner(R.t_sig >= 5400 & R.t_sig <= 7200);
            n1_in      = sum(win_window == 1);
            ok         = n1_in > 0;
            v.pass     = ok;
            v.msg      = sprintf('Override window: N1 won %d cycles — %s', n1_in, pf(ok));
        else
            v.pass = false;
            v.msg  = 'Time vector unavailable for window check';
        end

    case 'full_session'
        solar_ok = R.solar_frac >= 0.65;
        v.pass   = solar_ok;
        v.msg    = sprintf('Solar=%.1f%% N1=%d N2=%d JFI=%.4f — %s', ...
            R.solar_frac*100, R.n1_wins, R.n2_wins, R.jfi_final, pf(solar_ok));
end
end

%% =====================================================================
function print_result(R)
if ~R.success
    fprintf('   [FAIL] %s\n\n', R.error_msg); return;
end
tag = pf(R.verify.pass);
fprintf('   [%s] %s\n', tag, R.verify.msg);
fprintf('   Solar=%.1f%%  N1=%d  N2=%d  Grid=%d  JFI=%.4f\n\n', ...
    R.solar_frac*100, R.n1_wins, R.n2_wins, R.grid_cycles, R.jfi_final);
end

%% =====================================================================
function print_table(R)
fprintf('\n');
fprintf('  ╔══════════════════════╦════════╦════════╦════════╦════════╦════════╗\n');
fprintf('  ║ Scenario             ║ Solar  ║ N1 win ║ N2 win ║ Grid   ║ Result ║\n');
fprintf('  ╠══════════════════════╬════════╬════════╬════════╬════════╬════════╣\n');
for k = 1:numel(R)
    Rk = R(k);
    if Rk.success
        fprintf('  ║ %-20s ║ %5.1f%% ║ %6d ║ %6d ║ %6d ║ %-6s ║\n', ...
            Rk.label, Rk.solar_frac*100, Rk.n1_wins, Rk.n2_wins, ...
            Rk.grid_cycles, pf(Rk.verify.pass));
    else
        fprintf('  ║ %-20s ║  ERROR ║      - ║      - ║      - ║ FAIL   ║\n', Rk.label);
    end
end
fprintf('  ╚══════════════════════╩════════╩════════╩════════╩════════╩════════╝\n\n');
end

%% =====================================================================
function plot_comparison(R, S)

COL.n1    = [0.18, 0.72, 0.44];
COL.n2    = [0.85, 0.28, 0.20];
COL.solar = [1.00, 0.65, 0.00];
COL.grid  = [0.20, 0.60, 1.00];
COL.jfi   = [0.50, 0.20, 0.80];
COL.bg    = [0.97, 0.97, 0.97];

nS  = numel(R);
fig = figure('Name','Fig5_Scenario_Tests','Color','w', ...
    'Position',[50 30 1400 700]);

for k = 1:nS
    Rk = R(k);

    % Use actual time or fall back to synthetic
    if ~isempty(Rk.t_sig) && ~isempty(Rk.source_mode)
        t_h  = Rk.t_sig / 3600;
        src  = Rk.source_mode;
        win  = Rk.winner;
        jf   = Rk.jfi;
    else
        % Fallback: show empty panels with label
        for row = 1:3
            subplot(3,nS,(row-1)*nS+k);
            text(0.5,0.5,'No data','HorizontalAlignment','center',...
                'Units','normalized','FontSize',9,'Color',[0.6 0.6 0.6]);
            if row==1; title(S(k).title,'FontSize',9,'Interpreter','none'); end
            set(gca,'Color',COL.bg);
        end
        continue;
    end

    %% Row 1: Source mode
    subplot(3,nS,k);
    area(t_h, src*100,'FaceColor',COL.solar,'FaceAlpha',0.75,'EdgeColor','none'); hold on;
    area(t_h,(1-src)*100,'FaceColor',COL.grid,'FaceAlpha',0.55,'EdgeColor','none');
    ylim([0 120]); yticks([0 100]); yticklabels({'Grid','Solar'});
    title(S(k).title,'FontSize',9,'Interpreter','none');
    if k==1; ylabel('Source','FontSize',8); end
    grid on; set(gca,'Color',COL.bg,'XTickLabel',{});
    % Pass/Fail badge
    if Rk.verify.pass; bc=COL.n1; tag='PASS';
    else;               bc=COL.n2; tag='FAIL'; end
    text(0.97,0.91,tag,'Units','normalized','HorizontalAlignment','right',...
        'FontWeight','bold','Color',bc,'FontSize',10);

    %% Row 2: Auction winner
    subplot(3,nS,nS+k);
    if ~isempty(win)
        w1 = double(win==1);
        w2 = double(win==2);
        bar(t_h,  w1,'FaceColor',COL.n1,'EdgeColor','none','BarWidth',1); hold on;
        bar(t_h, -w2,'FaceColor',COL.n2,'EdgeColor','none','BarWidth',1);
        yline(0,'k-','LineWidth',0.5);
        ylim([-1.4 1.4]); yticks([-1 0 1]); yticklabels({'N2','Tie','N1'});
    end
    if k==1; ylabel('Winner','FontSize',8); end
    grid on; set(gca,'Color',COL.bg,'XTickLabel',{});
    % Annotation
    if ~isempty(win)
        text(0.5,0.05,sprintf('N1:%d  N2:%d  G:%d', ...
            sum(win==1),sum(win==2),sum(win==0)), ...
            'Units','normalized','HorizontalAlignment','center','FontSize',7);
    end

    %% Row 3: JFI
    subplot(3,nS,2*nS+k);
    if ~isempty(jf) && numel(jf)>1
        plot(t_h(1:numel(jf)), jf,'Color',COL.jfi,'LineWidth',1.8); hold on;
        yline(0.85,'r--','LineWidth',1.2);
        ylim([0.4 1.05]);
    end
    xlabel('t (h)','FontSize',8);
    if k==1; ylabel('JFI','FontSize',8); end
    title(sprintf('JFI=%.3f  min=%.3f',Rk.jfi_final,Rk.jfi_min),'FontSize',8);
    grid on; set(gca,'Color',COL.bg);
end

sgtitle('AutaNet P2P Microgrid — Five Scenario Tests', ...
    'FontSize',13,'FontWeight','bold');

exportgraphics(fig,'Fig5_Scenario_Tests.png','Resolution',300);
savefig(fig,'Fig5_Scenario_Tests.fig');
fprintf('[Fig 5] Saved Fig5_Scenario_Tests.png\n\n');
end

%% =====================================================================
function R = blank_result()
R = struct(...
    'label','','title','','t_run',0,'success',false,'error_msg','',...
    'tout',[],'t_sig',[],...
    'jfi',[],'source_mode',[],'bid_n1',[],'bid_n2',[],'winner',[],...
    'solar_frac',0,'n1_wins',0,'n2_wins',0,'grid_cycles',0,'n_cycles',0,...
    'jfi_final',0,'jfi_min',0,'jfi_mean',0,'n_contested',0,'n_tie',0,...
    'verify',struct('pass',false,'msg',''));
end

function s = pf(b)
if b; s='PASS'; else; s='FAIL'; end
end