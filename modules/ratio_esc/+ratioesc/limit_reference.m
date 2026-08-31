function value = limit_reference(request,previous,p)
request=min(max(request,p.lower),p.upper);
delta=p.rateLimit*p.Ts;
value=previous+min(max(request-previous,-delta),delta);
value=min(max(value,p.lower),p.upper);
end
