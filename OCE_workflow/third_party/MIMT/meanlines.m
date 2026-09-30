function  outpict=meanlines(inpict,dim,rgb,mode)
%   MEANLINES(INPICT, DIM, RGB, {MODE})
%       returns an RGB image wherein all pixels in row or column vectors
%       have the mean, max, or min values in corresponding vectors of INPICT 
%       can be used for shading or shifting images
%
%   INPICT is an RGB image 
%   DIM is the dimension on which to sample
%       1 averages along rows
%       2 averages along columns
%   RGB controls whether color channels are averaged independently (1 or 0)
%       when RGB==0, image is greyscale
%   MODE accepts 'mean', 'max', or 'min' (default 'mean')
%       also accepts 'max y' and 'min y' which select extrema based on luma
%       when RGB==0, output from these modes corresponds to vector extrema of Y channel
%       when RGB==1, luma modes tend to make more visual sense since pixels are
%       selected as a whole; rgb mode selects extrema in a channel-independent fashion
%
%   Supports inputs of 'uint8','uint16', and 'double'
   
if nargin<4
    mode='mean';
end

s=size(inpict);
numchans=size(inpict,3);
[inpict inclass]=imcast(inpict,'double');

outpict=zeros(s);
switch lower(mode(mode~=' '))
    case'mean'
        if dim==1
            for c=1:numchans
                for m=1:1:s(1);
                    outpict(m,:,c)=mean(inpict(m,:,c));
                end
            end
        elseif dim==2    
            for c=1:numchans
                for n=1:1:s(2);
                    outpict(:,n,c)=mean(inpict(:,n,c));
                end
            end
        end

        % if not in rgb mode, average across channels
        if rgb~=1 
            outpict=repmat(mean(outpict,3),[1 1 3]);
        end
    case 'max'
            if dim==1
            for c=1:numchans
                for m=1:1:s(1);
                    outpict(m,:,c)=max(inpict(m,:,c));
                end
            end
        elseif dim==2    
            for c=1:numchans
                for n=1:1:s(2);
                    outpict(:,n,c)=max(inpict(:,n,c));
                end
            end
        end

        % if not in rgb mode, maximize across channels
        if rgb~=1 
            outpict=repmat(max(outpict,3),[1 1 3]);
        end
    case 'min'
        if dim==1
            for c=1:numchans
                for m=1:1:s(1);
                    outpict(m,:,c)=min(inpict(m,:,c));
                end
            end
        elseif dim==2    
            for c=1:numchans
                for n=1:1:s(2);
                    outpict(:,n,c)=min(inpict(:,n,c));
                end
            end
        end

        % if not in rgb mode, minimize across channels
        if rgb~=1 
            outpict=repmat(min(outpict,3),[1 1 3]);
        end
    case 'maxy'
		if numchans~=3
			error('MEANLINES: luma modes require a 3-channel image')
		end
        luma=mono(inpict,'y');
        if rgb==1 
            if dim==1
                for m=1:1:s(1);
                    [~, idx]=max(luma(m,:));
                    outpict(m,:,:)=repmat(inpict(m,idx,:),[1 s(2) 1]);
                end
            elseif dim==2    
                for n=1:1:s(2);
                    [~, idx]=max(luma(:,n));
                    outpict(:,n,:)=repmat(inpict(idx,n,:),[s(1) 1 1]);
                end
            end
        else
            if dim==1
                for m=1:1:s(1);
                    [~, idx]=max(luma(m,:));
                    luma(m,:)=repmat(luma(m,idx),[1 s(2)]);
                end
            elseif dim==2    
                for n=1:1:s(2);
                    [~, idx]=max(luma(:,n));
                    luma(:,n)=repmat(luma(idx,n),[s(1) 1]);
                end
            end
            outpict=repmat(luma,[1 1 3]);
        end
        case 'miny'
		if numchans~=3
			error('MEANLINES: luma modes require a 3-channel image')
		end
        luma=mono(inpict,'y');
        if rgb==1 
            if dim==1
                for m=1:1:s(1);
                    [~, idx]=min(luma(m,:));
                    outpict(m,:,:)=repmat(inpict(m,idx,:),[1 s(2) 1]);
                end
            elseif dim==2    
                for n=1:1:s(2);
                    [~, idx]=min(luma(:,n));
                    outpict(:,n,:)=repmat(inpict(idx,n,:),[s(1) 1 1]);
                end
            end
        else
            if dim==1
                for m=1:1:s(1);
                    [~, idx]=min(luma(m,:));
                    luma(m,:)=repmat(luma(m,idx),[1 s(2)]);
                end
            elseif dim==2    
                for n=1:1:s(2);
                    [~, idx]=min(luma(:,n));
                    luma(:,n)=repmat(luma(idx,n),[s(1) 1]);
                end
            end
            outpict=repmat(luma,[1 1 3]);
        end
    otherwise
        error('MEANLINES: invalid mode')
end

outpict=imcast(outpict,inclass);
    
return
