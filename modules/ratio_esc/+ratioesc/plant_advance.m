function s = plant_advance(s,reference,c)
decay=exp(-c.Ts/c.tau);
s.ratio=decay*s.ratio+(1-decay)*reference;
s.previousReference=reference;
end
