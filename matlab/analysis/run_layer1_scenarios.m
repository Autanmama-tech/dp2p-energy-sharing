%% run_layer1_scenarios.m
% Runs three Layer 1 operating scenarios and generates comparison figures.
%
% Scenario A — Solar only (grid unavailable)
%   SMPS AC input = 0V, grid quality = 0
%   System relies entirely on PV array and battery
%
% Scenario B — Grid only (no solar generation)
%   Irradiance profile = 0, PV power = 0
%   System runs entirely from 240V AC grid via SMPS
%
% Scenario C — Weak Nigerian grid (solar preferred despite grid present)
%   SMPS AC input reduced to 140V RMS (198V peak)
%   Grid quality drops below 0.5 threshold
%   Auction controller switches to solar despite grid connection
%
% Run: >> init_microgrid
%      >> run_layer1_scenarios
% -----------------------------------------------------------------------

function run_layer1_scenarios()

fprintf('=== Layer 1 Scenario Tests ===\n\n');

mdl = 'p2p_microgrid';
if ~bdIsLoaded(mdl)
    load_system(mdl);
end
set_param(mdl,'AlgebraicLoopMsg','none');
set_param(mdl,'StopTime','28800');

%% Store original SMPS amplitude
V_ac_original = '339.4112549695428';   % 240V RMS × sqrt(2)

%% ---------------------------------------------------------------
%  SCENARIO A — Solar only (grid unavailable)
%% ---------------------------------------------------------------
fprintf('[Scenario A] Solar only — zeroing grid supply...\n');

% Set SMPS AC amplitude to 0
try
    set_param('ss1_power_plant/SMPS_Grid/V_ac','Amplitude','0');
    save_system('ss1_power_plant');
    fprintf('  SMPS amplitude set to 0V\n');
catch ME
    fprintf('  [WARN] Could not set SMPS: %s\n', ME.message);
end

% Normal irradiance profile
init_microgrid;

fprintf('  Simulating...\n');
simA = sim(mdl,'ReturnWorkspaceOutputs','on');
fprintf('  Done.\n\n');

% Restore SMPS
set_param('ss1_power_plant/SMPS_Grid/V_ac','Amplitude',V_ac_original);
save_system('ss1_power_plant');

%% ---------------------------------------------------------------
%  SCENARIO B — Grid only (no solar)
%% ---------------------------------------------------------------
fprintf('[Scenario B] Grid only — zeroing irradiance...\n');

init_microgrid;

% Override irradiance with zeros
irr_profile_zero = [0, 0; 28800, 0];
assignin('base','irr_profile', irr_profile_zero);
fprintf('  Irradiance set to 0 W/m²\n');

fprintf('  Simulating...\n');
simB = sim(mdl,'ReturnWorkspaceOutputs','on');
fprintf('  Done.\n\n');

% Restore irradiance
init_microgrid;

%% ---------------------------------------------------------------
%  SCENARIO C — Weak Nigerian grid (solar preferred)
%% ---------------------------------------------------------------
fprintf('[Scenario C] Weak grid — reducing SMPS to 140V RMS...\n');

% 140V RMS × sqrt(2) = 197.99V peak
try
    set_param('ss1_power_plant/SMPS_Grid/V_ac','Amplitude','197.99');
    save_system('ss1_power_plant');
    fprintf('  SMPS amplitude set to 198V peak (140V RMS)\n');
catch ME
    fprintf('  [WARN] Could not set SMPS: %s\n', ME.message);
end

init_microgrid;

fprintf('  Simulating...\n');
simC = sim(mdl,'ReturnWorkspaceOutputs','on');
fprintf('  Done.\n\n');

% Restore SMPS
set_param('ss1_power_plant/SMPS_Grid/V_ac','Amplitude',V_ac_original);
save_system('ss1_power_plant');

%% ---------------------------------------------------------------
%  PRINT SUMMARY
%% ---------------------------------------------------------------
fprintf('=== Results Summary ===\n\n');
fprintf('  %-30s %-15s %-15s %-15s\n','Metric','Scenario A','Scenario B','Scenario C');
fprintf('  %s\n',repmat('-',1,78));

