function files = export_run(log,c,folder,animate)
%EXPORT_RUN Scientific plots, editable figure, causal log and replay GIF.
if nargin<4, animate=true; end
if ~exist(folder,'dir'), mkdir(folder); end
save(fullfile(folder,'run.mat'),'log','c'); writetable(log,fullfile(folder,'run.csv'));
m=ratioesc.metrics(log,c); writetable(struct2table(m),fullfile(folder,'metrics.csv'));
f=figure('Visible','off','Color','white','Position',[50 50 1280 830]);
cleanup=onCleanup(@()close(f)); %#ok<NASGU>
layout=tiledlayout(f,2,2,'Padding','compact','TileSpacing','compact');
ax=gobjects(1,4); for j=1:4, ax(j)=nexttile(layout); end
title(layout,'转速比ESC | 恒推力假设下的仿真代理模型，非实测',...
    'FontName','Microsoft YaHei','FontSize',14,'FontWeight','bold');
ratioesc.draw_frame(ax,log,c,height(log),true);
exportgraphics(f,fullfile(folder,'overview.png'),'Resolution',150);
savefig(f,fullfile(folder,'overview.fig'));
if animate
    frames=unique(round(linspace(1,height(log),32)));
    tmp=fullfile(folder,'animation_frame.png'); gif=fullfile(folder,'online_process.gif');
    for j=1:numel(frames)
        ratioesc.draw_frame(ax,log,c,frames(j),true);
        title(layout,sprintf('仿真代理，非实测 | %s | t = %.1f s',c.stage,log.time(frames(j))),...
            'FontName','Microsoft YaHei','FontSize',14);
        exportgraphics(f,tmp,'Resolution',90);
        [rgb,~]=imread(tmp); [indexed,map]=rgb2ind(rgb,128);
        if j==1
            imwrite(indexed,map,gif,'gif','LoopCount',Inf,'DelayTime',0.18);
        else
            imwrite(indexed,map,gif,'gif','WriteMode','append','DelayTime',0.18);
        end
    end
end
files=struct('folder',folder,'image',fullfile(folder,'overview.png'),...
    'data',fullfile(folder,'run.mat'),'csv',fullfile(folder,'run.csv'));
end
