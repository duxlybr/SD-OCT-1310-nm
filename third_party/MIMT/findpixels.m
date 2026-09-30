function matches=findpixels(inpict,color,mode)
%   FINDPIXELS(INPICT, COLOR, MODE)
%       returns a 2-D logical map of all pixels in INPICT which match COLOR.
%
%   INPICT is a 3-channel image array (m x n x 3)
%       can also be a 4-D array of images (m x n x 3 x k)
%       when INPICT is 4-D, returned mask is 4-D
%   COLOR is a 3-element row vector
%   MODE is one of the typical equality or relational tests
%       'eq', 'ne', 'lt', 'gt', 'le', 'ge'
%
%   relational matching corresponds to an AND match on all channels.
%   i.e. for MODE = 'lt' and BOUND = [10 70 50], pixel values must lie 
%   within the rectangular prism in the color space with opposing corners 
%   on [0 0 0] and [10 70 50].  In this sense 'le' and 'gt' are not
%   complementary, and their sum does not fill the color space.

switch lower(mode)
    case 'eq'
        matches=all(bsxfun(@eq,inpict,reshape(color,[1 1 3])),3);
    case 'ne'
        matches=all(bsxfun(@ne,inpict,reshape(color,[1 1 3])),3);
    case 'lt'
        matches=all(bsxfun(@lt,inpict,reshape(color,[1 1 3])),3);
    case 'gt'
        matches=all(bsxfun(@gt,inpict,reshape(color,[1 1 3])),3);
    case 'le'
        matches=all(bsxfun(@le,inpict,reshape(color,[1 1 3])),3);
    case 'ge'
        matches=all(bsxfun(@ge,inpict,reshape(color,[1 1 3])),3);
    otherwise
        disp('FINDPIXELS: no valid mode specified')
end

return