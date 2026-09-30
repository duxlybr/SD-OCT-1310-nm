function  outpict=straightshifter(inpict,amount)
%   STRAIGHTSHIFTER(INPICT, AMOUNT)
%       shifts all rows and columns by the amount specified in AMOUNT
%       all shifts are circular
%
%   AMOUNT is in pixels, expressed as a 3x2 array 
%       [Ry Rx; Gy Gx; By Bx]
    
    amount=round(amount);
    s=size(inpict);
    for m=1:1:s(1);
        for c=1:1:3;
            inpict(m,:,c)=circshift(inpict(m,:,c),[0 amount(c,1)]);
        end
    end
    
    for n=1:1:s(2);
        for c=1:1:3;
            inpict(:,n,c)=circshift(inpict(:,n,c),amount(c,2));
        end
    end
    
    outpict=inpict;
return