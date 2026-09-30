function outpict=roishift(inpict,mask,dim,amt,mode,fill)
%   ROISHIFT(INPICT, MASK, DIM, AMOUNT, {MODE}, {FILL})
%       returns a copy of the input image wherein all pixels
%       selected by the mask are shifted along a specified dimension.
%       
%   INPICT is a 2-D or 3-D image
%   MASK is a 2-D or 3-D logical array
%   DIM specifies the dimension along which the selected pixels are shifted
%   AMOUNT is a scalar specifying the number of pixels to shift
%   MODE specifies whether local continuity is preserved
%       as each line of MASK is scanned for establishing an ROI in INPICT:
%       for MODE=0, all pixels selected by the mask line are shifted as a whole
%           local continuity is not preserved. 
%       for MODE=1, pixels selected by each contiguous region are shifted
%           as independent groups.  Some local continuity is preserved (default)
%   FILL specifies how the trailing edge pixels are filled
%       if 'circular', the shift is circular (default)
%       if 'replicate', the trailing pixel value is replicated
%       if specified as a color value or RGB triplet, fill will be specified color
%           e.g. [32 158 7]
%
%   NOTE:
%   Although MODE=1 can help preserve continuity, it can only do so 
%   along the axis of the sample line. Shearing can still occur between lines. 
%   Results are usually pretty garbled unless mask regions are individually convex.

if nargin==4
    mode=1;
end

if nargin==5
    fill='circular';
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
        disp('ROISHIFT: dim 3 of images must have size 1 or 3')
        return
    end
end

if isnumeric(fill) && numel(fill)~=cbg
    disp('ROISHIFT: RGB fill value must have same number of channels as INPICT')
    return
elseif ~isnumeric(fill) && ~(strcmpi(fill,'replicate') || strcmpi(fill,'circular'))
    disp('ROISHIFT: unknown fill type')
    return
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
                bsroi=circshift(bline(mline),[0 amt]);
                if numel(bsroi)>0
                    mr=numel(bsroi);
                    if strcmpi(fill,'replicate')
                        if amt>0
                            bsroi(1:min(amt,mr))=bsroi(mod(amt,mr)+1);
                        else
                            bsroi(max(end-(amt-1),1):end)=bsroi(mod(end-amt,mr));
                        end
                    elseif isnumeric(fill)
                        if amt>0
                            bsroi(1:min(amt,mr))=fill(c);
                        else
                            bsroi(max(end-(amt-1),1):end)=fill(c);
                        end
                    end

                    bline(mline)=bsroi;
                end
                outpict(m,:,c)=bline;
            end
        end
    else
        for c=1:1:cbg;
            for n=1:1:s(2);
                bline=inpict(:,n,c);
                mline=mask(:,n,c);
                bsroi=circshift(bline(mline),[amt 0]);
                if numel(bsroi)>0
                    mr=numel(bsroi);
                    if strcmpi(fill,'replicate')
                        if amt>0
                            bsroi(1:min(amt,mr))=bsroi(mod(amt,mr)+1);
                        else
                            bsroi(max(end-(amt-1),1):end)=bsroi(mod(end-amt,mr));
                        end
                    elseif isnumeric(fill)
                        if amt>0
                            bsroi(1:min(amt,mr))=fill(c);
                        else
                            bsroi(max(end-(amt-1),1):end)=fill(c);
                        end
                    end

                    bline(mline)=bsroi;
                end
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
                        bsroi=circshift(bline(starts(r):ends(r)),[0 amt]);
                        if numel(bsroi)>0
                            mr=numel(bsroi);
                            if strcmpi(fill,'replicate')
                                if amt>0
                                    bsroi(1:min(amt,mr))=bsroi(mod(amt,mr)+1);
                                else
                                    bsroi(max(end-(amt-1),1):end)=bsroi(mod(end-amt,mr));
                                end
                            elseif isnumeric(fill)
                                if amt>0
                                    bsroi(1:min(amt,mr))=fill(c);
                                else
                                    bsroi(max(end-(amt-1),1):end)=fill(c);
                                end
                            end

                            bline(starts(r):ends(r))=bsroi;
                        end
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
                        bsroi=circshift(bline(starts(r):ends(r)),[amt 0]);
                        if numel(bsroi)>0
                            mr=numel(bsroi);
                            if strcmpi(fill,'replicate')
                                if amt>0
                                    bsroi(1:min(amt,mr))=bsroi(mod(amt,mr)+1);
                                else
                                    bsroi(max(end-(amt-1),1):end)=bsroi(mod(end-amt,mr));
                                end
                            elseif isnumeric(fill)
                                if amt>0
                                    bsroi(1:min(amt,mr))=fill(c);
                                else
                                    bsroi(max(end-(amt-1),1):end)=fill(c);
                                end
                            end

                            bline(starts(r):ends(r))=bsroi;
                        end
                    end

                end
                
                outpict(:,n,c)=bline;
            end
        end
    end

end

return

    
























