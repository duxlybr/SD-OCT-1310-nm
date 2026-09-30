function [OCT_system,OCE_system] = K_Linearization (pathname,OCT_system,OCE_system)

spec_filename = dir(fullfile(pathname,'*.spectrum'));
spectrum = double(load(fullfile(pathname,spec_filename(1).name)));
OCT_system.spec_len = length(spectrum);

k_space = 2*pi./spectrum;
new_ks = double(k_space(1) -(0:OCT_system.spec_len-1)*...
        (k_space(1)-k_space(OCT_system.spec_len))/(OCT_system.spec_len-1));

OCE_system.k_space = k_space;
OCE_system.k_space_linear = new_ks;

end