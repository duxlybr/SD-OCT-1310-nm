function outpict=addborder(inpict,width,color)
%   ADDBORDER(INPICT, {WIDTH}, {COLOR})
%       Add a colored border to an image.  This is often more
%       convenient and faster than PADARRAY.
%
%   INPICT is an I/RGB image
%   WIDTH specifies border width
%       values >= 1 are interpreted as a width in pixels
%       values < 1 are interpreted as a fraction of the image diagonal
%       default is 1.5% of image diagonal (0.015)
%   COLOR is a scalar or RGB triplet specified with relation
%       to the same white value used in INPICT
%       default is black
%
%   CLASS SUPPORT: output type is inherited from input

if ~exist('color','var')
	color=zeros([1 size(inpict,3)]);
end

s=size(inpict);

if ~exist('width','var')
	width=0.015;
end

width=abs(width);
if width < 1
	width=width*norm(s(1:2),2);
end

width=ceil(width);
outpict=ones([s(1:2)+width*2 3 size(inpict,4)],class(inpict));

padv=[1:width (width+s(1)):(2*width+s(1))];
padh=[1:width (width+s(2)):(2*width+s(2))];
picv=(width+1):(width+s(1));
pich=(width+1):(width+s(2));

for c=1:size(inpict,3)
	outpict(padv,:,c,:)=color(c);
	outpict(:,padh,c,:)=color(c);
	outpict(picv,pich,c,:)=inpict(:,:,c,:);
end

end
