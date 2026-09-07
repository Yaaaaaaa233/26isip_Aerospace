function f = fwd_level(V, c)
%FWD_LEVEL 前飞功率水平因子(Hwang 代理三次式, config 锚点: 1 / 0.913@6.3 / 1.297@20)。
f = polyval(c.fwdCoef, V);
end
