function outpict=colorpict(imsize,cvec)
%   COLORPICT(IMSIZE,CVEC)
%       returns a uint8 RGB image of size IMSIZE with a solid color fill
%       output class is 'uint8' 
%      
%   IMSIZE is the image size in pixels (2-D, MxN)
%   CVEC is a 3-element row vector specifying the image color

outpict=uint8(repmat(permute(cvec,[3 1 2]),[imsize(1) imsize(2) 1]));

return