function I = inertia_from_bom(tipMass_kg, arm_m, tubeMass_kg, tubeLen_m, nTubes, centralMass_kg)
%QUAD_SIM.INERTIA_FROM_BOM 平行轴定理对角惯量(建模调整方案 2026-10-11, 妥协登记 C4)。
% 结构假设(声明级): X 架 45° 布局(rotor_angle=pi/4.., 与 config 一致), 4 个臂端
% 集中质量(电机+桨+电机座), 机臂管按细杆近似, 中心堆(电池+飞控+线缆)盘分布
% (半径 0.12 m), 端件 z 偏置 0.05 m; 质心居中、惯性积 = 0。
% Izz     = 4*tip*L^2 + nTubes*(m*Lt^2/12) + central*rC^2
% Ixx=Iyy = 4*tip*(L^2/2 + z^2) + nTubes*(m*Lt^2/24) + central*z^2
% CAD/实测到位后替换为实测对角阵(升级入口见 docs/QUAD_SIM_MODEL_PLAN_20261011.md C4)。
narginchk(6,6);
zTip = 0.05; rC = 0.12;
Izz = 4*tipMass_kg*arm_m^2 + nTubes*(tubeMass_kg*tubeLen_m^2/12) + centralMass_kg*rC^2;
Ixx = 4*tipMass_kg*(arm_m^2/2 + zTip^2) + nTubes*(tubeMass_kg*tubeLen_m^2/24) + centralMass_kg*zTip^2;
assert(all(isfinite([Ixx Izz])) && Ixx > 0 && Izz > 0, ...
    'quad_sim:InertiaFromBom','Invalid BOM masses/lengths.');
I = diag([Ixx, Ixx, Izz]);
end
