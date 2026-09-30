function outpict=picdynamics(inpict,G,linetime,rangemode,mode)
%   PICDYNAMICS(INPICT, {G}, {RANGEMODE}, {MODE})
%       performs LTI system response simulation on the rows of INPICT
%       used with imblend() to effect analog tape and crt drive defect emulation
%
%   INPICT is a single RGB image
%   G is the LTI system to use for simulation.  
%       by default, a generic system is selected with frequency scaled to the
%       image width.  Any other ZPK or TF can be used in place of this default.
%       if a single number is specified for G, it is treated as a frequency and
%       used in the default ZPK system.
%   LINETIME specifies the time represented by the scanning of one row
%       default is 60
%   RANGEMODE specifies how the output of the simulation should be handled
%       'squeeze' scales the output to fit in standard data range (default)
%       'clip' clips the output instead of scaling
%   MODE specifies what channels should be operated on (default 'rgb') 
%       'rgb' (process each channel independently) 
%       'h' (processes H in HSV and then converts back to RGB)
%       'v' (process V in HSV and convert back to RGB)
%       'y' (process Y and then convert back to RGB)
%       'v only' (output is greyscale triple of processed V)
%       'y only' (output is greyscale triple of processed Y)
%       single-channel modes reduce execution time by about 60%
%
%   EXAMPLE:
%   dpict=picdynamics(inpict,5,60,'squeeze');
%   out=imblend(dpict,inpict,1,'scale add',1.5);
%
%   CLASS SUPPORT:
%       Accepts 'double','single','uint8','uint16','int16', and 'logical'

if nargin<5
    mode='rgb';
end
if nargin<4
    rangemode='squeeze';
end
if nargin<3
    linetime=60;
end
if nargin<2
    f=size(inpict,2)/100;
    Z = [-1];
    P = [-1-f*i -1+f*i -2]; 
    K = 100;
    G = zpk(Z,P,K);
end

if isnumeric(G)
    f=G;
    Z = [-1];
    P = [-1-f*i -1+f*i -2]; 
    K = 100;
    G = zpk(Z,P,K);
end

% this script and the defaults were originally selected based on
% a uint8 data range.  that's why everything is scaled to 255 even
% though it's all in floating point

%padwidth=10;
[satpic inclass]=imcast(inpict,'double');
%satpic=padarray(satpic,[1 1]*padwidth,0,'both');
s=size(satpic);
t=0:s(1)*linetime/(s(1)*s(2)-1):s(1)*linetime;
G=ss(G);
satpic=reshape(permute(satpic,[2 1 3]),1,s(1)*s(2),3);

outpict=zeros(size(satpic));

