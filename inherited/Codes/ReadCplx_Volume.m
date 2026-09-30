function [Cplx_Matrix_Normal, Cplx_Matrix_Normal_BgSubs] = ReadCplx_Volume (pathname,OCT_system,OCE_system)

%tic
N = 10;
filenames = dir(fullfile(pathname,'*.dat'));
hann_rep_mat = double(repmat(hann(OCT_system.spec_len),1,OCE_system.NewTimeSize));
hann_rep_mat_bg = double(repmat(hann(OCT_system.spec_len),1,N));
Cplx_Matrix = complex(zeros(OCE_system.NumLateralPos,...
                            OCE_system.NewDepthSize,...
                            OCE_system.NewTimeSize));
Cplx_Matrix_BgSubs = Cplx_Matrix(:,:,1:N);

% Fringes_DC = zeros(OCT_system.spec_len,OCE_system.NumLateralPos);
% parfor pos = 1:OCE_system.NumLateralPos
%     
%     fid = fopen(fullfile(pathname,filenames(pos).name));
%     fseek(fid,OCT_system.spec_len*OCE_system.Cut_Time_ini,'bof');
%     pos_raw_fringes = double(fread(fid,[OCT_system.spec_len,10]...
%                              ,OCT_system.data_type,0,'b')-32768);
%     fclose(fid);
%     
%     linear_k_fringes = double(interp1(OCE_system.k_space,single(pos_raw_fringes)...
%                               ,OCE_system.k_space_linear,'linear'));
%                           
%     Fringes_DC(:,pos) = mean(linear_k_fringes,2); 
% end  
% DC_spectrum = median(Fringes_DC,2);
                      
for pos = 1:OCE_system.NumLateralPos
    
    fid = fopen(fullfile(pathname,filenames(pos).name));
    %fseek(fid,OCT_system.spec_len*OCE_system.Cut_Time_ini,'bof');
    
    if strcmp(OCT_system.data_type,'uint16')
        pos_raw_fringes = double(fread(fid,[OCT_system.spec_len,OCE_system.Cut_Time_end]...
                                 ,OCT_system.data_type,0,'b')-32768);
        fclose(fid);
    else
        pos_raw_fringes = double(fread(fid,[OCT_system.spec_len,OCE_system.Cut_Time_end]...
                                 ,OCT_system.data_type,0,'b'));
        fclose(fid);
    end
    
    
    %pos_raw_fringes = pos_raw_fringes(:,:);
    linear_k_fringes = double(interp1(OCE_system.k_space,single(pos_raw_fringes)...
                              ,OCE_system.k_space_linear,'linear'));
                          
    %linear_k_fringes1 = (linear_k_fringes - DC_spectrum);   
    linear_k_fringes1 = double(linear_k_fringes(:,1:N) - median(linear_k_fringes(:,1:N),2));  
    %linear_k_fringes = double(linear_k_fringes-smooth(mean(linear_k_fringes,2),0.05,'lowess')); 
    linear_k_fringes = double(linear_k_fringes); 
    
    %linear_k_fringes = double(linear_k_fringes-median(linear_k_fringes,2)); 
    
    fft_0 = fft(hann_rep_mat.*linear_k_fringes(:,OCE_system.Cut_Time_ini:OCE_system.Cut_Time_end));
    fft_1 = fft(hann_rep_mat_bg.*linear_k_fringes1);
    Cplx_Matrix(pos,:,:) = fft_0(OCE_system.Cut_Depth_ini:OCE_system.Cut_Depth_end,:);
    Cplx_Matrix_BgSubs(pos,:,:) = fft_1(OCE_system.Cut_Depth_ini:OCE_system.Cut_Depth_end,:);
    %pos
    
end   

[m, n, o] = size(Cplx_Matrix);                   
Cplx_Matrix_Normal = Cplx_Matrix;  
Cplx_Matrix_Normal_BgSubs = Cplx_Matrix_BgSubs; 

Cplx_Matrix_Normal(1:(m-OCE_system.Jump_Lat_pos),:,:) = Cplx_Matrix(OCE_system.Jump_Lat_pos+1:m,:,:);
Cplx_Matrix_Normal_BgSubs(1:(m-OCE_system.Jump_Lat_pos),:,:) = Cplx_Matrix_BgSubs(OCE_system.Jump_Lat_pos+1:m,:,:); 

Cplx_Matrix_Normal((m-OCE_system.Jump_Lat_pos+1):m,:,:) = Cplx_Matrix(1:OCE_system.Jump_Lat_pos,:,:);
Cplx_Matrix_Normal_BgSubs((m-OCE_system.Jump_Lat_pos+1):m,:,:) = Cplx_Matrix_BgSubs(1:OCE_system.Jump_Lat_pos,:,:);
%toc

end