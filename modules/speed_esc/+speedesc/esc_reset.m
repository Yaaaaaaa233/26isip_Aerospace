function s = esc_reset(initial,p)
validateattributes(initial,{'double'},{'scalar','finite','>=',p.lower,'<=',p.upper});
s=struct('estimator',speedesc.estimator_reset(p),'reference',speedesc.reference_reset(initial,p),'frozen',false);
end
