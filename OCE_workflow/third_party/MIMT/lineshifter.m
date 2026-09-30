function  outpict=lineshifter(inpict,mask,amt,order)
%   LINESHIFTER(INPICT, MASK, SHIFTAMOUNT, {ORDER});
%       returns a copy of the input image, with RGB channels shifted
%       proportional to the mean row and column channel values
%
%   INPICT is a single rgb image
%   MASK is a single rgb image whose vector means are used to calculate
%       shift amounts for INPICT
%   SHIFTAMOUNT is a unity-scaled ratio
%       expressed as a 3x2 array [Ry Rx; Gy Gx; By Bx]
%   ORDER specifies which axis to shift first
%       'normal' shifts columnwise first (default)
%       'reverse' shifts row-wise first (used to undo shifts)
%       use 'reverse' and negate SLURAMOUNT to undo a 'normal' shift
    
if nargin<4;
    order='normal';
end

s=size(inpict);
if sum(abs(amt(:,1)))~=0
    rowmeans=mod(round(mean(mask,2).*permute(repmat(amt(:,1)',[s(1) 1 1]),[1 3 2])),s(2));
end
if sum(abs(amt(:,2)))~=0
    colmeans=mod(round(mean(mask,1).*permute(repmat(amt(:,2),[1 s(2) 1]),[3 2 1])),s(1));
end

if strcmpi(order,'reverse')
    for c=1:1:3;
        if amt(c,2)~=0
            for n=1:1:s(2);
            inpict(:,n,c)=circshift(inpict(:,n,c),colmeans(1,n,c));
            end
        end
    end
end    

for c=1:1:3;
    if amt(c,1)~=0
        for n=1:1:s(1);
            inpict(n,:,c)=circshift(inpict(n,:,c),[0 rowmeans(n,1,c)]);
        end
    end
end

if strcmpi(order,'normal')
    for c=1:1:3;
        if amt(c,2)~=0
            for n=1:1:s(2);
            inpict(:,n,c)=circshift(inpict(:,n,c),colmeans(1,n,c));
            end
        end
    end
end

outpict=inpict;

return











