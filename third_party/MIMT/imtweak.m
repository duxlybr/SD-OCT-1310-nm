function outpict=imtweak(inpict,model,changevec)
%   IMTWEAK(INPICT,COLORMODEL,CHANGEVEC)
%       allows simplified manipulation of RGB images or triplets using a 
%       specified color model.  
%
%   INPICT an RGB image, a 4-D image set or a 3-element vector (color triplet)
%       can process multiple triplets (i.e. a color table)
%       so long as triplets are row vectors and array is not 3-D
%
%   COLORMODEL is one of the following 
%       'rgb' for operations on [R G B] in RGB
%       'hsv' for operations on [H S V] in HSV 
%       'hsi' for operations on [H S I] in HSI
%       'hsl' for operations on [H S L] in HSL (as in GIMP <2.9)
%       'hsy' for operations on [H S Y] in HSY using YPbPr
%       'hsyp' for operations on [H S Y] in HSYp using YPbPr
%       'huslab' for operations on [H S L] in HuSL using CIELCHab
%       'husluv' for operations on [H S L] in HuSL using CIELCHuv
%       'huslpab' for operations on [H S L] in HuSLp using CIELCHab
%       'huslpuv' for operations on [H S L] in HuSLp using CIELCHuv
%       'ypbpr' for operations on [Y C H] in polar YPbPr
%       'lchab' for operations on [L C H] in CIELCHab
%       'lchuv' for operations on [L C H] in CIELCHuv
%       'lchsr' for operations on [L C H] in polar SRLAB2
%   
%       HuSL is an adaptation of CIELCHuv/CIELCHab with normalized chroma. 
%           It is particularly useful for tasks such as avoiding out-of-gamut 
%           values when increasing saturation or when rotating hue at high saturation.
%       HSY method uses polar operations in a normalized luma-chroma model
%           this has results very similar to HuSL, but is about 2-3x as fast.
%       HuSLp and HSYp variants are normalized and bounded to the maximum biconic subset of the   
%           projected RGB space. This means HuSLp/HSYp avoids distortion of the chroma space when 
%           normalizing, preserving the uniformity of the parent space. Unfortunately, this 
%           also means it can only render colors near the neutral axis (pastels). 
%           These methods are mostly useful for relative specification of uniform colors.
%       LCH and YPbPr operations are clamped to the extent of RGB by data truncation prior to conversion
%           
%   CHANGEVEC is a 3-element vector specifying amounts by which color
%       channels are to be altered.  Scaling is proportional for 
%       all metrics except hue  In the case of hue, specifying 1.00 will
%       rotate hue 360 degrees.  Assuming an HSL model, CHANGEVEC=[0 1 1]
%       results in no change to INPICT.  CHANGEVEC=[0.33 0.5 0.5] results
%       in a 120 degree hue rotation and a 50% decrease of saturation and
%       lightness. For channels other than hue, specifying a negative value 
%       will invert the channel and then apply the specified scaling
%
%
%   CLASS SUPPORT:
%   Supports 'uint8', 'uint16', 'int16', 'single', and 'double'
%
%   See also: IMMODIFY, RGB2HSI, RGB2HSL, RGB2HSY, RGB2HUSL, RGB2LCH, MAXCHROMA.


% While everything has its place, I find little use for the included HSV, HSI, and HSL methods.
% Users may be comfortable with HSL as used in GIMP or LCH as used in Photoshop.
% If the convenience of familiarity is of substantial merit, feel free to use those.
% 
% Unless your goal is to create images with localized brightness inversions, washed-out
% greys or blown-out highlights, I recommend LCH, HuSL or the HSY/YPP method for general hue/saturation adjustment.  
%
% an unbounded LCH method is potentially lossy; that is, color points are not restrained to the limits of
% the RGB gamut for normal datatype ranges.  When out-of-gamut points are clipped on conversion to RGB, 
% they tend to be mapped to locations far away from the point where they left the space.
% While maintaining a LCH working environment and converting to RGB only for final output would be ideal, 
% These tools are all designed to be stand-alone with RGB input and output.  As such, LCH methods are truncated.
% This results in good appearance with one operation, but the consequences of truncation tend to accumulate with
% repeated operations.  For instance, repeated incremental hue adjustment will tend to compress the chroma range of an
% image to the extent of the HuSLp bicone since truncated information is unrecoverable.  HuSL methods may
% be a useful compromise in these cases, despite their chroma distortion.
%
% HuSL and HSY methods are attempts at creating convenient bounded polar color models like HSV or HSL,
% but which utilize transformations of the input RGB space with better color/brightness separation.  
% HuSL is a variant of CIELCH wherein chroma is normalized to the extent of the RGB gamut.  
% Similarly, my own HSY method uses a polar conversion of YPbPr wherein C is normalized to the RGB cube.
% Both methods constrain color points to reduce the effect of clipping, though HSY is much faster.
%
% As to be expected, most of these methods perform poorly for large brightness adjustments.
% For significant brightness adjustments, consider using a levels/curves tool instead (imlnc)

