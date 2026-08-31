function p = controller_config(c)
%CONTROLLER_CONFIG Whitelist: no plant map or optimizer truth may cross here.
keys={'Ts','lower','upper','rateLimit','amplitude','frequency','hpOmega','lpOmega','gain'};
p=struct();
for k=1:numel(keys), p.(keys{k})=c.(keys{k}); end
p.adapt=strcmp(c.stage,'esc');
end
