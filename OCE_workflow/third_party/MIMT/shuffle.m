function outpict=shuffle(inpict,tiles,lockrgb,perms)
%   SHUFFLE(INPICT, TILES, {LOCKRGB}, {PERMUTATIONS})
%       subdivides the input image into tiles and shuffles
%       them in a random or specified permutation
%
%   INPICT is a 2-D, 3-D, or 4-D image
%   TILES is a 2-element vector specifying the number of tiles
%       [tilesdown tilesacross]
%   LOCKRGB specifies whether the color channels are permuted independently
%       0 results in channels being shuffled independently
%       1 (default) shuffles all channels at once
%   PERMUTATIONS is an array specifying the desired tile permutation
%       By default, this array is randomly generated internally, but can
%       be specified if repeatability or specific behavior is required.
%       Elements are linear indices specifying the destination of tiles as they 
%       are to be moved in a grid of size=TILES.
%       each row vector of PERMUTATIONS is of length=prod(TILES)
%       if LOCKRGB==0, 3 rows are required to permute each of 3 channels
%       if LOCKRGB==1, only 1 row is needed, as all channels are permuted at once
%
%   EXAMPLE:
%       outpict=shuffle(inpict,[30 30],1,900:-1:1);
%       (flips tile order)

if nargin==2
    lockrgb=1;
end

if lockrgb==0;
    if size(inpict,3)~=3
        disp('SHUFFLER: cannot use LOCKRGB=0 on a single-channel image')
        return
    end
    indc=3;
else 
    indc=1;
end

% if we're given a permutation array, check it
% otherwise generate as many permutations as we need
if nargin==4
    if any(size(perms)~=[indc prod(tiles)])
        disp(sprintf('SHUFFLER: permutation array must have dim [C prod(tiles)]\n\twhere C is 1 or 3 depending on LOCKRGB'))
        expected_size=[indc prod(tiles)]
        specified_size=size(perms)
        return
    end
else
    perms=[];
    for c=1:indc;
        perms=cat(1,perms,randperm(prod(tiles)));
    end
end

% temporarily resize to closest multiple
s=size(inpict);
newsize=ceil(s(1:2)./tiles).*tiles;
if size(inpict,4)~=1
    inpict=fourdee(@imresize,inpict,newsize);
else
    inpict=imresize(inpict,newsize);
end

cw=round(newsize(1:2)./tiles);
[mm nn]=meshgrid(1:tiles(1),1:tiles(2));

outpict=zeros([newsize size(inpict,3) size(inpict,4)],'uint8');
for c=1:indc;
    rMN=perms(c,:); % new permutation for each channel
    for f=1:1:size(inpict,4);
        for m=1:tiles(1);
            for n=1:tiles(2);
                ri=(cw(1)*(m-1)+1):(cw(1)*m);
                ci=(cw(2)*(n-1)+1):(cw(2)*n);

                thistile=(m-1)*tiles(2)+n; % a linear index
                M=mm(rMN(thistile));
                N=nn(rMN(thistile));

                ro=(cw(1)*(M-1)+1):(cw(1)*M);
                co=(cw(2)*(N-1)+1):(cw(2)*N);

                numc=size(inpict,3);
                outpict(ri,ci,c*(1:numc/indc),f)=inpict(ro,co,c*(1:numc/indc),f);
            end
        end
    end
end

% resize back to original dimensions
if size(inpict,4)~=1
    outpict=fourdee(@imresize,outpict,s(1:2));
else
    outpict=imresize(outpict,s(1:2));
end

return



