%% plot_final_figures.m
% Generates final paper-quality figures with updated results:
%   - Continuous bid function (ties: 2263 → 4)
%   - Grid quality aware source selection
%   - Nigerian grid context
%
% Run: >> plot_final_figures(ans)
% -----------------------------------------------------------------------

function plot_final_figures(simOut)

fprintf('=== Generating Final Paper Figures ===\n\n');

%% Extract signals from simulation output
jfi_sim     = simOut.jfi;
source_mode = simOut.source_mode;
bid_n1      = simOut.bid_n1;
bid_n2      = simOut.bid_n2;
winner      = simOut.winner;
t_sim       = simOut.tout;

% Match signal length to time vector
n = numel(jfi_sim);
t_h = (0:n-1)' * 10 / 3600;   % hours at 10s per sample

%% Colours
C.solar  = [1.00, 0.65, 0.00];
C.grid   = [0.20, 0.60, 1.00];
C.n1     = [0.18, 0.72, 0.44];
C.n2     = [0.85, 0.28, 0.20];
C.jfi    = [0.50, 0.20, 0.80];
C.bg     = [0.97, 0.97, 0.97];

%% Standalone session for physical JFI trajectory
fprintf('[INFO] Computing standalone JFI trajectories...\n');
[t_sa, jfi_g, jfi_c, jfi_a, rh1, rh2, src, b1_sa, b2_sa, win_sa, P_pv, V_bat] = ...
    run_standalone_continuous();
fprintf('[INFO] Done.\n\n');

%% ═══════════════════════════════════════════════════════
%%  FIG 1 — System Power Overview
%% ═══════════════════════════════════════════════════════
fprintf('[Fig 1] System overview...\n');
fig1 = figure('Name','Fig1_System_Overview','Color','w','Position',[50 50 900 580]);

subplot(3,1,1)
area(t_sa, P_pv/1000,'FaceColor',C.solar,'FaceAlpha',0.85,'EdgeColor','none')
ylabel('PV Power (kW)'); ylim([0 1.6])
title('(a) PV Array Output — 8-Hour Day Profile  (3 × 470 W panels)')
grid on; set(gca,'Color',C.bg,'XTickLabel',{})

subplot(3,1,2)
plot(t_sa, V_bat,'k-','LineWidth',1.8); hold on
yline(11.8,'b--','LineWidth',1.4,'Label','Grid switch  11.8 V')
yline(11.6,'r:', 'LineWidth',1.2,'Label','LVD  11.6 V')
yline(14.4,'g--','LineWidth',1.0,'Label','Bulk  14.4 V')
ylabel('V_{bat} (V)'); ylim([11.0 15.0])
title('(b) Battery Terminal Voltage  (12 V / 220 Ah SLA)')
grid on; set(gca,'Color',C.bg,'XTickLabel',{})

subplot(3,1,3)
area(t_sa, src*100,'FaceColor',C.solar,'FaceAlpha',0.75,'EdgeColor','none'); hold on
area(t_sa,(1-src)*100,'FaceColor',C.grid,'FaceAlpha',0.55,'EdgeColor','none')
ylabel('Source (%)'); ylim([0 120]); yticks([0 100])
yticklabels({'Grid','Solar'}); xlabel('Time (hours)')
title(sprintf('(c) Source Mode — Solar fraction = %.1f%%  (Nigerian grid quality aware)', mean(src)*100))
legend('Solar/battery','Grid SMPS','Location','northeast')
grid on; set(gca,'Color',C.bg)

sgtitle('Decentralised P2P Energy Trading System — System Power Overview (8-hour session)',...
    'FontSize',13,'FontWeight','bold')
save_fig(fig1,'Fig1_System_Overview')

%% ═══════════════════════════════════════════════════════
%%  FIG 2 — Auction Dynamics (continuous bids)
%% ═══════════════════════════════════════════════════════
fprintf('[Fig 2] Auction dynamics...\n');
fig2 = figure('Name','Fig2_Auction_Dynamics','Color','w','Position',[80 30 900 650]);

subplot(3,1,1)
plot(t_sa, b1_sa,'Color',C.n1,'LineWidth',1.8); hold on
plot(t_sa, b2_sa,'Color',C.n2,'LineWidth',1.8)
yline(200,'--','LineWidth',1.0,'Label','Max  200','Color',[0.4 0.4 0.4])
yline(140,'--','LineWidth',1.0,'Label','Critical  140','Color',[0.4 0.4 0.4])
yline(100,':','LineWidth',1.0,'Label','Min  100','Color',[0.4 0.4 0.4])
ylim([90 215]); ylabel('Bid (units/kWh)')
legend('Node 1','Node 2','Location','northeast')
title('(a) Continuous Auction Bid Prices per 10-second Cycle')
grid on; set(gca,'Color',C.bg,'XTickLabel',{})

