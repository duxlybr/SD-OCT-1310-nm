function outpict=mergedown(inpict,varargin)
%   MERGEDOWN(INPICT, OPACITY, BLENDMODE, {...})
%       performs image blending on dim 4 of a 4-D imageset
%       performs a cascading blend from the maximal end of the array,
%       so modes such as 'normal' at 0.5 opacity will tend to taper, 
%       whereas other modes like 'screen' or 'multiply' will not
%       output is a single-frame image
%   
%   INPICT is a 4-D image set of any type supported by IMBLEND
%   Remaining arguments (OPACITY, BLENDMODE, etc) are any appropriate arguments
%   accepted by IMBLEND
%   
%   See also: imblend

nframes=size(inpict,4);

outpict=inpict(:,:,:,nframes);
for f=nframes-1:-1:1;
    outpict=imblend(inpict(:,:,:,f),outpict,varargin{:});
end

return