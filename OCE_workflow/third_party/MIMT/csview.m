function csview(spc,varargin)
%   CSVIEW(SPACE, {PARAMETERS})
%       Visualize the projection of sRGB gamut within various color spaces.
%       Optionally visualize the trajectory of out-of-gamut points
%       as would occur if data range is clamped on conversion from SPACE to sRGB
%       If called with no arguments, a GUI tool is opened to allow interactive use.
%
%   SPACE is one of the following:
%       'hsv' 
%       'hsl'
%       'hsi'
%       'yuv' 
%       'yiq' 
%       'ypbpr' 
%       'ycbcr' 
%       'ydbdr'
%       'xyz'     CIEXYZ
%       'lab'     CIELAB
%       'luv'     CIELUV
%       'srlab'   SRLAB2
%       'lchab'   cylindrical CIELAB
%       'lchuv'   cylindrical CIELUV
%       'lchsr'   cylindrical SRLAB2
%       'hsy'     a normalized polar variant of YPbPr
%       'huslab'  a normalized polar variant of CIELAB
%       'husluv'  a normalized polar variant of CIELUV
%
%   Optional parameters include 'invert' and 'testpoint'
%   'invert' inverts the colormap for operation on inverted X displays. 
%       This also disables scene lighting (can't invert lighting)
%       e.g. csview('lab','invert',true);
%
%   'testpoint' parameter defines a color point in SPACE.
%       To be followed by a 3-element vector parameterized WRT the axes and range of SPACE. 
%       i.e. TESTPOINT==[20 100 0] and SPACE=='lch' implies a location of L=20, C=100, H=0.
%
%       If specified, a plane will be drawn at the original elevation as a visual aid.
%       A trajectory will be drawn to indicate the result of post-conversion clipping of RGB values.
%
%       Note that in HSY and HuSL modes, the chroma normalization allows simple clamping 
%       before RGB conversion. Oversaturation has minimal effect on H and Y/L.
%
%       Compare the following example pairs:
%         LCHab versus HuSLab
%           csview('lchab','testpoint',[80 60 12]);
%           csview('huslab','testpoint',[12 200 80]);
%         LCHuv versus HuSLuv
%           csview('lchuv','testpoint',[80 101 12]);
%           csview('husluv','testpoint',[12 200 80]);
%         YPbPr versus HSY
%           csview('ypbpr','testpoint',[0.8 -0.14 0.43]);
%           csview('hsy','testpoint',[0 3 0.8]);
%
%       Bear in mind the expectation that points should stay on a radial is merely 
%       based on my assumption of a polar working method. It might not be what you need.
%
%   'alpha' parameter specifies face alpha of the surf objects which create the projected cube
%       This may not produce desired results when 'testpoint' is set.  I'm not sure if this
%       is a general issue with alpha blending or an issue specific to opengl+fglrx.
%
%   While HSV, HSL methods are available, they're offered only as a novelty.  
%   They render as cylinders due to the naive math, so tiling of the end faces 
%   is kind of bogus and point trajectories won't make much sense.
%
%   This function makes use of Pascal Getreuer's COLORSPACE() for several conversion types.
%   http://www.mathworks.com/matlabcentral/fileexchange/28790-colorspace-transformations

if nargin==0;
    csview_gui;
    return
end

for k=1:2:length(varargin);
    switch lower(varargin{k})
        case 'testpoint'
            testpoint=varargin{k+1};
        case 'invert'
            invert=varargin{k+1};
        case 'alpha'
            fa=varargin{k+1};   
        otherwise
            if ~isnumeric(varargin{k})
                disp(sprintf('CSVIEW: unknown input parameter name %s',varargin{k}))
            end
            return
    end
end

if ~exist('testpoint','var')
    showtrajectory=false;
    testpoint=[0 0 0];
else
    showtrajectory=true;
end

if ~exist('invert','var')
    invert=1;
else
    invert=-1;
end

if ~exist('fa','var')
    fa=1;
end

% HSY, HuSL methods are only a simulation
denormalized='';
if strcmpi(spc(spc~=' '),'hsy')
    denormalized='hsy';
    origpoint=testpoint;
    testpoint(2)=1;
    limitpoint=torgb(permute(testpoint,[3 1 2]),spc);
    spc='ypbpr';
    limitpoint=fromrgb(limitpoint,spc);
    maxS=sqrt(limitpoint(2)^2+limitpoint(3)^2);
    testpoint(1)=testpoint(1)+108.6;
    PB=origpoint(2)*maxS*cos(testpoint(1)*pi/180);
    PR=origpoint(2)*maxS*sin(testpoint(1)*pi/180);
    Y=testpoint(3);
    testpoint=[Y PB PR];
elseif strcmpi(spc(spc~=' '),'huslab')
    denormalized='huslab';
    origpoint=testpoint;
    testpoint(2)=100;
    limitpoint=torgb(permute(testpoint,[3 1 2]),spc);
    spc='lab';
    limitpoint=fromrgb(limitpoint,spc);
    maxS=sqrt(limitpoint(2)^2+limitpoint(3)^2);
    A=origpoint(2)*maxS*cos(testpoint(1)*pi/180)/100;
    B=origpoint(2)*maxS*sin(testpoint(1)*pi/180)/100;
    L=testpoint(3);
    testpoint=[L A B];
elseif strcmpi(spc(spc~=' '),'husluv')
    denormalized='husluv';
    origpoint=testpoint;
    testpoint(2)=100;
    limitpoint=torgb(permute(testpoint,[3 1 2]),spc);
    spc='luv';
    limitpoint=fromrgb(limitpoint,spc);
    maxS=sqrt(limitpoint(2)^2+limitpoint(3)^2);
    U=origpoint(2)*maxS*cos(testpoint(1)*pi/180)/100;
    V=origpoint(2)*maxS*sin(testpoint(1)*pi/180)/100;
    L=testpoint(3);
    testpoint=[L U V];  
end

switch lower(spc(spc~=' '))
    case {'hsv','hsl','hsi'}
        xyz=[1 2 3];
        polar=true;
        maxZ=1; 
    case {'lchab','lchuv','lchsr'}
        xyz=[3 2 1];
        polar=true;
        maxZ=100;
    case {'ypbpr','ydbdr','yiq','yuv'}
        xyz=[2 3 1];
        polar=false; 
        maxZ=1;
    case {'xyz'}
        xyz=[1 3 2];
        polar=false; 
        maxZ=1;    
    case 'ycbcr'
        xyz=[2 3 1];
        polar=false; 
        maxZ=255;
    case {'luv','lab','srlab'}
        xyz=[2 3 1];
        polar=false; 
        maxZ=100;
    otherwise
        disp('COLORSPACEVIEW: unsupported space type')
        return
end


bk=permute([0 0 0],[3 1 2]);
wh=permute([1 1 1],[3 1 2]);
mg=permute([1 0 1],[3 1 2]);
rd=permute([1 0 0],[3 1 2]);
yl=permute([1 1 0],[3 1 2]);
gr=permute([0 1 0],[3 1 2]);
cy=permute([0 1 1],[3 1 2]);
bl=permute([0 0 1],[3 1 2]);

cla
lw=1.5;
subdivs=50;
f=faceresize(cat(1,cat(2,bk,rd),cat(2,gr,yl)),subdivs); 
fv=drawface(f,xyz,spc,polar,invert,fa); axis vis3d; hold on;
drawedges(fv,f,invert,lw,xyz);

f=faceresize(cat(1,cat(2,bk,gr),cat(2,bl,cy)),subdivs); 
fv=drawface(f,xyz,spc,polar,invert,fa);
drawedges(fv,f,invert,lw,xyz);

f=faceresize(cat(1,cat(2,bk,bl),cat(2,rd,mg)),subdivs); 
drawface(f,xyz,spc,polar,invert,fa);

f=faceresize(cat(1,cat(2,wh,mg),cat(2,yl,rd)),subdivs); 
fv=drawface(f,xyz,spc,polar,invert,fa);
drawedges(fv,f,invert,lw,xyz);

f=faceresize(cat(1,cat(2,wh,yl),cat(2,cy,gr)),subdivs); 
drawface(f,xyz,spc,polar,invert,fa);

f=faceresize(cat(1,cat(2,wh,cy),cat(2,mg,bl)),subdivs); 
fv=drawface(f,xyz,spc,polar,invert,fa);
drawedges(fv,f,invert,lw,xyz);

lv=[0 0 -0.1; 0 0 1.1]*maxZ;
line(lv(:,1),lv(:,2),lv(:,3),'color','b','linewidth',lw)
line(lv(:,1),lv(:,2),lv(:,3),'color','y','linestyle','--','linewidth',lw)


if showtrajectory
    if strcmpi(denormalized,'hsy')
        RGBpoint=torgb(permute(origpoint,[3 1 2]),'hsy');
    elseif strcmpi(denormalized,'huslab')
        RGBpoint=torgb(permute(origpoint,[3 1 2]),'huslab');
    elseif strcmpi(denormalized,'husluv')
        RGBpoint=torgb(permute(origpoint,[3 1 2]),'husluv');
    else
        RGBpoint=torgb(permute(testpoint,[3 1 2]),spc);
    end
    RGBpoint=min(max(RGBpoint,0),1);
    
    CSPpoint=permute(fromrgb(RGBpoint,spc),[2 3 1]);
    if polar; 
        A=CSPpoint(xyz(2)).*cos(CSPpoint(xyz(1))*pi/180);
        B=CSPpoint(xyz(2)).*sin(CSPpoint(xyz(1))*pi/180); 
        CSPpoint(xyz(1))=A; CSPpoint(xyz(2))=B;
    end
    CSPpoint=CSPpoint(xyz);

    axis tight
    
    if polar
        lv=[testpoint(xyz(2))*cos(testpoint(xyz(1))*pi/180) ...
            testpoint(xyz(2))*sin(testpoint(xyz(1))*pi/180) testpoint(xyz(3))]; 
    else
        lv=testpoint(xyz);
    end
    lv=[lv; CSPpoint; 0 0 testpoint(xyz(3))];
    
    
    line(lv([1 2],1),lv([1 2],2),lv([1 2],3),'color','b','linewidth',lw)
    line(lv([1 2],1),lv([1 2],2),lv([1 2],3),'color','y','linestyle','--','linewidth',lw)
    line(lv([1 3],1),lv([1 3],2),lv([1 3],3),'color','k','linestyle',':','linewidth',lw)
    plot3(lv(1,1),lv(1,2),lv(1,3),'b','marker','*','markersize',10,'linewidth',lw);
    plot3(lv(2,1),lv(2,2),lv(2,3),'y','marker','o','markersize',10,'linewidth',lw);
    
    axis tight
    XL=get(gca,'xlim');
    YL=get(gca,'ylim');
    k=patch([XL(2) XL(2), XL(1) XL(1)],[YL(1) YL(2) YL(2) YL(1)], [1 1 1 1],'facealpha',0.4,'edgealpha',0.8);
    set(k,'zdata', [1 1 1 1]*testpoint(xyz(3))); % for some reason, it refuses to work directly as above (2009b)
end

set(gca,'Projection','perspective');
view(3);
daspect([1,1,1])
if invert==1
    camlight 
    %lighting gouraud
end
grid on

end

function face=faceresize(fkern,subdivs)
	% IF IPT IS INSTALLED
	if license('test', 'image_toolbox')
		face=imresize(fkern,[1 1]*(subdivs+1),'bilinear'); 
	else % this is a marginally slower fallback method
		face=zeros([subdivs+1 subdivs+1 3]);
		for c=1:3
			face(:,:,c)=interp2(fkern(:,:,c),(1:1/subdivs:2)',1:1/subdivs:2);
		end
	end
	
	face=max(min(face,1),0);
end

function out=fromrgb(f,spc)
    switch lower(spc(spc~=' '))
        case 'hsi'
            out=rgb2hsi(f);
        case 'hsy'
            out=rgb2hsy(f);
        case 'huslab'
            out=rgb2husl(f,'lab');
        case 'husluv'
            out=rgb2husl(f,'luv'); 
        case 'lchab'
            out=rgb2lch(f,'lab');
        case 'lchuv'
            out=rgb2lch(f,'luv');
        case 'srlab'
            out=rgb2lch(f,'srlab');   
            Hrad=out(:,:,3)*pi/180;
            out(:,:,3)=sin(Hrad).*out(:,:,2); % B
            out(:,:,2)=cos(Hrad).*out(:,:,2); % A
        case 'lchsr'
            out=rgb2lch(f,'srlab');  
        otherwise
            out=colorspace(['>' spc],f);
    end
end

function out=torgb(f,spc)
    switch lower(spc(spc~=' '))
        case 'hsi'
            out=hsi2rgb(f);
        case 'hsy'
            out=hsy2rgb(f);
        case 'huslab'
            out=husl2rgb(f,'lab');
        case 'husluv'
            out=husl2rgb(f,'luv');
        case 'lchab'
            out=lch2rgb(f,'lab');
        case 'lchuv'
            out=lch2rgb(f,'luv');
        case 'lchsr'
            out=lch2rgb(f,'srlab');
        case 'srlab'
            L=f(:,:,1);
            Hrad=mod(atan2(f(:,:,3),f(:,:,2)),2*pi);
            H=Hrad*180/pi;
            C=sqrt(f(:,:,2).^2 + f(:,:,3).^2);
            out=lch2rgb(cat(3,L,C,H),'srlab');
        otherwise
            out=colorspace(['<' spc],f);
    end
end

function drawline(fvb,fb,lw,xyz)
    surf(fvb(:,:,xyz(1)),fvb(:,:,xyz(2)),fvb(:,:,xyz(3)),fb,'facecol','no','edgecol','interp','linewidth',lw);
end

function fv=drawface(f,xyz,spc,polar,invert,fa)
    fv=fromrgb(f,spc);
    if polar; 
        A=fv(:,:,xyz(2)).*cos(fv(:,:,xyz(1))*pi/180);
        B=fv(:,:,xyz(2)).*sin(fv(:,:,xyz(1))*pi/180); 
        fv(:,:,xyz(1))=A; fv(:,:,xyz(2))=B;
    end
    f=(invert<0)+sign(invert)*f;
	% this would look nicer with subtle edge alpha
	% but it ruins refresh rate and makes plot manipulation laggy
    surf(fv(:,:,xyz(1)),fv(:,:,xyz(2)),fv(:,:,xyz(3)),f,'edgealpha',0,'facealpha',fa,'ambientstrength',0.4); 
end

function drawedges(fv,f,invert,lw,xyz)
    fvb=repmat(fv(1,:,:),[2 1 1]); fb=repmat(f(1,:,:),[2 1 1]);
    drawline(fvb,(invert>0)-sign(invert)*fb,lw,xyz);
    fvb=repmat(fv(end,:,:),[2 1 1]); fb=repmat(f(end,:,:),[2 1 1]);
    drawline(fvb,(invert>0)-sign(invert)*fb,lw,xyz);
    fvb=repmat(fv(:,1,:),[1 2 1]); fb=repmat(f(:,1,:),[1 2 1]);
    drawline(fvb,(invert>0)-sign(invert)*fb,lw,xyz);
    fvb=repmat(fv(:,end,:),[1 2 1]); fb=repmat(f(:,end,:),[1 2 1]);
    drawline(fvb,(invert>0)-sign(invert)*fb,lw,xyz);
end
