subplot(3,1,2)
plot(t_sa, rh1*100,'Color',C.n1,'LineWidth',1.8); hold on
plot(t_sa, rh2*100,'Color',C.n2,'LineWidth',1.8)
yline(80,'k--','LineWidth',1.4,'Label','Critical  80% RH')
fill([t_sa; flipud(t_sa)],[80*ones(size(t_sa)); 100*ones(size(t_sa))],...
    [1 0.8 0.8],'FaceAlpha',0.2,'EdgeColor','none')
ylabel('RH (%)'); ylim([30 105])
legend('Node 1 RH','Node 2 RH','Location','northeast')
title('(b) Chamber Relative Humidity — AHT21 Sensor Models')
grid on; set(gca,'Color',C.bg,'XTickLabel',{})

subplot(3,1,3)
w1 = double(win_sa==1); w2 = double(win_sa==2);
bar(t_sa,  w1,'FaceColor',C.n1,'EdgeColor','none','BarWidth',1); hold on
bar(t_sa, -w2,'FaceColor',C.n2,'EdgeColor','none','BarWidth',1)
yline(0,'k-','LineWidth',0.8)
ylim([-1.4 1.4]); yticks([-1 0 1])
yticklabels({'N2 wins solar','Tie / Grid','N1 wins solar'})
ylabel('Winner'); xlabel('Time (hours)')
n_cont = sum(abs(b1_sa - b2_sa) > 0.01);
n_tie  = sum(abs(b1_sa - b2_sa) <= 0.01 & src==1);
title(sprintf('(c) Solar Auction Winner — N1: %d  N2: %d  Ties: %d  (Continuous bids)',...
    sum(w1), sum(w2), n_tie))
grid on; set(gca,'Color',C.bg)

sgtitle('Decentralised P2P Energy Trading System — Auction Protocol Dynamics (Continuous Bid Function)',...
    'FontSize',13,'FontWeight','bold')
save_fig(fig2,'Fig2_Auction_Dynamics')

%% ═══════════════════════════════════════════════════════
%%  FIG 3 — JFI Analysis
%% ═══════════════════════════════════════════════════════
fprintf('[Fig 3] JFI analysis...\n');
fig3 = figure('Name','Fig3_JFI_Analysis','Color','w','Position',[110 20 1000 560]);

subplot(2,1,1)
p1 = plot(t_sa, jfi_g,'Color',C.n2,'LineWidth',2.0); hold on
p2 = plot(t_sa, jfi_c,'Color',C.n1,'LineWidth',2.0)
p3 = plot(t_sa, jfi_a,'Color',C.grid,'LineWidth',1.8,'LineStyle','--')
yline(0.85,'k--','LineWidth',1.5,'Label','Target  JFI = 0.85')
yline(1.00,':','LineWidth',1.0,'Color',[0.7 0.7 0.7])
fill([t_sa; flipud(t_sa)],[jfi_g; flipud(jfi_c)],...
    [0.95 0.85 0.85],'FaceAlpha',0.25,'EdgeColor','none')
ylim([0.45 1.05]); xlabel('Time (hours)'); ylabel('JFI')
legend([p1 p2 p3],...
    sprintf('Global JFI  (continuous bids)         final = %.4f',jfi_g(end)),...
    sprintf('Contested JFI  (auction protocol only) final = %.4f',jfi_c(end)),...
    sprintf('Global JFI  (alternating tie-break)    final = %.4f',jfi_a(end)),...
    'Location','southeast')
title('(a) Jain Fairness Index — Continuous Bid Function vs Binary Bid Baseline')
grid on; set(gca,'Color',C.bg)

subplot(2,1,2)
rh_diff = (rh1 - rh2)*100;
area(t_sa, max(rh_diff,0),'FaceColor',C.n1,'FaceAlpha',0.6,'EdgeColor','none'); hold on
area(t_sa,-max(-rh_diff,0),'FaceColor',C.n2,'FaceAlpha',0.6,'EdgeColor','none')
yline(0,'k-','LineWidth',0.8)
ylabel('DeltaRH = RH1 - RH2 (%)'); xlabel('Time (hours)')
title(sprintf('(b) Humidity Differential — Contested: %.1f%%   Tie: %.1f%%   Grid: 0%%',...
    n_cont/numel(b1_sa)*100, n_tie/numel(b1_sa)*100))
legend('N1 higher bid','N2 higher bid','Location','northeast')
grid on; set(gca,'Color',C.bg)

sgtitle('Decentralised P2P Energy Trading System — Jain Fairness Index Analysis',...
    'FontSize',13,'FontWeight','bold')
