function matcharray=multimask(inpict,mode,bound,compmode)
%   MULTIMASK(INPICT, MODE, BOUND, {BOOLMODE})
%       returns a 2-D logical map of all pixels in INPICT specified via
%       corner colors and using relational and boolean operations.
%
%   INPICT is a 3-channel image array (m x n x 3)
%       if INPICT is 4-D (m x n x 3 x k), mask is 4-D (m x n x 1 x k)
%   BOUND is an array specifying boundary colors
%       rows are 3-element color vectors
%   MODE is a single string or a cell array of strings corresponding to BOUND
%       'eq', 'ne', 'lt', 'gt', 'le', 'ge'
%   COMPMODE specifies how matches should be logically compared
%       'not' is valid only if a single boundary is specified, otherwise
%       'and', 'or', 'xor', 'nand', 'nor', 'xnor' are available (default AND)
%
%   relational matching corresponds to an AND match on all channels.
%   i.e. for MODE = 'lt' and BOUND = [10 70 50], pixel values must lie 
%   within the rectangular prism in the color space with opposing corners 
%   on [0 0 0] and [10 70 50].  In this sense 'le' and 'gt' are not
%   complementary, and their sum does not fill the color space.
%
%   EX: 
%   multimask(A,{'ge','lt'},[10 10 10; 20 20 20],'xor')

if nargin==3
    compmode='and';
end

if ischar(mode)
    mode={mode};
end

tests=size(bound,1);
if tests~=max(size(mode))
    disp('MULTIMASK: BOUND and MODE size mismatch')
    return 
end

if strcmpi(compmode,'not') && tests>1
    disp('MULTIMASK: use ''nand'' instead of ''not'' for the union of negated matches')
    return 
end

numframes=1;
s=size(inpict);
if numel(s)==4
    numframes=s(4);
end

if strcmpi(compmode,'not') || strcmpi(compmode,'nor') || ...
        strcmpi(compmode,'nand') || strcmpi(compmode,'xnor')
    negated=1;
else
    negated=0;
end

matcharray=zeros([s(1:2) 1 numframes],'uint8');
for fr=1:1:numframes;
    for n=1:1:tests;
        % this will return a mxnx1 array
        thismatch=findpixels(inpict(:,:,:,fr),bound(n,:),char(mode(n)));

        if  tests==1
            matches=thismatch;
        elseif n==1
            matches=thismatch;
        else
            switch lower(compmode)
                case {'and','nand'}
                    matches=thismatch & matches;
                case {'or','nor'}
                    matches=thismatch | matches;
                case {'xor','xnor'}
                    matches=xor(thismatch, matches);
                otherwise  %default is AND
                    matches=thismatch & matches;
            end
        end
    end

    if negated==1;
        matches=~matches;
    end
    
    matcharray(:,:,1,fr)=matches;    

end

matcharray=logical(matcharray);

return







