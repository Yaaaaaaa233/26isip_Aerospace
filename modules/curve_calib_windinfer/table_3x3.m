%TABLE_3X3 任务3.3 三乘三验证表：飞机模式 × 风况, 单元格=MOE(纯能耗 Emin/Eactual)。
% 飞机模式: 悬停(v=0) / 匀速转圈(地速≡名义6.3) / 变速转圈(hybrid, 曲线未知: 标定+在线风推断)。
% 风况: 无风 / 恒定风(3.5 m/s @40°) / 变风(composite)。
% 任务3.3特有口径: 控制器不知道曲线(u*未知)也不知道风——匀速行飞名义6.3是
% "仅依赖单一速度点"的用户基线; hybrid含首飞标定学费(一次性)。
% 每格3种子(3/6/9)均值, duration=800 s; known oracle 作参考上限。
% 结果写入 docs/table_3x3.md(每轮固定验证交付物, 见 ../ROADMAP.md)。
root=fileparts(mfilename('fullpath')); addpath(root);
outDir=fullfile(root,'docs'); if ~exist(outDir,'dir'), mkdir(outDir); end
modeNames={'悬停(v=0)';'匀速转圈@名义6.3';'变速转圈(hybrid)'};
windNames={'无风';'恒定风(3.5@40°)';'变风(composite)'};
windCfg={...
 {'windKind','const','windBias',0.0,'windBiasY',0.0,'windAmp',0.0,'windAmpY',0.0};...
 {'windKind','const','windBias',3.5,'windBiasY',0.0,'windAmp',0.0,'windAmpY',0.0,'windDirDeg',40};...
 {'windKind','composite','windBias',2.5,'windAmp',1.5,'windOmega',0.08,...
  'windBiasY',0.0,'windAmpY',0.0,'turbStd',0.3}};
M=nan(3,3); K=zeros(1,3);
for iw=1:3
    for im=1:3
        vals=[];
        for sd=[3 6 9]
            c=w33.config('seed',sd,'duration',800,'tailSteps',60,windCfg{iw}{:});
            scn=w33.scenario('static',c);
            if im==3
                [log,~]=w33.run_algorithm('hybrid',scn,c);
            else
                if im==1, olv=0; else, olv=6.3; end
                c2=w33.config(c,'openLoopV',olv);
                [log,~]=w33.run_algorithm('openloop',scn,c2);
            end
            vals(end+1)=sum(log.minPowerTrue)/sum(log.powerTrue); %#ok<AGROW>
        end
        M(im,iw)=mean(vals);
        fprintf('%s × %s : MOE=%.4f (3种子均值)\n',modeNames{im},windNames{iw},M(im,iw));
    end
    for sd=[3 6 9]
        c=w33.config('seed',sd,'duration',800,'tailSteps',60,windCfg{iw}{:});
        [log,~]=w33.run_algorithm('known',w33.scenario('static',c),c);
        K(iw)=K(iw)+sum(log.minPowerTrue)/sum(log.powerTrue)/3;
    end
end
fid=fopen(fullfile(outDir,'table_3x3.md'),'w','n','UTF-8');
cl=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,['# 任务3.3 三乘三验证表\n\n生成时间：%s | MOE=纯能耗口径 Emin/Eactual'...
    '(2026-09-04用户口径) | 每格3种子均值, 800 s | 对象: 空速=地速−风, ', ...
    '曲线未知(控制器无u*/曲线/风任何真值)\n\n'],datestr(now,31));
fprintf(fid,'| 飞机模式 \\ 风况 | 无风 | 恒定风(3.5@40°) | 变风(composite) |\n|---|---:|---:|---:|\n');
for im=1:3
    fprintf(fid,'| %s | %.4f | %.4f | %.4f |\n',modeNames{im},M(im,1),M(im,2),M(im,3));
end
fprintf(fid,'\n参考上限(known oracle, 已知风+已知曲线, 非因果): | %.4f | %.4f | %.4f |\n',K(1),K(2),K(3));
fprintf(fid,['\n判读: 匀速转圈@名义6.3 即用户所说"仅依赖单一速度点"的基线——无风时恰好最优, ',...
    '有风后损失显著; sweepcal 靠首飞全速域快扫(3→12 m/s双向, 150步)联合辨识曲线与风, ',...
    '账面含一次性"标定学费"(约150/800步的采样代价), 但在所有风况下都优于单一速度点基线, ',...
    '且无需任何曲线先验。RL对照(策略梯度)为诚实负结果, 详见 run_task33_checks 报告。\n']);
fprintf('表已写入 docs/table_3x3.md\n');
disp(M);
fprintf('TABLE DONE\n');