save_fig(fig3,'Fig3_JFI_Analysis')

%% ═══════════════════════════════════════════════════════
%%  FIG 4 — KPI Summary
%% ═══════════════════════════════════════════════════════
fprintf('[Fig 4] KPI summary...\n');
fig4 = figure('Name','Fig4_KPI_Summary','Color','w','Position',[140 40 900 520]);

kpi_labels  = {'Solar fraction (%)','Contested JFI','Global JFI (continuous)','Alt. tie-break JFI'};
kpi_values  = [mean(src)*100,  jfi_c(end), jfi_g(end), jfi_a(end)];
kpi_targets = [65,             0.85,        0.85,        0.85];
kpi_maxes   = [100,            1.0,         1.0,         1.0];
kpi_fmts    = {'%.1f%%','%.4f','%.4f','%.4f'};

for k = 1:4
    subplot(2,2,k)
    val = kpi_values(k); tgt = kpi_targets(k);
    bc  = C.n1*double(val>=tgt) + C.n2*double(val<tgt);
    bar(1,val,0.5,'FaceColor',bc,'EdgeColor','none'); hold on
    yline(tgt,'k--','LineWidth',1.5,'Label',sprintf('Target %.2g',tgt))
    lbl = sprintf(kpi_fmts{k},val);
    text(1,val*0.5,lbl,'HorizontalAlignment','center',...
        'FontSize',13,'FontWeight','bold','Color','w')
    xlim([0.4 1.6]); ylim([0 kpi_maxes(k)*1.12])
    set(gca,'XTick',[],'Color',C.bg)
    title(kpi_labels{k},'FontSize',11)
    if val>=tgt
        ylabel('\color[rgb]{0.18,0.72,0.44}PASS','FontWeight','bold','FontSize',11)
    else
        ylabel('\color[rgb]{0.85,0.28,0.20}FAIL','FontWeight','bold','FontSize',11)
    end
    grid on
end

sgtitle('Decentralised P2P Energy Trading System — KPI Summary Dashboard',...
    'FontSize',13,'FontWeight','bold')
save_fig(fig4,'Fig4_KPI_Summary')

%% ═══════════════════════════════════════════════════════
%%  FIG 5 — Continuous Bid Function Shape
%% ═══════════════════════════════════════════════════════
fprintf('[Fig 5] Bid function shape...\n');
fig5 = figure('Name','Fig5_Bid_Function','Color','w','Position',[170 50 700 400]);

rh_range = 0:0.001:1;
bid_cont = zeros(size(rh_range));
bid_bin  = zeros(size(rh_range));
for k = 1:numel(rh_range)
    rh = rh_range(k);
    if rh < 0.80; bid_cont(k) = 100 + (rh/0.80)*40;
    else;          bid_cont(k) = 140 + ((rh-0.80)/0.20)*60; end
    bid_bin(k) = 100 + 40*double(rh>=0.80);
end

plot(rh_range*100, bid_cont,'Color',C.n1,'LineWidth',2.5); hold on
plot(rh_range*100, bid_bin, 'Color',C.n2,'LineWidth',1.8,'LineStyle','--')
xline(80,'k--','LineWidth',1.2,'Label','Critical  80% RH')
yline(140,':','LineWidth',1.0,'Label','Critical bid  140','Color',[0.5 0.5 0.5])
scatter([0 80 100],[100 140 200],80,C.n1,'filled')
text(2,103,'100','FontSize',10,'Color',C.n1)
text(81,143,'140','FontSize',10,'Color',C.n1)
text(95,197,'200','FontSize',10,'Color',C.n1)
xlabel('Relative Humidity (%)'); ylabel('Bid Price (units/kWh)')
ylim([90 215]); xlim([0 100])
legend('Continuous bid (proposed system)','Binary bid (baseline)','Location','northwest')
title({'Decentralised P2P Energy Trading System — Auction Bid Function Design', ...
       'Bid Function Comparison – Continuous vs Binary'}, ...
       'FontSize', 12, 'FontWeight', 'bold')
grid on; set(gca,'Color',C.bg)

save_fig(fig5,'Fig5_Bid_Function')

%% Summary
fprintf('\n=== All figures saved ===\n')
fprintf('  Fig1_System_Overview.png\n')
fprintf('  Fig2_Auction_Dynamics.png\n')
fprintf('  Fig3_JFI_Analysis.png\n')
fprintf('  Fig4_KPI_Summary.png\n')
fprintf('  Fig5_Bid_Function.png     ← NEW: shows continuous vs binary\n\n')
fprintf('Key results:\n')
fprintf('  Solar fraction    : %.1f%%\n', mean(src)*100)
fprintf('  Tie cycles        : %d  (was 2263 with binary bids)\n', n_tie)
fprintf('  Contested JFI     : %.4f\n', jfi_c(end))
fprintf('  Global JFI        : %.4f\n', jfi_g(end))
fprintf('  Alt. tie-break JFI: %.4f\n', jfi_a(end))
fprintf('  N1 wins / N2 wins : %d / %d\n', sum(w1), sum(w2))
end