metrics = {
    'Solar fraction (%)',       mean(simA.source_mode)*100, mean(simB.source_mode)*100, mean(simC.source_mode)*100;
    'PV peak power (W)',        max(simA.pv_power),         max(simB.pv_power),         max(simC.pv_power);
    'Bus voltage min (V)',      min(simA.bus_voltage_log),  min(simB.bus_voltage_log),  min(simC.bus_voltage_log);
    'Bus voltage max (V)',      max(simA.bus_voltage_log),  max(simB.bus_voltage_log),  max(simC.bus_voltage_log);
    'Battery SOC min (%)',      min(simA.bat_soc)*100,      min(simB.bat_soc)*100,      min(simC.bat_soc)*100;
    'Battery SOC max (%)',      max(simA.bat_soc)*100,      max(simB.bat_soc)*100,      max(simC.bat_soc)*100;
    'JFI final',                simA.jfi(end),              simB.jfi(end),              simC.jfi(end);
    'N1 wins',                  sum(simA.winner==1),        sum(simB.winner==1),        sum(simC.winner==1);
    'N2 wins',                  sum(simA.winner==2),        sum(simB.winner==2),        sum(simC.winner==2);
};

for k = 1:size(metrics,1)
    fprintf('  %-30s %-15.2f %-15.2f %-15.2f\n', ...
        metrics{k,1}, metrics{k,2}, metrics{k,3}, metrics{k,4});
end
fprintf('\n');

%% ---------------------------------------------------------------
%  PLOT COMPARISON FIGURE
%% ---------------------------------------------------------------
fprintf('[Plotting] Generating Layer 1 scenario comparison...\n');

C.solar  = [1.00, 0.65, 0.00];
C.grid   = [0.20, 0.60, 1.00];
C.weak   = [0.85, 0.28, 0.20];
C.bat    = [0.18, 0.72, 0.44];
C.bg     = [0.97, 0.97, 0.97];

t_h  = simA.tout / 3600;
t_hB = simB.tout / 3600;
t_hC = simC.tout / 3600;

% Downsample continuous signals for plotting (every 10th point)
ds = 10;
tA = t_h(1:ds:end);
tB = t_hB(1:ds:end);
tC = t_hC(1:ds:end);

fig = figure('Name','Fig6_Layer1_Scenarios','Color','w',...
    'Position',[50 30 1100 750]);

%% Row 1: PV Power
subplot(3,3,1)
area(tA, simA.pv_power(1:ds:end)/1000,'FaceColor',C.solar,'FaceAlpha',0.8,'EdgeColor','none')
title('Scenario A — Solar Only','FontSize',10)
ylabel('PV Power (kW)'); ylim([0 1.6])
grid on; set(gca,'Color',C.bg,'XTickLabel',{})
text(0.5,0.85,'Grid: OFF','Units','normalized','HorizontalAlignment','center',...
    'FontSize',9,'Color',C.grid,'FontWeight','bold')

subplot(3,3,2)
area(tB, simB.pv_power(1:ds:end)/1000,'FaceColor',[0.7 0.7 0.7],'FaceAlpha',0.5,'EdgeColor','none')
title('Scenario B — Grid Only (No Solar)','FontSize',10)
ylabel('PV Power (kW)'); ylim([0 1.6])
grid on; set(gca,'Color',C.bg,'XTickLabel',{})
text(0.5,0.85,'PV: OFF','Units','normalized','HorizontalAlignment','center',...
    'FontSize',9,'Color',[0.5 0.5 0.5],'FontWeight','bold')

subplot(3,3,3)
area(tC, simC.pv_power(1:ds:end)/1000,'FaceColor',C.solar,'FaceAlpha',0.8,'EdgeColor','none')
title('Scenario C — Weak Grid (Solar Preferred)','FontSize',10)
ylabel('PV Power (kW)'); ylim([0 1.6])
grid on; set(gca,'Color',C.bg,'XTickLabel',{})
text(0.5,0.85,'Grid: WEAK','Units','normalized','HorizontalAlignment','center',...
    'FontSize',9,'Color',C.weak,'FontWeight','bold')