% results for a 900x650 px image with CHANGEVEC=[0.5 0.5 0.5]
% average of 10 calls
%
% 65ms RGB
% 351ms HSV
% 341ms HSI
% 315ms HSL
% 339ms YPbPr
% 658ms LCHab
% 595ms LCHuv
% 736ms LCHsr
% 338ms HSY
% 290ms HSYp
% 785ms HuSLab
% 706ms HuSLuv
% 708ms HuSLpab
% 670ms HuSLpuv

[inpict inclass]=imcast(inpict,'double');

% is the image argument a color or a picture?
if size(inpict,2)==3 && numel(size(inpict))<3
    inpict=permute(inpict,[3 1 2]);
    iscolorelement=1;
else
    iscolorelement=0;
end

outpict=zeros(size(inpict));
switch lower(model)

    case {'ypp','hsy','hsyp','ypbpr'}
        % Since this method uses a LUT to normalize S, this dimension is quantized.
        % if some smaller step size is desired, modify 'st'
        % 
        % This code is replicated here instead of using RGB2HSY and HSY2RGB
        % in order to retain the LUT and increase speed.
        
        st=255; % <<< change this to alter LUT size
        A=[0.299,0.587,0.114;-0.1687367,-0.331264,0.5;0.5,-0.418688,-0.081312]; % YPbPr
        Axyz=circshift(A,-1);
		Ai=permute(inv(A),[1 3 2]);

        if any(strcmpi(model,{'hsy','ypp','ypbpr'}))
            % color angles
            bl=mod(atan2(A(3,3),A(2,3)),2*pi);
            mg=mod(atan2(A(3,3)+A(3,1),A(2,3)+A(2,1)),2*pi);
            rd=mod(atan2(A(3,1),A(2,1)),2*pi);
            yl=mod(atan2(A(3,1)+A(3,2),A(2,1)+A(2,2)),2*pi);
            gr=mod(atan2(A(3,2),A(2,2)),2*pi);
            cy=mod(atan2(A(3,2)+A(3,3),A(2,2)+A(2,3)),2*pi);
            % black point is at [0 0 0]
            % white point is at [0 0 1]

            % magenta, yellow, cyan corner vectors
            vmg=Axyz(:,1)+Axyz(:,3)-[0 0 1]';
            vyl=Axyz(:,1)+Axyz(:,2)-[0 0 1]';
            vcy=Axyz(:,2)+Axyz(:,3)-[0 0 1]';

            % normals for lower, upper planes
            nr0=cross(Axyz(:,2),Axyz(:,3));
            nb0=cross(Axyz(:,1),Axyz(:,2));
            ng0=cross(Axyz(:,3),Axyz(:,1));
            nr1=cross(vmg,vyl);
            ng1=cross(vyl,vcy);
            nb1=cross(vcy,vmg);

            % find maximal boundaries for S(H,Y)
            y=0:1/st:1; h=0:(2*pi)/st:(2*pi);
            [Y H]=meshgrid(y,h);
            a=cos(H);
            b=sin(H);
            kt=zeros(size(H)); kb=kt;
            % bottom planes G=0, B=0, R=0
            mask=H>=bl | H<rd;
            kb(mask)=-ng0(3)*Y(mask)./(ng0(1)*a(mask) + ng0(2)*b(mask));
            mask=H>=rd & H<gr;
            kb(mask)=-nb0(3)*Y(mask)./(nb0(1)*a(mask) + nb0(2)*b(mask));
            mask=H>=gr & H<bl;
            kb(mask)=-nr0(3)*Y(mask)./(nr0(1)*a(mask) + nr0(2)*b(mask));
            % top planes R=1, G=1, B=1
            mask=H>=mg & H<yl;
            kt(mask)=(nr1(3)-nr1(3)*Y(mask))./(nr1(1)*a(mask) + nr1(2)*b(mask));
            mask=H>=yl & H<cy;
            kt(mask)=(ng1(3)-ng1(3)*Y(mask))./(ng1(1)*a(mask) + ng1(2)*b(mask));
            mask=H>=cy | H<mg;
            kt(mask)=(nb1(3)-nb1(3)*Y(mask))./(nb1(1)*a(mask) + nb1(2)*b(mask));

            % find limiting radius from min parameter value
            k=min(kt,kb);
            SMAX=sqrt((a.*k).^2 + (b.*k).^2);
        elseif strcmpi(model,'hsyp')
            Ybreak=0.50195313;
            Sbreak=0.28211668;
            Y=0:1/st:1;
            SMAX=zeros(size(Y));

            mk=Y<Ybreak;
            SMAX(mk)=Sbreak/Ybreak*Y(mk);
            SMAX(~mk)=Sbreak-Sbreak/(1-Ybreak)*(Y(~mk)-Ybreak);
		end

		A=permute(A,[1 3 2]);
        for f=1:1:size(inpict,4);
            % do YPbPr transform here just to save 12ms
            pict=inpict(:,:,:,f);
			yc(:,:,1)=sum(bsxfun(@times,pict,A(1,:,:)),3);
			yc(:,:,2)=sum(bsxfun(@times,pict,A(2,:,:)),3);
			yc(:,:,3)=sum(bsxfun(@times,pict,A(3,:,:)),3);
            
            H=mod(atan2(yc(:,:,3),yc(:,:,2)),2*pi); % color angle
            S=sqrt(yc(:,:,3).^2+yc(:,:,2).^2); % color magnitude
            Y=yc(:,:,1);

            % normalize S
            if strcmpi(model,'hsy')
                Hp=round(H/(2*pi)*st)+1;
                Yp=round(Y*st)+1;
                smax=SMAX(sub2ind([1 1]*st+1,Hp,Yp));
                mask=(smax<1/512);
                S(~mask)=S(~mask)./smax(~mask);
            elseif strcmpi(model,'hsyp')
                Yp=round(Y*st)+1;
                smax=SMAX(Yp);
                mask=(smax<1/512);
                S(~mask)=S(~mask)./smax(~mask);
            elseif any(strcmpi(model,{'ypp','ypbpr'}))
                Hp=round(H/(2*pi)*st)+1;
                Yp=round(Y*st)+1;
                smax=SMAX(sub2ind([1 1]*st+1,Hp,Yp));
                mask=(smax<1/512);
                S(~mask)=min(S(~mask),smax(~mask));
            end
            
            
            % adjust color points
            if any(strcmpi(model,{'ypp','ypbpr'}))
                changevec=fliplr(changevec);
            end
            H=mod(H+changevec(1)*2*pi,2*pi);
            S=((changevec(2)<0)+sign(changevec(2))*S)*abs(changevec(2));
            Y=min(((changevec(3)<0)+sign(changevec(3))*Y)*abs(changevec(3)),1);
            
            % clamp and denormalize S
            if strcmpi(model,'hsy')
                Hp=round(H/(2*pi)*st)+1;
                Yp=round(Y*st)+1;
                smax=SMAX(sub2ind([1 1]*st+1,Hp,Yp));
                S=min(S,1);
                mask=(smax<1/512);
                S=S.*smax;
                S(mask)=0;
            elseif strcmpi(model,'hsyp')
                Yp=round(Y*st)+1;
                smax=SMAX(Yp);
                mask=(smax<1/512);
                S=S.*smax;
                S(mask)=0;
            elseif any(strcmpi(model,{'ypp','ypbpr'}))
                Hp=round(H/(2*pi)*st)+1;
                Yp=round(Y*st)+1;
                smax=SMAX(sub2ind([1 1]*st+1,Hp,Yp));
                S=min(S,1);
                mask=(smax<1/512);
                S=min(S,smax);
                S(mask)=0;
            end
            
                                    
            yc(:,:,2)=S.*cos(H); % B
            yc(:,:,3)=S.*sin(H); % R
            yc(:,:,1)=Y;

            pict(:,:,1)=sum(bsxfun(@times,yc,Ai(1,:,:)),3);
			pict(:,:,2)=sum(bsxfun(@times,yc,Ai(2,:,:)),3);
			pict(:,:,3)=sum(bsxfun(@times,yc,Ai(3,:,:)),3);
            outpict(:,:,:,f)=max(min(pict,1),0);
        end
    
        
    case 'hsv'
        for f=1:1:size(inpict,4);
            hsvpict=rgb2hsv(inpict(:,:,:,f));
            hsvpict(:,:,1)=mod(hsvpict(:,:,1)+changevec(1),1);
            hsvpict(:,:,2)=min(((changevec(2)<0)+sign(changevec(2))*hsvpict(:,:,2))*abs(changevec(2)),1);
            hsvpict(:,:,3)=min(((changevec(3)<0)+sign(changevec(3))*hsvpict(:,:,3))*abs(changevec(3)),1);
            outpict(:,:,:,f)=hsv2rgb(hsvpict);
        end
        
             
    case 'husluv'
        hmax=360;
        smax=100;
        lmax=100;
        method='luv';
        
        for f=1:1:size(inpict,4);
            huslpict=rgb2husl(inpict(:,:,:,f),method);
            huslpict(:,:,1)=mod(huslpict(:,:,1)+changevec(1)*hmax,hmax);
            huslpict(:,:,2)=min((smax*(changevec(2)<0)+sign(changevec(2))*huslpict(:,:,2))*abs(changevec(2)),smax);
            huslpict(:,:,3)=min((lmax*(changevec(3)<0)+sign(changevec(3))*huslpict(:,:,3))*abs(changevec(3)),lmax);
            outpict(:,:,:,f)=husl2rgb(huslpict,method);
        end
       
        
    case 'huslab'
        hmax=360;
        smax=100;
        lmax=100;
        method='lab';
        
        for f=1:1:size(inpict,4);
            huslpict=rgb2husl(inpict(:,:,:,f),method);
            huslpict(:,:,1)=mod(huslpict(:,:,1)+changevec(1)*hmax,hmax);
            huslpict(:,:,2)=min((smax*(changevec(2)<0)+sign(changevec(2))*huslpict(:,:,2))*abs(changevec(2)),smax);
            huslpict(:,:,3)=min((lmax*(changevec(3)<0)+sign(changevec(3))*huslpict(:,:,3))*abs(changevec(3)),lmax);
            outpict(:,:,:,f)=husl2rgb(huslpict,method);
        end
        
        
    case 'huslpuv'
        hmax=360;
        smax=100;
        lmax=100;
        method='luvp';
        
        for f=1:1:size(inpict,4);
            huslpict=rgb2husl(inpict(:,:,:,f),method);
            huslpict(:,:,1)=mod(huslpict(:,:,1)+changevec(1)*hmax,hmax);
            huslpict(:,:,2)=min((smax*(changevec(2)<0)+sign(changevec(2))*huslpict(:,:,2))*abs(changevec(2)),smax);
            huslpict(:,:,3)=min((lmax*(changevec(3)<0)+sign(changevec(3))*huslpict(:,:,3))*abs(changevec(3)),lmax);
            outpict(:,:,:,f)=husl2rgb(huslpict,method);
        end
       
        
    case 'huslpab'
        hmax=360;
        smax=100;
        lmax=100;
        method='labp';
        
        for f=1:1:size(inpict,4);
            huslpict=rgb2husl(inpict(:,:,:,f),method);
            huslpict(:,:,1)=mod(huslpict(:,:,1)+changevec(1)*hmax,hmax);
            huslpict(:,:,2)=min((smax*(changevec(2)<0)+sign(changevec(2))*huslpict(:,:,2))*abs(changevec(2)),smax);
            huslpict(:,:,3)=min((lmax*(changevec(3)<0)+sign(changevec(3))*huslpict(:,:,3))*abs(changevec(3)),lmax);
            outpict(:,:,:,f)=husl2rgb(huslpict,method);
        end
            
        
    case 'lchab'
        hmax=360;
        cmax=134.2;
        lmax=100;
        method='lab';

        for f=1:1:size(inpict,4);
            lchpict=rgb2lch(inpict(:,:,:,f),method);
            lchpict(:,:,3)=mod(lchpict(:,:,3)+changevec(3)*hmax,hmax);
            lchpict(:,:,2)=min((cmax*(changevec(2)<0)+sign(changevec(2))*lchpict(:,:,2))*abs(changevec(2)),cmax);
            lchpict(:,:,1)=min((lmax*(changevec(1)<0)+sign(changevec(1))*lchpict(:,:,1))*abs(changevec(1)),lmax);
            outpict(:,:,:,f)=lch2rgb(lchpict,method,'truncatelch');
        end
      
        
    case 'lchuv'
        hmax=360;
        cmax=180;
        lmax=100;
        method='luv';

        for f=1:1:size(inpict,4);
            lchpict=rgb2lch(inpict(:,:,:,f),method);
            lchpict(:,:,3)=mod(lchpict(:,:,3)+changevec(3)*hmax,hmax);
            lchpict(:,:,2)=min((cmax*(changevec(2)<0)+sign(changevec(2))*lchpict(:,:,2))*abs(changevec(2)),cmax);
            lchpict(:,:,1)=min((lmax*(changevec(1)<0)+sign(changevec(1))*lchpict(:,:,1))*abs(changevec(1)),lmax);
            outpict(:,:,:,f)=lch2rgb(lchpict,method,'truncatelch');
        end
        
    case 'lchsr'
        hmax=360;
        cmax=103;
        lmax=100;
        method='srlab';

        for f=1:1:size(inpict,4);
            lchpict=rgb2lch(inpict(:,:,:,f),method);
            lchpict(:,:,3)=mod(lchpict(:,:,3)+changevec(3)*hmax,hmax);
            lchpict(:,:,2)=min((cmax*(changevec(2)<0)+sign(changevec(2))*lchpict(:,:,2))*abs(changevec(2)),cmax);
            lchpict(:,:,1)=min((lmax*(changevec(1)<0)+sign(changevec(1))*lchpict(:,:,1))*abs(changevec(1)),lmax);
            outpict(:,:,:,f)=lch2rgb(lchpict,method,'truncatelch');
        end
        
    case 'rgb'
        for f=1:1:size(inpict,4);
            rgbpict=inpict(:,:,:,f);

            if abs(changevec(1))~=1
                rgbpict(:,:,1)=min(((changevec(1)<0)+sign(changevec(1))*rgbpict(:,:,1))*abs(changevec(1)),1);
            end
            if abs(changevec(2))~=1
                rgbpict(:,:,2)=min(((changevec(2)<0)+sign(changevec(2))*rgbpict(:,:,2))*abs(changevec(2)),1);
            end
            if abs(changevec(3))~=1
                rgbpict(:,:,3)=min(((changevec(3)<0)+sign(changevec(3))*rgbpict(:,:,3))*abs(changevec(3)),1);
            end
            
            outpict(:,:,:,f)=rgbpict;
        end
        
     
    case 'hsl'
        hmax=360;

        for f=1:1:size(inpict,4);
			hslpict=rgb2hsl(inpict(:,:,:,f));
            hslpict(:,:,1)=mod(hslpict(:,:,1)+changevec(1)*hmax,hmax);
            hslpict(:,:,2)=min(((changevec(2)<0)+sign(changevec(2))*hslpict(:,:,2))*abs(changevec(2)),1);
            hslpict(:,:,3)=min(((changevec(3)<0)+sign(changevec(3))*hslpict(:,:,3))*abs(changevec(3)),1);
            outpict(:,:,:,f)=hsl2rgb(hslpict);
        end
        
        
    case 'hsi'
        hmax=360;

        for f=1:1:size(inpict,4);
            hsipict=rgb2hsi(inpict(:,:,:,f));
            hsipict(:,:,1)=mod(hsipict(:,:,1)+changevec(1)*hmax,hmax);
            hsipict(:,:,2)=min(((changevec(2)<0)+sign(changevec(2))*hsipict(:,:,2))*abs(changevec(2)),1);
            hsipict(:,:,3)=min(((changevec(3)<0)+sign(changevec(3))*hsipict(:,:,3))*abs(changevec(3)),1);
            outpict(:,:,:,f)=hsi2rgb(hsipict);
        end
 
          
    otherwise
        disp('IMTWEAK: unknown color model')
        return
end

if iscolorelement==1;
    outpict=permute(outpict,[2 3 1]);
end

outpict=imcast(outpict,inclass);

return




