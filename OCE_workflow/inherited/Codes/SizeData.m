function [OCE_system] = SizeData (pathname,OCT_system,OCE_system)

filenames = dir(fullfile(pathname,'*.dat'));
fid = fopen(fullfile(pathname,filenames(1).name));
if strcmp(OCT_system.data_type,'uint16')
    tmp_raw_fringe = double(fread(fid,[OCT_system.spec_len,Inf],OCT_system.data_type ,0,'b')-32768);
else
    tmp_raw_fringe = double(fread(fid,[OCT_system.spec_len,Inf],OCT_system.data_type ,0,'b'));
end
OCE_system.NumLateralPos = round(length(filenames));
OCE_system.NumMrept = size(tmp_raw_fringe,2);
OCE_system.DepthSize =  size(tmp_raw_fringe,1)/2;

end