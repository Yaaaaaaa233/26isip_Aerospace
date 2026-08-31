function [power,measured,s] = measure(s,optimum,noise,c)
power=ratioesc.power_map(s.ratio,optimum,c);
if isempty(s.delayBuffer)
    delayed=power;
else
    delayed=s.delayBuffer(1);
    s.delayBuffer=[s.delayBuffer(2:end);power];
end
measured=delayed+noise;
end
