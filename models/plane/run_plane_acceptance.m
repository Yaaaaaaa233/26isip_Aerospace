function result=run_plane_acceptance()
%RUN_PLANE_ACCEPTANCE Machine-readable Plane P0-P4 acceptance entry.
result=test_plane_p0p4();assert(result.pass,'plane:Acceptance','Plane acceptance failed.');
end
