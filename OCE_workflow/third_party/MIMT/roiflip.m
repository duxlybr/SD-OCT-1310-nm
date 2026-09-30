function outpict=roiflip(inpict,mask,dim,mode)
%   ROIFLIP(INPICT, MASK, DIM, {MODE})
%       returns a copy of the input image wherein all pixels
%       selected by the mask are flipped along a specified dimension.
%       
%   INPICT is a 2-D or 3-D image
%   MASK is a 2-D or 3-D logical array
%   DIM specifies the dimension along which the selected pixels are flipped
%   MODE specifies whether local continuity is preserved
%       as each line of MASK is scanned for establishing an ROI in INPICT:
%       for MODE=0, all pixels selected by the mask line are flipped as a whole
%           local continuity is not preserved. 
%       for MODE=1, pixels selected by each contiguous region are flipped
%           as independent groups.  Some local continuity is preserved (default)
%
%   NOTE:
%   Although MODE=1 can help preserve continuity, it can only do so 
%   along the axis of the sample line. Shearing can still occur between lines. 
%   Results are usually pretty garbled unless mask regions are individually convex.

if nargin==3
    mode=1;
end

s=size(inpict);
cbg=size(inpict,3);
cm=size(mask,3);
if cbg~=cm
    if cbg==1 && cm==3 % grey bg, rgb mask
        inpict=repmat(inpict,[1 1 3]); 
        s=size(inpict);
        cbg=size(inpict,3);
    elseif cm==1 && cbg==3 % rgb bg, logical mask
        mask=repmat(mask,[1 1 3]); 
    else
        disp('ROIFLIP: dim 3 of images must have size 1 or 3')
        return
    end
end

mask=logical(mask);
outpict=zeros(s,'uint8');
if mode==0
    % flip entire ROI and ignore continuity
    if dim==2
        for c=1:1:cbg;
            for m=1:1:s(1);
                bline=inpict(m,:,c);
                mline=mask(m,:,c);
                bline(mline)=flipdim(bline(mline),2);
                outpict(m,:,c)=bline;
            end
        end
    else
        for c=1:1:cbg;
            for n=1:1:s(2);
                bline=inpict(:,n,c);
                mline=mask(:,n,c);
                bline(mline)=flipdim(bline(mline),1);
                outpict(:,n,c)=bline;
            end
        end
    end
    
else
    if dim==2
        for c=1:1:cbg;
            for m=1:1:s(1);
                bline=inpict(m,:,c);
                mline=mask(m,:,c);

                if any(mline)
                    marks=diff([0 mline]);
                    starts=(1:length(mline)).*(marks==1);
                    ends=((1:length(mline))-1).*(marks==-1);
                    starts=starts(starts~=0);
                    ends=ends(ends~=0);
                    
                    % close ROI if still open at end of line
                    if numel(starts) > numel(ends)
                        ends=[ends  length(mline)];
                    end

                    for r=1:length(starts);
                        bline(starts(r):ends(r))=flipdim(bline(starts(r):ends(r)),2);
                    end

                end

                outpict(m,:,c)=bline;
            end
        end
    else
        for c=1:1:cbg;
            for n=1:1:s(2);
                bline=inpict(:,n,c);
                mline=mask(:,n,c);
                
                if any(mline)
                    marks=diff([0; mline]);
                    starts=(1:length(mline)).*(marks==1)';
                    ends=((1:length(mline))-1).*(marks==-1)';
                    starts=starts(starts~=0);
                    ends=ends(ends~=0);

                    % close ROI if still open at end of line
                    if numel(starts) > numel(ends)
                        ends=[ends  length(mline)];
                    end
                    
                    for r=1:length(starts);
                        bline(starts(r):ends(r))=flipdim(bline(starts(r):ends(r)),1);
                    end

                end
                
                outpict(:,n,c)=bline;
            end
        end
    end

end

return

    
























