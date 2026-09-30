function [Bmode] = ReadBmodeFast (pathname,OCT_system,OCE_system)


%% Reading Data (just N repetitions to be fast)

N = 10; %Numer of repetitions (,ust be low)
filenames = dir(fullfile(pathname,'*.dat'));
hann_rep_mat = double(repmat(hann(OCT_system.spec_len),1,N));
Intensity_Matrix = double(zeros(OCE_system.DepthSize,...
                            OCE_system.NumLateralPos));
                                               
parfor pos = 1:OCE_system.NumLateralPos
    
    fid = fopen(fullfile(pathname,filenames(pos).name));
    
    if strcmp(OCT_system.data_type,'uint16')
        pos_raw_fringes = double(fread(fid,[OCT_system.spec_len,N]...
                                 ,OCT_system.data_type,0,'b')-32768);
        fclose(fid);
    else
        pos_raw_fringes = double(fread(fid,[OCT_system.spec_len,N]...
                                 ,OCT_system.data_type,0,'b'));
        fclose(fid);
    end
    
    linear_k_fringes = double(interp1(OCE_system.k_space,single(pos_raw_fringes),...
                                      OCE_system.k_space_linear,'linear'));
                                  
    linear_k_fringes = double(linear_k_fringes-median(linear_k_fringes,2));    
    %linear_k_fringes = double(linear_k_fringes-smooth(mean(linear_k_fringes,2),0.05,'lowess')); 
    fft_1 = fft(hann_rep_mat.*linear_k_fringes);
    
    Intensity_Matrix(:,pos) = mean(abs(fft_1(1:OCE_system.DepthSize,:)),2);

    
end    

% figure
% imagesc(20*log10(Intensity_Matrix));

%% Resizing image alonz z, and fixing jump

Bmode = Intensity_Matrix;

end