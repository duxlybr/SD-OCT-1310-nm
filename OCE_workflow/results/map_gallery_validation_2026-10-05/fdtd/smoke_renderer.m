function smoke_renderer()
%SMOKE_RENDERER Analytic-only harness check, excluded from the FDTD gallery.
    here=fileparts(mfilename('fullpath')); directory=fullfile(here,'renderer_smoke');
    if ~isfolder(directory), mkdir(directory); end
    f=1000; rho=1000; nu=.495; E=12000;
    beta=(1-2*nu)/(2*(1-nu));
    r=sqrt(fzero(@(s)s^3-8*s^2+(24-16*beta)*s-16*(1-beta),[0 1]));
    c=r*sqrt(E/(2*rho*(1+nu)));
    x=(-20:50)*100e-6; y=(-25:25)*100e-6; t=(0:79)*50e-6;
    [X,Y]=meshgrid(x,y);
    data=struct('motion',cos(-2*pi*f/c*X+reshape(2*pi*f*t,1,1,[])), ...
        'x_m',x,'row_m',y,'t_s',t,'valid_mask',true(size(X)),'plane_type',"enface");
    cases={struct('label',"renderer_smoke_analytic_only",'model',"rayleigh", ...
        'f_hz',f,'rho',rho,'nu',nu,'thickness_m',0,'lambda_bg_m',c/f, ...
        'source_center_m',[-.0055 0],'source_width_m',.0006, ...
        'truth_young_pa',E*ones(size(X)),'inclusion_mask',false(size(X)), ...
        'data',data)};
    caseFile=fullfile(directory,'analytic_only_smoke_cases.mat'); save(caseFile,'cases');
    evaluate_fdtd_gallery(caseFile,fullfile(directory,'private_preview'));
end
