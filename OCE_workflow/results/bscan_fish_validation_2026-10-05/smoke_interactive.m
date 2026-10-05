cd('C:/Users/proyecto.pi1081/Desktop/SD-OCT-1310-nm/OCE_workflow');startup;
files={'src/+oce/+interaction/tuneWaveSpeedMaps.m','workflows/run_elastography_interactive.m', ...
 'workflows/run_multi_excitation_elastography.m','workflows/run_acquisition_stepwise.m','workflows/run_raster_enface_stepwise.m'};
for j=1:numel(files)
 messages=checkcode(files{j},'-id');fprintf('CHECKCODE %s: %d diagnostics\n',files{j},numel(messages));
 for k=1:numel(messages),fprintf('line%d %s: %s\n',messages(k).line,messages(k).id,messages(k).message);end
end
x=(0:20)'*.1e-3;z=(0:10)'*.02e-3;t=(0:159)'/40000;[X,Z]=meshgrid(x,z);
motion=real(exp(-2i*pi*1000*X/2).*reshape(exp(2i*pi*1000*t),1,1,[]));
data=struct('motion',motion,'x_m',x,'row_m',z,'t_s',t,'valid_mask',true(size(X)),'plane_type',"bmode");
f=oce.interaction.tuneWaveSpeedMaps(data,struct('frequency_hz',1000,'method','phase_gradient', ...
 'window_x_mm',.6,'window_row_mm',0,'young_model','rayleigh'));
f.Visible='off';assert(~isempty(f.UserData.speed_result) && any(f.UserData.speed_result.valid_mask,'all'));
assert(all(abs(f.UserData.speed_result.speed_m_s(f.UserData.speed_result.valid_mask)-2)<.001));
loadButton=findall(f,'Text','Cargar / reconstruir plano');assert(string(loadButton.Enable)=="off");
close(f);disp('INTERACTIVE_MEMORY_PLANE_SMOKE_PASS');
