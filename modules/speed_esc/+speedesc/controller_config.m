function p = controller_config(c)
%CONTROLLER_CONFIG Whitelist excludes curves, optima, noise and scenarios.
keys={'Ts','lower','upper','amplitude','omega','gain','hpOmega','lpOmega',...
    'window','minimumSpeedStd','gradientLimit','centerRate','referenceRate','maxAge','fixedReference'};
p=struct(); for k=1:numel(keys), p.(keys{k})=c.(keys{k}); end
p.method=double(strcmp(c.method,'demod'))+1;
p.controlMode=double(strcmp(c.mode,'dither'))+2*double(strcmp(c.mode,'esc'));
end