%% =====================================================================
function [t_h,jfi_g,jfi_c,jfi_a,rh1,rh2,src,bid1,bid2,win,P_pv,V_bat] = ...
    run_standalone_continuous()

V_GRID=11.8; RH_CRIT=0.80;
BID_MIN=100; BID_CRIT=140; BID_MAX=200;
P_DRY=144; T_CYC=10; T_SIM=28800;
BAT_CAP=2640; PV_PEAK=1410; PV_EFF=0.85; I_MAX=150;
SOC_WH=[0,264,1320,1980,2640]; SOC_V=[11.6,11.8,12.0,12.4,12.7];
irr_t=[0,1800,3600,7200,10800,14400,18000,21600,25200,28800];
irr_v=[100,250,500,700,900,950,850,650,350,100];
rh1_t=[0,1800,3600,7200,14400,21600,28800];
rh1_v=[.40,.60,.85,.90,.75,.55,.40];
rh2_t=[0,3600,7200,10800,18000,25200,28800];
rh2_v=[.40,.45,.82,.90,.70,.50,.38];

N=T_SIM/T_CYC; t_s=(0:T_CYC:T_SIM-T_CYC)';
rh1=max(min(interp1(rh1_t,rh1_v,t_s,'pchip'),1),0);
rh2=max(min(interp1(rh2_t,rh2_v,t_s,'pchip'),1),0);
irr=max(interp1(irr_t,irr_v,t_s,'pchip'),0);
ppv=PV_PEAK*PV_EFF*(irr/1000);

E_bat=0.80*BAT_CAP;
E1g=0;E2g=0;E1c=0;E2c=0;E1a=0;E2a=0;
jfi_g=zeros(N,1);jfi_c=zeros(N,1);jfi_a=zeros(N,1);
src=zeros(N,1);bid1=zeros(N,1);bid2=zeros(N,1);win=zeros(N,1);
P_pv=zeros(N,1);V_bat=zeros(N,1);

for k=1:N
    Vb=min(max(interp1(SOC_WH,SOC_V,E_bat,'linear','extrap'),10.5),14.6);
    V_bat(k)=Vb; P_pv(k)=ppv(k);
    solar=(Vb>=V_GRID); src(k)=double(solar);

    r1=rh1(k); r2=rh2(k);
    if r1<RH_CRIT; b1=BID_MIN+(r1/RH_CRIT)*(BID_CRIT-BID_MIN);
    else;           b1=BID_CRIT+((r1-RH_CRIT)/(1-RH_CRIT))*(BID_MAX-BID_CRIT); end
    if r2<RH_CRIT; b2=BID_MIN+(r2/RH_CRIT)*(BID_CRIT-BID_MIN);
    else;           b2=BID_CRIT+((r2-RH_CRIT)/(1-RH_CRIT))*(BID_MAX-BID_CRIT); end
    bid1(k)=b1; bid2(k)=b2;

    if solar; w=1+double(b2>b1); else; w=0; end
    win(k)=w;
    ep=P_DRY*T_CYC/3600;
    if solar; E1g=E1g+ep*(w==1); E2g=E2g+ep*(w==2); end
    if solar&&abs(b1-b2)>0.01; E1c=E1c+ep*(w==1); E2c=E2c+ep*(w==2); end
    if solar
        if b1>b2; wa=1; elseif b2>b1; wa=2; else; wa=1+mod(k,2); end
        E1a=E1a+ep*(wa==1); E2a=E2a+ep*(wa==2);
    end
    jfi_g(k)=cjfi(E1g,E2g); jfi_c(k)=cjfi(E1c,E2c); jfi_a(k)=cjfi(E1a,E2a);
    Pc=min(ppv(k),I_MAX*Vb); Pl=2*P_DRY*double(solar);
    E_bat=min(max(E_bat+(Pc-Pl)*T_CYC/3600,0),BAT_CAP);
end
t_h=t_s/3600;
end

function v=cjfi(e1,e2)
    if e1==0&&e2==0;v=1;return;end
    d=2*(e1^2+e2^2); if d<1e-12;v=1;return;end
    v=min(max((e1+e2)^2/d,0),1);
end

function save_fig(fig,name)
    exportgraphics(fig,[name '.png'],'Resolution',300)
    savefig(fig,[name '.fig'])
    fprintf('       Saved %s\n',name)
end