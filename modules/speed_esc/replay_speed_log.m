function L = replay_speed_log(file,powerReferenceW,c)
%REPLAY_SPEED_LOG Real SI CSV -> timestamp-paired shadow speed suggestions.
% No command is transmitted. Logged future power is not caused by suggestions.
if nargin<3, c=speedesc.config(); end
validateattributes(powerReferenceW,{'double'},{'scalar','real','finite','positive'});
T=readtable(file); required={'time_s','velocity_time_s','vn_mps','ve_mps',...
    'battery_time_s','voltage_v','current_a'};
assert(all(ismember(required,T.Properties.VariableNames)),'speedesc:LogSchema','Missing required SI telemetry fields.');
assert(height(T)>=2 && all(isfinite(T.time_s)) && all(diff(T.time_s)>0),...
    'speedesc:LogTime','Times must be finite and strictly increasing.');
for name={'velocity_time_s','battery_time_s'}
    stamps=T.(name{1}); mask=isfinite(stamps);
    assert(all(stamps(mask)<=T.time_s(mask)+1e-9) && all(diff(stamps(mask))>=0),...
        'speedesc:LogTime','Signal stamps cannot be from the future or go backwards.');
end
p=speedesc.controller_config(c); s=[]; times=(T.time_s(1):c.Ts:T.time_s(end))';
rows=nan(numel(times),8); index=1; maximumPairGap=c.Ts+1e-9;
for k=1:numel(times)
    now=times(k);
    while index<height(T) && T.time_s(index+1)<=now+1e-9, index=index+1; end
    r=T(index,:); powerTime=r.battery_time_s; paired=NaN; pairGap=NaN;
    % Only previously received velocity samples may be used, never future interpolation.
    candidate=find(T.velocity_time_s(1:index)<=powerTime+1e-9,1,'last');
    if ~isempty(candidate)
        pairGap=powerTime-T.velocity_time_s(candidate);
        if pairGap<=maximumPairGap, paired=hypot(T.vn_mps(candidate),T.ve_mps(candidate)); end
    end
    J=r.voltage_v*r.current_a/powerReferenceW;
    valid=isfinite(J) && r.voltage_v>0 && r.current_a>=0 && isfinite(paired) && ...
        paired>=c.lower && paired<=c.upper && isfinite(powerTime) && now-powerTime<=c.maxAge;
    ref=NaN; center=NaN; frozen=true;
    if isempty(s) && valid, s=speedesc.esc_reset(paired,p); end
    if ~isempty(s)
        [ref,s,d]=speedesc.esc_step(s,J,paired,powerTime,now,valid,p); center=d.center; frozen=d.frozen;
    end
    rows(k,:)=[now,powerTime,paired,J,ref,center,frozen,pairGap];
end
L=array2table(rows,'VariableNames',{'time_s','power_time_s','paired_speed_mps','normalized_power',...
    'candidate_speed_NOT_APPLIED','reference_center','frozen','pair_gap_s'});
end
