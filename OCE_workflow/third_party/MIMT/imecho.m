function outpict=imecho(inpict,nechoes,mode,skip,offset,option)
%   IMECHO(INPICT, NECHOES, MODE, {SKIP}, {OFFSET}, {OPTION})
%       blends delayed frame copies with an image animation
%
%   INPICT is a 4-D image array
%   NECHOES is the number of frames over which the delays should occur
%   MODE is an image blend mode string (see IMBLEND())
%   SKIP specifies the number of frames sample spacing (default 1)
%   OFFSET is a 3-element row vector specifying frame offsets per channel
%       (default [0 0 0])
%   OPTION specifies an optional operational mode (default 'normal')
%       'difference' causes blend operations to occur on the difference of frames
%       'blocks' causes trailing frames to be spatially downsampled
%       'diffblocks' is the same as 'difference', but with downsampling 
%
%   EX:
%   imecho(pict,4,'multiply',2)
%       blends 4 copies of PICT, each offset by 2 frames (every other)

if nargin<6
    option='normal';
end
if nargin<5
    offset=[0 0 0];
end
if nargin<4
    skip=1;
end

skip=max(skip,1);
offset=round(offset);
nframes=size(inpict,4);
wpict=inpict;

if strcmpi(option,'normal');
    for n=1:1:nechoes;
        wpict=imblend(wpict,circshift(inpict, ...
            [0 0 0 mod(nechoes-(n*skip),nframes)]),(1-1/nechoes),mode);
    end
elseif strcmpi(option,'difference');
    for n=1:1:nechoes;
        dpict=imblend(wpict,circshift(inpict, ...
            [0 0 0 mod(nechoes-(n*skip),nframes)]),1,'difference');
        wpict=imblend(wpict,dpict,(1-1/nechoes),mode);
    end
elseif strcmpi(option,'blocks');
    for n=1:1:nechoes;
        dpict=circshift(inpict,[0 0 0 mod(nechoes-(n*skip),nframes)]);
        dpict=blockify(dpict,[1 1 1]*2*(nechoes-n+1));
        wpict=imblend(wpict,dpict,(1-1/nechoes),mode);
    end
elseif strcmpi(option,'diffblocks')
    for n=1:1:nechoes;
        dpict=imblend(wpict,circshift(inpict, ...
            [0 0 0 mod(nechoes-(n*skip),nframes)]),1,'difference');
        dpict=blockify(dpict,[1 1 1]*2*(nechoes-n+1));
        wpict=imblend(wpict,dpict,(1-1/nechoes),mode);
    end
end

if sum(abs(offset))>0;
    for c=1:1:3;
        wpict(:,:,c,:)=circshift(wpict(:,:,c,:),[0 0 0 offset(c)]);
    end
end
outpict=wpict;

return














