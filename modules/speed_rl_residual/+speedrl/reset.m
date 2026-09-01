function [observation,s] = reset(c,adapter,baseline)
%RESET Initialize one fixed-duration residual-control episode.
[adapterState,sample]=adapter.reset(c.seed,c); speedrl.validate_sample(sample);
reference=c.initialSpeed; lastDelta=0;
meanPower=sample.power_w; if ~sample.power_valid, meanPower=c.powerScale; end
ctx=speedrl.context(sample,reference,lastDelta,meanPower,0,c);
[base,baseInfo]=baseline.reference(ctx); ctx.baseSpeed=base;
[observation,history]=speedrl.observe(ctx,[],c);
s=struct('config',c,'adapter',adapter,'baseline',baseline,'adapterState',adapterState,...
    'sample',sample,'reference',reference,'lastDelta',lastDelta,'previousMean',meanPower,...
    'history',history,'steps',0,'lastBaseline',base,'lastBaselineInfo',baseInfo,'lastInfo',struct());
end
