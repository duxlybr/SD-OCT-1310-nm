function outpict=dilatemargins(inpict,margins,se,invert,mode)
%   DILATEMARGINS(INPICT, MARGINS, SE, {INVERT},{MODE})
%       performs selective dilation & erosion on lightest and darkest pixels 
%
%   INPICT is an RGB image
%   MARGINS is a 1x2 vector specifying black and white value margins
%       [0 0] corresponds to black/white values of [0 255]
%   SE is a structure element for dilation (see strel())
%   INVERT (0 or 1, default 0) when set, output behavior is inverted
%       lightest pixels are darkened, etc
%   MODE specifies how the margins vector is interpreted
%       'mono' matches pixels where all channels are within the margins
%       'rgb' matches pixel channels independently (default)

if nargin==3
    invert=0;
    mode='rgb';
end

if nargin==4
    mode='rgb';
end

if strcmpi(mode,'mono')
    wmask=findpixels(inpict,(255-margins(2))*[1 1 1],'ge');
    bmask=findpixels(inpict,margins(1)*[1 1 1],'le');

    wpict=imdilate(replacepixels([0 0 0],inpict,~wmask),se);
    bpict=imerode(replacepixels([1 1 1]*255,inpict,~bmask),se);
elseif strcmpi(mode,'rgb')
    for c=1:size(inpict,3);
        inchan=inpict(:,:,c);
        wmask(:,:,c)=inchan >= (255-margins(2));
        bmask(:,:,c)=inchan <= margins(1);

        wt=inchan; bt=inchan;
        wt(~wmask(:,:,c))=0;
        bt(~bmask(:,:,c))=255;
        wpict(:,:,c)=imdilate(wt,se);
        bpict(:,:,c)=imerode(bt,se);
    end
end

if invert==0
    outpict=imblend(wpict,inpict,1,'lighten rgb');
    outpict=imblend(bpict,outpict,1,'darken rgb');
else
    outpict=imblend(255-wpict,inpict,1,'darken rgb');
    outpict=imblend(255-bpict,outpict,1,'lighten rgb');
end

return

















