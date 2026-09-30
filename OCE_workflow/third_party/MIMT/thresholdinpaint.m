function rempict=thresholdinpaint(bg,mode,mask,fold,method)
%   THRESHOLDINPAINT(INPICT, MODE, MASK, {FOLD}, {METHOD})
%       use PDE inpainting to estimate deleted pixel values 
%
%   INPICT is a 3-D RGB image
%   MASK is a 2-D logical pixel mask
%   MODE specifies where image elements should be deleted
%       and re-estimated ('rgb', 'r', 'g', 'b', 'h', 's', 'v', 'y')
%
%   when FOLD=0, estimates outside uint8 range are truncated
%   when FOLD=1, estimates outside uint8 range are folded
%
%   see 'help inpaint_nans' for info on setting METHOD
%
%   CLASS SUPPORT:
%   Output class is inherited from INPICT
%   Accepts 'double','single','uint8','uint16','int16', and 'logical'
%
%   This file makes use of John D'Errico's INPAINT_NANS()
%   http://www.mathworks.com/matlabcentral/fileexchange/4551-inpaint-nans

if nargin == 3
    fold=0; method=0;
elseif nargin == 4
    method=0;
end

mask=logical(mask);
[rempict inclass]=imcast(bg,'double');

% this uses replacepixels() to actually match pixels by color triplet
switch lower(mode)
    case 'rgb'
        rempict=replacepixels([NaN NaN NaN],rempict,mask);
        % fill in holes by channel
        for c=1:1:3;
            channel=rempict(:,:,c);
            channel=painter(channel,fold,method);
            rempict(:,:,c)=channel;
        end

    case 'r'
        channel=rempict(:,:,1);
        channel(mask)=NaN;
        channel=painter(channel,fold,method);
        rempict(:,:,1)=channel;
        
    case 'g'
        channel=rempict(:,:,2);
        channel(mask)=NaN;
        channel=painter(channel,fold,method);
        rempict(:,:,2)=channel;
        
    case 'b'
        channel=rempict(:,:,3);
        channel(mask)=NaN;
        channel=painter(channel,fold,method);
        rempict(:,:,3)=channel;
        
    case 'h'
        rempict=rgb2hsv(rempict);
        channel=rempict(:,:,1);
        channel(mask)=NaN;
        channel=painter(channel,fold,method);
        rempict(:,:,1)=channel;
        rempict=hsv2rgb(rempict);
        
    case 's'
        rempict=rgb2hsv(rempict);
        channel=rempict(:,:,2);
        channel(mask)=NaN;
        channel=painter(channel,fold,method);
        rempict(:,:,2)=channel;
        rempict=hsv2rgb(rempict);
        
    case 'v'
        rempict=rgb2hsv(rempict);
        channel=rempict(:,:,3);
        channel(mask)=NaN;
        channel=painter(channel,fold,method);
        rempict(:,:,3)=channel;
        rempict=hsv2rgb(rempict);
        
    case 'y'
		rempict=rgb2ypp(rempict);
        channel=rempict(:,:,1);
        channel(mask)=NaN;
        channel=painter(channel,fold,method);
        rempict(:,:,1)=channel;
		rempict=ypp2rgb(rempict);
        
    otherwise
        disp('THRESHOLDINPAINT: unknown mode')
        return
end

    rempict=imcast(rempict,'double');
end

function channel=painter(channel,fold,method)
    channel=inpaint_nans(channel,method);
    if fold==1;
        channel=abs(channel);
        channel(channel>2)=2-mod(channel(channel>2),2);
        channel(channel>1)=1-mod(channel(channel>1),1);
    end
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







