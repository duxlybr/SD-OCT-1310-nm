function outpict=mono(inpict,channel)
%   MONO(INPICT,CHANNEL)
%       extracts a single channel from RGB images or triplets
%
%   INPICT an RGB image, a 4-D image set or a 3-element vector (color triplet)
%       can process multiple triplets (i.e. a color table)
%       so long as triplets are row vectors and array is not 3-D
%   CHANGEVEC is a string specifying the channel to extract
%       'r', 'g', 'b' corresponding to the channels of RGB
%       'h', 's', 'v' corresponding to the channels of HSV
%       'l', 'i', 'y' HSL lightness, HSI intensity, luma
%       'l lch', 'c lch', 'h lch' correspond to LCH from CIELCHab 
%       'h husl', 's husl', 'l husl' correspond to HSL from HuSL
%       
%   note that doing things like mono([247 21 140],'r') is trivial.  
%   LCH and HuSL methods are much slower, as they use a full image conversion
%
%   CLASS SUPPORT:
%       Accepts images of 'uint8' and 'double'
%       Return type is inherited from INPICT
%       In the case of a 'double' input, any image containing values >1
%       is assumed to have a white value of 255. 

% output type is inherited from input, assumes white value of either 1 or 255
inclass=class(inpict);
if strcmp(inclass,'uint8')
    whval=255;
elseif strcmp(inclass,'double')
    if max(max(max(inpict)))<=1
        whval=1;
    else 
        whval=255;
    end
else
    disp('MONO: unsupported class for INPICT')
    return
end

% is the image argument a color or a picture?
if size(inpict,2)==3 && numel(size(inpict))<3
    inpict=permute(inpict,[3 1 2]);
    iscolorelement=1;
else
    iscolorelement=0;
end

outsize=size(inpict); 
outsize(3)=1;
outpict=zeros(outsize,inclass);
for f=1:1:size(inpict,4);
    switch lower(channel(channel~=' '))
        case 'r'
            outpict(:,:,1,f)=inpict(:,:,1,f);
        case 'g'
            outpict(:,:,1,f)=inpict(:,:,2,f);    
        case 'b'
            outpict(:,:,1,f)=inpict(:,:,3,f);  
        case 'h'
            %hsvpict=rgb2hsv(double(inpict(:,:,:,f))/whval);
            %outpict(:,:,1,f)=cast(hsvpict(:,:,1)*whval,inclass); 
            wpict=double(inpict(:,:,:,f))/whval;
            R=wpict(:,:,1);
            G=wpict(:,:,2);
            B=wpict(:,:,3);
            M=max(wpict,[],3);
            D=M-min(wpict,[],3);
            D=D+(D==0);
            H=zeros(size(R));

            rm=wpict(:,:,1)==M;
            gm=wpict(:,:,2)==M;
            bm=wpict(:,:,3)==M;
            %bm=~(rm | gm);
            H(rm)=(G(rm)-B(rm))./D(rm);
            H(gm)=2+(B(gm)-R(gm))./D(gm);
            H(bm)=4+(R(bm)-G(bm))./D(bm);

            H=H/6;
            ltz=H<0;
            H(ltz)=H(ltz)+1;
            H(D==0)=NaN;
            outpict(:,:,1,f)=cast(H*whval,inclass);
        case 's'
            wpict=double(inpict(:,:,:,f))/whval;
            mx=max(wpict,[],3);
            mn=min(wpict,[],3);
            outpict(:,:,1,f)=cast((mx-mn)./(mx+(mx==0))*whval,inclass);
        case 'v'
            outpict(:,:,1,f)=max(inpict(:,:,:,f),[],3);
        case 'l'
            wpict=double(inpict(:,:,:,f));
            mx=max(wpict,[],3);
            mn=min(wpict,[],3);
            outpict(:,:,1,f)=cast((mx+mn)/2,inclass);
        case 'i'
            wpict=double(inpict(:,:,:,f));
            outpict(:,:,1,f)=cast(mean(wpict,3),inclass);
        case 'y'
            factors=[0.299 0.587 0.114];
            cscale=repmat(reshape(factors,1,1,3),outsize(1:3));
            Y=sum(double(inpict(:,:,:,f)).*cscale,3);
            outpict(:,:,1,f)=cast(Y,inclass);   
        case {'llch','lhusl'} % L is identical here
			A=rgb2lch(inpict(:,:,:,f),'lab');
            outpict(:,:,1,f)=cast(A(:,:,1)/100*whval,inclass);
        case 'clch'
			A=rgb2lch(inpict(:,:,:,f),'lab');
            outpict(:,:,1,f)=cast(A(:,:,2)/134.2*whval,inclass);
        case 'hlch'
            A=rgb2lch(inpict(:,:,:,f),'lab');
            outpict(:,:,1,f)=cast(A(:,:,3)/360*whval,inclass);
        case 'hhusl'
            A=rgb2husl(inpict(:,:,:,f));
            outpict(:,:,1,f)=cast(A(:,:,1)/360*whval,inclass);
        case 'shusl'
            A=rgb2husl(inpict(:,:,:,f));
            outpict(:,:,1,f)=cast(A(:,:,2)/100*whval,inclass);
        otherwise
            disp('MONO: unsupported channel string')
            return
    end
end

if iscolorelement==1;
    outpict=permute(outpict,[2 3 1]);
end

return