%do a LTI system response for each line
switch lower(mode)
	case 'rgb'
		for c=1:1:size(inpict,3)
			u=satpic(1,:,c)'*255;
			satpic(1,:,c)=lsim(G,u,t)'/255;
		end

		% scale everything back to data range [0 1]
		if strcmpi(rangemode,'squeeze')
			for c=1:1:size(inpict,3)
				[picmin picmax]=imrange(satpic(:,:,c));
				outpict(:,:,c)=1/(picmax-picmin)*(satpic(:,:,c)-picmin);
			end
		elseif strcmpi(rangemode,'clip')
			outpict=max(min(satpic,1),0);
		end

	case {'luma', 'y'}
		ypppic=rgb2ypp(satpic);
		u=ypppic(1,:,1)'*255;
		ypppic(1,:,1)=lsim(G,u,t)'/255;

		% scale everything back to data range [0 1]
		if strcmpi(rangemode,'squeeze')
			[picmin picmax]=imrange(ypppic(:,:,1));
			ypppic(:,:,1)=1/(picmax-picmin)*(ypppic(:,:,1)-picmin);
		elseif strcmpi(rangemode,'clip')
			ypppic(:,:,1)=max(min(ypppic(:,:,1),1),0);
		end
    
		outpict=ypp2rgb(ypppic);
    
	case {'v','value'}
		hsvpic=rgb2hsv(satpic);
		u=hsvpic(1,:,3)'*255;
		hsvpic(1,:,3)=lsim(G,u,t)'/255;

		% scale everything back to data range [0 1]
		if strcmpi(rangemode,'squeeze')
			[picmin picmax]=imrange(hsvpic(:,:,3));
			hsvpic(:,:,3)=1/(picmax-picmin)*(hsvpic(:,:,3)-picmin);
		elseif strcmpi(rangemode,'clip')
			hsvpic(:,:,3)=max(min(hsvpic(:,:,3),1),0);
		end

		outpict=hsv2rgb(hsvpic);
    
	case {'hue','h'}
		hsvpic=rgb2hsv(satpic);
		imrange(hsvpic(:,:,1))
		sum(sum(isnan(hsvpic(:,:,1))))
		u=hsvpic(1,:,1)'*255;
		hsvpic(1,:,1)=lsim(G,u,t)'/255;

		% scale everything back to data range [0 1]
		if strcmpi(rangemode,'squeeze')
			[picmin picmax]=imrange(hsvpic(:,:,1));
			hsvpic(:,:,1)=1/(picmax-picmin)*(hsvpic(:,:,1)-picmin);
		elseif strcmpi(rangemode,'clip')
			hsvpic(:,:,1)=max(min(hsvpic(:,:,1),1),0);
		end

		outpict=hsv2rgb(hsvpic);
    
	case {'y only','luma only'}
		ypppic=rgb2ypp(satpic);
		u=ypppic(1,:,1)'*255;
		ypppic(1,:,1)=lsim(G,u,t)'/255;

		% scale everything back to data range [0 1]
		if strcmpi(rangemode,'squeeze')
			[picmin picmax]=imrange(ypppic(:,:,1));
			ypppic(:,:,1)=1/(picmax-picmin)*(ypppic(:,:,1)-picmin);
		elseif strcmpi(rangemode,'clip')
			ypppic(:,:,1)=max(min(ypppic(:,:,1),1),0);
		end

		outpict=ypp2rgb(ypppic);

	case {'v only','value only'}
		hsvpic=rgb2hsv(satpic);
		u=hsvpic(1,:,3)'*255;
		hsvpic(1,:,3)=lsim(G,u,t)'/255;

		% scale everything back to data range [0 1]
		if strcmpi(rangemode,'squeeze')
			[picmin picmax]=imrange(hsvpic(:,:,3));
			hsvpic(:,:,3)=1/(picmax-picmin)*(hsvpic(:,:,3)-picmin);
		elseif strcmpi(rangemode,'clip')
			hsvpic(:,:,3)=max(min(hsvpic(:,:,3),1),0);
		end

		outpict=hsv2rgb(hsvpic);
		
	otherwise 
		error('PICDYNAMICS: unknown mode')
		
end

class(outpict)
imrange(outpict(:,:,1))
imrange(outpict(:,:,2))
imrange(outpict(:,:,3))

outpict=permute(reshape(outpict,s(2),s(1),3),[2 1 3]);
%outpict=cropborder(outpict,padwidth);
outpict=max(min(outpict,1),0);
outpict=imcast(outpict,inclass);

end

function out=rgb2ypp(in)
	A=[0.299,0.587,0.114;-0.1687367,-0.331264,0.5;0.5,-0.418688,-0.081312];
	A=permute(A,[1 3 2]);
	out=zeros(size(in));
	out(:,:,1)=sum(bsxfun(@times,in,A(1,:,:)),3);
	out(:,:,2)=sum(bsxfun(@times,in,A(2,:,:)),3);
	out(:,:,3)=sum(bsxfun(@times,in,A(3,:,:)),3);
end

function out=ypp2rgb(in)
	A=[1,0,1.402; 1,-0.3441,-0.7141; 1,1.772,0];
	A=permute(A,[1 3 2]);
	out=zeros(size(in));
	out(:,:,1)=sum(bsxfun(@times,in,A(1,:,:)),3);
	out(:,:,2)=sum(bsxfun(@times,in,A(2,:,:)),3);
	out(:,:,3)=sum(bsxfun(@times,in,A(3,:,:)),3);
end










