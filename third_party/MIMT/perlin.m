function outpict=perlin(outsize,rainbow,method)
%   PERLIN(SIZE, {RAINBOW}, {METHOD})
%       generates pseudo-perlin noise fields. 
%       behavior is random (nonrepeatable).  See PERLIN3() 
%   
%   SIZE is a vector defining the size of the output image
%       1-D outputs are specified in 2-D (e.g. [1 100])
%       3-D output behavior is specified by RAINBOW flag
%   RAINBOW specifies how RGB maps are generated (default 0)
%           when RAINBOW=0, image is composed of uncorrelated 2-D page differences
%           when RAINBOW=1, image is composed of uncorrelated 2-D pages
%       both modes are compromises made to avoid the cost of 3-D interpolation
%       the default mode yields results closer to actual 3-D noise.
%   METHOD is the interpolation method used (see interp2())
%       default 'spline'
% 
%   See also: perlin3

if ~exist('method','var')
    method='spline';
end
if ~exist('rainbow','var')
    rainbow=0;
end


pagesize=outsize(1:2);
if sum(pagesize>1)==1
    s=max(pagesize,2);
elseif sum(pagesize>1)==2 || sum(pagesize>1)==3
    s=pagesize;
else
    disp('PERLIN: currently only supports 1-D or 2-D');
    return
end

if length(outsize)==3
    numchan=outsize(3);
else
    numchan=1;
end

outpict=zeros([pagesize numchan]); 
for c=1:1:numchan;
    wpict=zeros(s);
    w=max(s);
    k=0;
    while w > 3
        k=k+1;
        d=interp2(randn(ceil(s/(2^(k-1))+1)), k-1, method);
        wpict=wpict + k*d(1:s(1),1:s(2));
        w=w-ceil(w/2 - 1);
    end

    if sum(pagesize>1)==1
        wpict=wpict(1:pagesize(1),1:pagesize(2));
    end
    
    outpict(:,:,c)=wpict;
end

[mn mx]=imrange(outpict);
if numchan==3 && rainbow==0
    dv=(mx-mn)/300;
    outpict(:,:,1)=outpict(:,:,2)+outpict(:,:,1)*dv;
    outpict(:,:,3)=outpict(:,:,2)+outpict(:,:,3)*dv;
end

[mn mx]=imrange(outpict);
outpict=uint8(255*(outpict - mn) ./ (mx-mn));

return