function s = reference_reset(initial,p)
s=struct('center',min(max(initial,p.lower+p.amplitude),p.upper-p.amplitude),'last',initial);
end
