function  outpict=cropborder(inpict,width)
%   CROPBORDER(INPICT, WIDTH)
%       crops a border of WIDTH pixels from the edges of INPICT
%       this is much more convenient than using imcrop()
%    
%   WIDTH can either be a single value or a 2-element vector

    if numel(width)==1;
        width=[1 1]*width;
    end
    
    sz=size(inpict);
    outpict=inpict((width(1)+1):(sz(1)-width(1)),(width(2)+1):(sz(2)-width(2)),:);
return