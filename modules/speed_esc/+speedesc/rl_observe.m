function [o,history] = rl_observe(speed,reference,meanJ,deltaJ,age,valid,history,c)
frame=[(speed-c.lower)/(c.upper-c.lower);(reference-c.lower)/(c.upper-c.lower);...
    meanJ;deltaJ;age/c.maxAge;valid];
frame(~isfinite(frame))=0;
if isempty(history), history=repmat(frame,1,4); else, history=[history(:,2:end),frame]; end
o=history(:);
end
