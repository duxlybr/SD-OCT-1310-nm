function outpict=randlines(size,dim,threshold,rgb,mode,rate)
%   RANDLINES(SIZE, DIM, SPARSITY, RGB, {MODE}, {RATE})
%       generates image fields of random lines of various type
%
%   SIZE is a vector specifying the output image dimensions 
%   DIM is the dimension on which to sample
%       1 produces horizontal stripes
%       2 produces vertical stripes
%   SPARSITY increases threshold before displacement occurs (0 to 1)
%   RGB controls whether color channels are averaged independently (1 or 0)
%       when RGB==0, image is greyscale
%   MODE specifies the style of output (default is 'normal')
%       'normal' sets each line to a random value from 0-255
%       'walks' does a random walk when setting line values
%           accepts additional argument RATE
%       'ramps' creates some goofy ramps of random length
%           accepts additional argument RATE
%           SPARSITY has no effect in 'ramps' mode
%   RATE is used with optional modes to set the rate at which the walk
%       or the ramp progresses locally.  A large rate will result in either
%       a clipped walk or short ramps.  Value is normalized WRT internal default.


if nargin<5
    mode='normal';
end

s=size;
whiteval=255;
if strcmpi(mode,'normal')
    if rgb==1
        if dim==1
            outpict=repmat(rand([s(1) 1 3]),[1 s(2) 1]);
        elseif dim==2
            outpict=repmat(rand([1 s(2) 3]),[s(1) 1 1]);
        end    
    else
        if dim==1
            outpict=repmat(rand([s(1) 1 1]),[1 s(2) 3]);
        elseif dim==2
            outpict=repmat(rand([1 s(2) 1]),[s(1) 1 3]);
        end   
    end

    if threshold~=0;
        outpict=max(outpict-threshold,0)./(1-threshold);
    end
    
    
elseif strcmpi(mode,'walks')
    if nargin<6
        rate=1;
    end
    rate=rate*0.05;
    
    if rgb==1
        if dim==1
            stripe=rand([s(1) 1 3])-0.5;
            stripe(abs(stripe)<=threshold/2)=0;
            stripe=cumsum(stripe*rate)+0.5;
            outpict=repmat(stripe,[1 s(2) 1]);
        elseif dim==2
            stripe=rand([1 s(2) 3])-0.5;
            stripe(abs(stripe)<=threshold/2)=0;
            stripe=cumsum(stripe*rate)+0.5;
            outpict=repmat(stripe,[s(1) 1 1]);
        end    
    else
        if dim==1
            stripe=rand([s(1) 1 1])-0.5;
            stripe(abs(stripe)<=threshold/2)=0;
            stripe=cumsum(stripe*rate)+0.5;
            outpict=repmat(stripe,[1 s(2) 3]);
        elseif dim==2
            stripe=rand([1 s(2) 1])-0.5;
            stripe(abs(stripe)<=threshold/2)=0;
            stripe=cumsum(stripe*rate)+0.5;
            outpict=repmat(stripe,[s(1) 1 3]);
        end   
    end

    
elseif strcmpi(mode,'ramps')
    % this code could probably be compacted or faster, but wtfe
    % this is really arbitrary junk from an ad-hoc script
    if nargin<6
        rate=1;
    end
    rate=rate*0.01;
    
    minlength=1;
    if rgb==0
        if dim==1
            outpict=zeros(s(1:2))';
        elseif dim==2
            outpict=zeros(s(1:2));
        end
        
        for n=1:1:prod(s(1:2));
            k=rand(); % this was originally set outside the loop
            if n==1, m=1; else m=n-1; end

            %if outpict(m)>=(minlength+rand()*(1-minlength))
            if outpict(m)>=randrange([minlength 1]);
                continue;
            elseif k >= 0.95
                outpict(n)=outpict(m)+5*rate;
            elseif k >= 0.8
                outpict(n)=outpict(m)+3*rate;
            else
                outpict(n)=outpict(m)+1*rate; 
            end

        end
        
        if dim==1
            outpict=outpict';
        end
        outpict=repmat(outpict,[1 1 3]);
    else
        outpict=zeros(s);
        for c=1:1:3;
            wpict=randlines(s,dim,threshold,0,'ramps',rate/0.01);
            outpict(:,:,c)=double(wpict(:,:,1))/whiteval;
        end
    end
end

outpict=uint8(outpict*whiteval);

return

















