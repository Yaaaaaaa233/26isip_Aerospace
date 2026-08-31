function s = esc_reset(p,initialRatio,initialMeasurement)
validateattributes(initialRatio,{'double'},{'scalar','finite','>=',p.lower,'<=',p.upper});
validateattributes(initialMeasurement,{'double'},{'scalar','finite'});
s=struct('center',min(max(initialRatio,p.lower+p.amplitude),p.upper-p.amplitude),...
    'bias',initialMeasurement,'gradient',0,'lastReference',initialRatio,...
    'sample',0,'frozen',false,'reinitialize',false,'warmup',0);
end
