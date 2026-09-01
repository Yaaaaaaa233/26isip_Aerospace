function action = agent_action(agent,observation)
%AGENT_ACTION Deterministic actor evaluation without exploration noise.
actor=getActor(agent); action=getAction(actor,{observation});
if iscell(action), action=action{1}; end
action=double(action); action=action(1);
end
