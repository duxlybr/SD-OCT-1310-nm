function [Cplx_Matrix4D, Cplx_Matrix_BgSubs3D] = ReadCplx_Volume_3D_New1 (pathname,OCT_system,OCE_system)

%tic
filenames = dir(fullfile(pathname,'*.dat'));
hann_rep_mat = double(repmat(hann(OCT_system.spec_len),1,OCE_system.NewTimeSize));
hann_rep_mat_bg = double(repmat(hann(OCT_system.spec_len),1,50));
Cplx_Matrix = complex(zeros(OCE_system.NumLateralPos,...
                            OCE_system.NewDepthSize,...
                            OCE_system.NewTimeSize));
Cplx_Matrix_BgSubs = Cplx_Matrix(:,:,1);

Cplx_Matrix4D = complex(zeros(OCE_system.Num3DX,...
                            OCE_system.Num3DY,...
                            OCE_system.NewDepthSize,...
                            OCE_system.NewTimeSize));                        
Cplx_Matrix_BgSubs3D = Cplx_Matrix4D(:,:,:,1);


for pos = 1:OCE_system.NumLateralPos
    
    fid = fopen(fullfile(pathname,filenames(pos).name));
    %fseek(fid,OCT_system.spec_len*OCE_system.Cut_Time_ini,'bof');
    
    if strcmp(OCT_system.data_type,'uint16')
        pos_raw_fringes = double(fread(fid,[OCT_system.spec_len,OCE_system.Cut_Time_end + 50]...
                                 ,OCT_system.data_type,0,'b')-32768);
        fclose(fid);
    else
        pos_raw_fringes = double(fread(fid,[OCT_system.spec_len,OCE_system.Cut_Time_end + 50]...
                                 ,OCT_system.data_type,0,'b'));
        fclose(fid);
    end
    
    pos_raw_fringes = pos_raw_fringes(:,:);
    linear_k_fringes = double(interp1(OCE_system.k_space,single(pos_raw_fringes)...
                              ,OCE_system.k_space_linear,'linear'));
                          
    %linear_k_fringes1 = (linear_k_fringes - DC_spectrum);   
    linear_k_fringes1 = (linear_k_fringes(:,OCE_system.Cut_Time_end+1:end) - median(linear_k_fringes(:,OCE_system.Cut_Time_end+1:end),2));  
    %linear_k_fringes = double(linear_k_fringes-smooth(mean(linear_k_fringes,2),0.05,'lowess')); 
    fft_0 = fft(hann_rep_mat.*linear_k_fringes(:,OCE_system.Cut_Time_ini:OCE_system.Cut_Time_end));
    fft_1 = fft(hann_rep_mat_bg.*linear_k_fringes1);
    Cplx_Matrix(pos,:,:) = fft_0(OCE_system.Cut_Depth_ini:OCE_system.Cut_Depth_end,:);
    Cplx_Matrix_BgSubs(pos,:) = mean(fft_1(OCE_system.Cut_Depth_ini:OCE_system.Cut_Depth_end,:),2);
    pos
    
end   

[m, n, o] = size(Cplx_Matrix);                   
Cplx_Matrix_Normal = Cplx_Matrix;  
Cplx_Matrix_Normal_BgSubs = Cplx_Matrix_BgSubs; 

Cplx_Matrix_Normal(1:(m-OCE_system.Jump_Lat_pos),:,:) = Cplx_Matrix(OCE_system.Jump_Lat_pos+1:m,:,:);
Cplx_Matrix_Normal_BgSubs(1:(m-OCE_system.Jump_Lat_pos),:) = Cplx_Matrix_BgSubs(OCE_system.Jump_Lat_pos+1:m,:); 

Cplx_Matrix_Normal((m-OCE_system.Jump_Lat_pos+1):m,:,:) = Cplx_Matrix(1:OCE_system.Jump_Lat_pos,:,:);
Cplx_Matrix_Normal_BgSubs((m-OCE_system.Jump_Lat_pos+1):m,:) = Cplx_Matrix_BgSubs(1:OCE_system.Jump_Lat_pos,:);

clear Cplx_Matrix
clear Cplx_Matrix_BgSubs
%toc
  
for posY = 1:OCE_system.Num3DY
    
    pos_ini = OCE_system.X3D_ini + OCE_system.Num3DX*(posY-1);
    pos_end = OCE_system.X3D_ini + OCE_system.Num3DX*(posY)-1; 

    Cplx_Matrix4D(:,posY,:,:) = squeeze(Cplx_Matrix_Normal(pos_ini:pos_end,:,:));
    Cplx_Matrix_BgSubs3D(:,posY,:) = squeeze(Cplx_Matrix_Normal_BgSubs(pos_ini:pos_end,:));
    posY
end
    
end