%% Row 2: Bus voltage
subplot(3,3,4)
plot(tA, simA.bus_voltage_log(1:ds:end),'Color',C.bat,'LineWidth',1.8)
hold on
yline(11.8,'b--','LineWidth',1.2,'Label','Grid switch 11.8V')
yline(11.6,'r:','LineWidth',1.0,'Label','LVD 11.6V')
ylabel('Bus Voltage (V)'); ylim([11.0 13.5])
xlabel('Time (hours)'); grid on; set(gca,'Color',C.bg,'XTickLabel',{})

subplot(3,3,5)
plot(tB, simB.bus_voltage_log(1:ds:end),'Color',C.grid,'LineWidth',1.8)
hold on
yline(12,'k--','LineWidth',1.0,'Label','12V nominal')
ylabel('Bus Voltage (V)'); ylim([11.0 13.5])
xlabel('Time (hours)'); grid on; set(gca,'Color',C.bg,'XTickLabel',{})

subplot(3,3,6)
plot(tC, simC.bus_voltage_log(1:ds:end),'Color',C.weak,'LineWidth',1.8)
hold on
yline(11.8,'b--','LineWidth',1.2,'Label','Grid switch 11.8V')
ylabel('Bus Voltage (V)'); ylim([11.0 13.5])
xlabel('Time (hours)'); grid on; set(gca,'Color',C.bg,'XTickLabel',{})

%% Row 3: Battery SOC
subplot(3,3,7)
plot(tA, simA.bat_soc(1:ds:end)*100,'Color',C.bat,'LineWidth',1.8)
hold on
yline(80,'k:','LineWidth',1.0,'Label','Initial 80%')
ylabel('Battery SOC (%)'); ylim([60 105])
xlabel('Time (hours)'); grid on; set(gca,'Color',C.bg)
text(0.5,0.08,sprintf('Min: %.1f%%  Max: %.1f%%',min(simA.bat_soc)*100,max(simA.bat_soc)*100),...
    'Units','normalized','HorizontalAlignment','center','FontSize',8)

subplot(3,3,8)
plot(tB, simB.bat_soc(1:ds:end)*100,'Color',C.grid,'LineWidth',1.8)
hold on
yline(80,'k:','LineWidth',1.0,'Label','Initial 80%')
ylabel('Battery SOC (%)'); ylim([60 105])
xlabel('Time (hours)'); grid on; set(gca,'Color',C.bg)
text(0.5,0.08,sprintf('Min: %.1f%%  Max: %.1f%%',min(simB.bat_soc)*100,max(simB.bat_soc)*100),...
    'Units','normalized','HorizontalAlignment','center','FontSize',8)

subplot(3,3,9)
plot(tC, simC.bat_soc(1:ds:end)*100,'Color',C.weak,'LineWidth',1.8)
hold on
yline(80,'k:','LineWidth',1.0,'Label','Initial 80%')
ylabel('Battery SOC (%)'); ylim([60 105])
xlabel('Time (hours)'); grid on; set(gca,'Color',C.bg)
text(0.5,0.08,sprintf('Min: %.1f%%  Max: %.1f%%',min(simC.bat_soc)*100,max(simC.bat_soc)*100),...
    'Units','normalized','HorizontalAlignment','center','FontSize',8)

sgtitle('Decentralised P2P Energy Trading System — Layer 1 Operating Scenarios',...
    'FontSize',13,'FontWeight','bold')

exportgraphics(fig,'Fig6_Layer1_Scenarios.png','Resolution',300)
savefig(fig,'Fig6_Layer1_Scenarios.fig')
fprintf('[OK]  Saved Fig6_Layer1_Scenarios.png\n\n')

fprintf('=== Layer 1 scenarios complete ===\n')
fprintf('  Move to results: movefile(''Fig6*.png'',''results'')\n\n')
end