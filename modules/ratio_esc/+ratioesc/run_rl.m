function log = run_rl(c,policy)
%RUN_RL Smoke policies only. This function does not train a learning agent.
if nargin<2, policy='random'; end
[~,state]=ratioesc.rl_reset(c);
stream=RandStream('mt19937ar','Seed',c.seed+10000);
segments=cell(ceil(c.duration/c.rlPeriod),1); done=false; i=0;
while ~done
    if strcmp(policy,'fixed')
        action=c.fixedReference;
    else
        action=c.lower+(c.upper-c.lower)*rand(stream);
    end
    [~,~,done,state]=ratioesc.rl_step(action,state);
    i=i+1; segments{i}=state.lastSegment;
end
log=vertcat(segments{1:i});
end
