function outpict=fourdee(fhandle,varargin)
%   FOURDEE(FHANDLE, ARG1, ARG2...)
%       generic tool for using rgb image processing functions
%       on 4-D image sets.  Only works if first argument is a 4D array.
%
%   FHANDLE is a function handle (e.g. @imresize)
%   ARGS are the arguments to be passed to the function specified by FHANDLE

numframes=size(varargin{1},4);

for f=1:1:numframes;
   outpict(:,:,:,f)=fhandle(varargin{1}(:,:,:,f),varargin{2:end});
end

return




















