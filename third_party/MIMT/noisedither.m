function out=noisedither(img,ntype)
%   NOISEDITHER(INPICT,{TYPE})
%       Apply simple noise threshold dither to an I/RGB image
%
%   INPICT is a 2-D intensity image
%       if fed an RGB image, its luma channel will be extracted
%
%   TYPE is the noise type (default 'blue')
%       'white' for noise with a flat power spectrum
%       'blue' for noise with a power density roughly proportional to f
%
%   Output class is logical
%
%   See also: dither, zfdither, orddither, arborddither, linedither

if ~exist('ntype','var')
	ntype='blue';
end

if size(img,3)==3
	img=mono(img,'y');
end

img=imcast(img,'double');
s=size(img);

switch lower(ntype)
	case 'white'
		mask=rand(s(1:2));
	case 'blue'
		mask=rand(s(1:2));
		sigma=2;
		maskdiff=mask-imgaussfilt(mask,sigma);
		[mn mx]=imrange(maskdiff);
		maskdiff=(maskdiff-mn)/(mx-mn);
		mask=adapthisteq(maskdiff);
	otherwise
		error('NOISEDITHER: unknown noise type')
end

out=mask<=img;

end
