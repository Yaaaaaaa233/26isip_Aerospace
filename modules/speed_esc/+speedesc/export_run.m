function export_run(L,c,folder,animation)
if nargin<4, animation=false; end
if ~exist(folder,'dir'), mkdir(folder); end
m=speedesc.metrics(L,c); writetable(L,fullfile(folder,'run.csv'));
writetable(struct2table(m),fullfile(folder,'metrics.csv')); save(fullfile(folder,'run.mat'),'L','c','m');
fig=figure('Visible','off','Position',[60 60 1400 900]); cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
tiledlayout(2,2,'TileSpacing','compact','Padding','compact'); ax=gobjects(1,4);
for k=1:4, ax(k)=nexttile; end
speedesc.draw_frame(ax,L,c,height(L),true);
sgtitle(sprintf('V%d 平飞速度ESC | %s / %s | 代理模型，固定上下桨配比，非实测',c.version,c.curve,c.method),'Interpreter','none');
exportgraphics(fig,fullfile(folder,'overview.png'),'Resolution',140);
savefig(fig,fullfile(folder,'overview.fig'));
if animation
    for k=1:20
        index=1+round((height(L)-1)*(k-1)/19); speedesc.draw_frame(ax,L,c,index,true);
        file=fullfile(folder,'frame.png'); exportgraphics(fig,file,'Resolution',75);
        [a,map]=rgb2ind(imread(file),256);
        if k==1, imwrite(a,map,fullfile(folder,'online_speed.gif'),'gif','LoopCount',Inf,'DelayTime',.18);
        else, imwrite(a,map,fullfile(folder,'online_speed.gif'),'gif','WriteMode','append','DelayTime',.18); end
    end
end
end
