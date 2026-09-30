function outpict=tonemap(inpict,varargin)
%   TONEMAP(INPICT, {'PARAMETER', VALUE, ...})
%       This is a basic tone-mapping function similar to the standard
%       'tonemap' plugin for GIMP.  
%
%   INPICT is an image 
%
%   Additional parameters can be set via name-value pairs:
%       BLURSIZE should be a relatively large value, but varies depending on
%           the contrast detail.  Default is 100.
%       BLUROPACITY is the opacity of the blurred mask layer (default is 0.75)
%       BLENDOPACITY is the opacity of the final mixdown (default is 0.5)
%       MODE is the blend mode used for mixdown (default is 'overlay')
%       AMOUNT is used with MODE (see imblend()) (default is 2)
%
%   Regarding use of IMBLEND() parameters for mixdown:
%       GIMP uses 'softlight' simply because it doesn't have an overlay mode.
%       'overlay' and especially 'softlight' have very subtle effect here; 
%       GIMP handles this via iterated application of 'softlight'.  
%
%       As an alternative to iterative blends, I have developed a scalable 'overlay'
%       mode which allows approximation of any fractional iteration of 'overlay'.
%
%       Other contrast-enhancement modes can be used if desired.  Consider:
%           'contrast' with AMOUNT=0.3 to 0.7
%           'helow' with AMOUNT=0.5
% 
%   CLASS SUPPORT:
%   Supports 'uint8', 'uint16', 'int16', 'single', and 'double'

for k=1:2:length(varargin);
    switch lower(varargin{k})
        case 'blursize'
            blursz=varargin{k+1};
        case 'bluropacity'
            bluropacity=varargin{k+1};
        case 'blendopacity'
            overlayopacity=varargin{k+1};
        case 'mode'
            mode=varargin{k+1};
        case 'amount'
            amount=varargin{k+1};
        otherwise
            disp(sprintf('TONEMAP: unknown input parameter name %s',varargin{k}))
            return
    end
end

if ~exist('blursz','var')
    blursz=100;
end
if ~exist('bluropacity','var')
    bluropacity=0.75;
end
if ~exist('overlayopacity','var')
    overlayopacity=0.5;
end
if ~exist('mode','var')
    mode='overlay';
end
if ~exist('amount','var')
    amount=2;
end

[inpict inclass]=imcast(inpict,'double');

sigma=sqrt(-(blursz^2)/(2*log10(1/255)));
h=fspecial('gaussian',[1 1]*blursz,sigma);

% invert a desaturated copy
A=1-mono(inpict,'y');

% blur the inverted grey layer
% use padding to avoid vignetting
A=padarray(A,[1 1]*blursz,'replicate');
A=imfilter(A,h);
A=cropborder(A,blursz);

% recombine it with a fraction of the original image
merged=imblend(A,inpict,bluropacity,'normal');

% this allows generalized access to imblend
outpict=imblend(merged,inpict,overlayopacity,mode,amount);

outpict=imcast(outpict,inclass);

end






