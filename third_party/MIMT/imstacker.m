function outpict=imstacker(varargin)
% PICTSTACK = IMSTACKER(PICTARRAY,{OPTIONS})
%    Build a 4-D image array from a cell array of images.  
%    Images do not need to be of same geometry or datatype;
%    they may also differ in the number of channels (including transparency).
%    Single-frame and multiframe images can be mixed.
%    IMSTACKER and MIMREAD essentially replace BATCHLOADER for general multifile image import.
%
% PICTARRAY is a cell array containing multiple images
%    All standard image classes are supported
%    Indexed images are not supported
%
% OPTIONS are key-value pairs and keys including:
%    GRAVITY specifies how images should be aligned with each other (default 'center')
%       Valid strings and abbreviations include:
%          'center','north','south','east','west','northeast','northwest','southeast','southwest'
%          'c','n','s','e','w','ne','nw','se','sw'
%       e.g. 'nw' aligns the top and left edges of all images
%            's' aligns the bottom edges and centers horizontally
%
%    SIZE specifies the output image size (default 'max')
%       This may be explicitly set with a 2-element vector 
%       Or this may be implicitly set with one of the following:
%          'min' uses the smallest horizontal and vertical dimensions among input images
%          'max' uses the largest horizontal and vertical dimensions among input images
%          'first' uses the dimensions of the first image
%          'last' uses the dimensions of the last image
%
%    FIT describes how mismatched geometry should be resolved (default 'rigid')
%       'rigid' merely crops or pads as needed; no scaling is performed.
%          Using 'max' or 'min' SIZE with 'rigid' is equivalent to 'union' or 'intersection'
%       'circumscribe' will scale each image to fill SIZE, cropping any excess
%       'inscribe' will scale each image to fit within SIZE, padding any gaps
%
%    INTERPOLATION applies to FIT modes which use scaling (default 'bicubic')
%       Supported methods:
%          'bicubic','bilinear','nearest','lanczos2','lanczos3'
%
%    OFFSET allows for image offsets when using 'rigid' FIT (default [0 0])
%       This is a 1x2 or numel(PICTARRAY)x2 vector specifying vertical and horizontal
%       offsets in pixels.  If a single vector is provided, it will be applied to all images.
%
%    OUTCLASS specifies the output class (default 'double')
%       Supported types:
%          'double','single','uint8','uint16','int16','logical'
%
%    PADDING specifies the color/transparency of any padded image areas (default [0 0])
%       This may be a 1-4 element vector (I/IA/RGB/RGBA)
%       The color values in PADDING should be scaled to match the class of PADDING.
%          i.e. if PADDING is of the default class 'double', expected range is [0 1].
%       PADDING has the ability to force expansion of the output array.
%          e.g. Using [0 0 0 1] will force RGBA output even if importing only 1-channel images.
%       Similarly, an underspecified PADDING will be expanded if required by imported images.
%          e.g. Using [0 1] and importing 3-channel images will expand PADDING to [0 0 0 1]
%
%    VERBOSE will cause the list of file paths and other image information to be dumped to console.
%
%    QUIET will suppress any non-terminal warnings when invalid images are encountered.
%
% EXAMPLE:
%    Load a bunch of images;
%       pictarray=mimread('sources',{'ban*','*bars*','table*'},'verbose');
%    Use IMSTACKER to read and organize everything into a 4D stack:
%       pictstack=imstacker(pictarray,'gravity','nw','size','max','fit','rigid','interpolation',...
%                  'bicubic','outclass','uint8','padding',[0.2 0 0.5 0.8],'verbose');
%
%
% See also: mimread, batchloader, imread, gifread, imfinfo


gravitystrings={'c','n','s','e','w','ne','nw','se','sw',...
	'center','north','south','east','west','northeast','northwest','southeast','southwest'};
gravity='center';
outsizestrings={'first','last','min','max'}; % may also be a vector
outsize='max';
fitstrings={'rigid','inscribe','circumscribe'};
fit='rigid';
interpolationstrings={'bicubic','bilinear','nearest','lanczos2','lanczos3'};
interpolation='bicubic';
outclassstrings={'double','single','uint8','uint16','int16','logical'};
outclass='double';
offset=[0 0];
verbosity='normal';
padding=[0 0];
wclass='double';
inbucket={};


k=1;
while k<=numel(varargin)
	thiskey=varargin{k};
	if iscell(thiskey)
		inbucket=thiskey;
		k=k+1;
	elseif ischar(thiskey)
		switch lower(thiskey)
			case 'gravity'
				if ismember(varargin{k+1},gravitystrings)
					gravity=varargin{k+1};
					k=k+2;
				else
					error('IMSTACKER: unknown string for GRAVITY')
				end			
			case 'size'
				thisval=varargin{k+1};
				if isnumeric(thisval)
					if numel(thisval)==2
						outsize=thisval;
						k=k+2;
					else
						error('IMSTACKER: if specified explicitly, SIZE must be a 2-element vector')
					end
				elseif ismember(thisval,outsizestrings)
					% this needs to be resolved later
					outsize=thisval;
					k=k+2;
				else
					error('IMSTACKER: unknown string for SIZE')
				end
			case 'fit'
				if ismember(varargin{k+1},fitstrings)
					fit=varargin{k+1};
					k=k+2;
				else
					error('IMSTACKER: unknown string for FIT')
				end		
			case 'padding'
				thisval=varargin{k+1};
				if isnumeric(thisval)
					if any(numel(thisval)==[1 2 3 4])
						padding=imcast(thisval,'double');
						k=k+2;
					else
						error('IMSTACKER: PADDING must be a tuple of length 1 to 4')
					end
				elseif ischar(thisval)
					error('IMSTACKER: PADDING must be numeric')
				end
			case 'interpolation'
				if ismember(varargin{k+1},interpolationstrings)
					interpolation=varargin{k+1};
					k=k+2;
				else
					error('IMSTACKER: unknown string for INTERPOLATION')
				end	
			case 'outclass'
				if ismember(varargin{k+1},outclassstrings)
					outclass=varargin{k+1};
					k=k+2;
				else
					error('IMSTACKER: unknown string for OUTCLASS')
				end	
			case 'offset'
				thisval=varargin{k+1};
				if isnumeric(thisval)
					if any(size(thisval,1)==[1 numel(inbucket)])
						if size(thisval,2)==2
							offset=thisval;
							k=k+2;
						else
							error('IMSTACKER: OFFSET must be a 1x2 or Nx2 array')
						end
					else
						error('IMSTACKER: dim 1 of offset does not match number of images')
					end
				elseif ischar(thisval)
					error('IMSTACKER: OFFSET must be numeric')
				end
			case 'verbose'
				verbosity='verbose';
				k=k+1;
			case 'quiet'
				verbosity='quiet';
				k=k+1;
			otherwise
				error('IMSTACKER: unknown key %s',varargin{k})
		end
	else
		error('IMSTACKER: invalid key %d',k)
	end
end

if isempty(inbucket)
	error('IMSTACKER: no images found.  Either you didn''t specify an array, or the array is empty')
end

% abbreviate gravity strings for sanity
if ismember(gravity,{'center','north','south','east','west','northeast','northwest','southeast','southwest'})
	switch gravity
		case 'center'
			gravity='c';
		case 'north'
			gravity='n';
		case 'south'
			gravity='s';
		case 'east'
			gravity='e';
		case 'west'
			gravity='w';
		case 'northeast'
			gravity='ne';
		case 'northwest'
			gravity='nw';
		case 'southeast'
			gravity='se';
		case 'southwest'
			gravity='sw';
	end
end
	


% READ INPUT ARRAY %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

numpicts=numel(inbucket);
sizetable=ones(numpicts,4);
for p=1:numpicts
	sizetable(p,:)=[size(inbucket{p},1) size(inbucket{p},2) size(inbucket{p},3) size(inbucket{p},4)];
end

if strcmp(verbosity,'verbose')
	fprintf('\nINPUT SIZE TABLE:\n')
	sizetable
	fprintf('\nNUMBER OF VALID IMAGES: %d\n',numpicts)
end



% PREP STACK BUILD %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% calculate outsize if implicit (min/max/top/bot)
if ~isnumeric(outsize)
	switch lower(outsize)
		case 'min'
			outsize=min(sizetable(:,1:2),[],1);
		case 'max'
			outsize=max(sizetable(:,1:2),[],1);
		case 'first'
			outsize=sizetable(1,1:2);
		case 'last'
			outsize=sizetable(end,1:2);
	end
end

% padding is cast to double, but may have never been cast correctly!
% clean up any uintX-scaled specs cast as double
if any(padding>2) && all(padding<=255) % uint8
	padding=padding/255;
elseif any(padding>255) % uint16
	padding=padding/65535;
end
padding=imcast(padding,wclass);

% calculate appropriate number of ouput channels
st_alpha = ~mod(sizetable(:,3),2);
st_color = sizetable(:,3)-st_alpha;
pd_alpha = ~mod(numel(padding),2);
pd_color = numel(padding)-pd_alpha;
numoutchans = max(max(st_color),pd_color) + (any(st_alpha) || pd_alpha);

% does padding need to be expanded?
numpadchans=numel(padding);
if numpadchans~=numoutchans
	% does padding need alpha added?
	if mod(numpadchans,2) && ~mod(numoutchans,2)
		padding=cat(2,padding,ones(size(padding(1))));
	end
	numpadchans=numel(padding);

	% does padding need to be expanded?
	if numpadchans==1 && numoutchans==3
		padding=repmat(padding(1),[1 3 1]);
	elseif numpadchans==2 && numoutchans==4
		padding=cat(2,repmat(padding(1),[1 3 1]),padding(2));
	end
end

% expand offset if needed
if size(offset,1)~=numpicts
	offset=repmat(offset(1,:),[numpicts,1]);
end



% BUILD STACK %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% working image class should be double to avoid losses with scaling
% and to simplify casting of padding
outpict=zeros([outsize numoutchans sum(sizetable(:,4))],outclass);

if strcmp(verbosity,'verbose')
	fprintf('CALCULATED PADDING: %s\n',mat2str(imcast(padding,outclass)))
	fprintf('CALCULATED OFFSET: %s\n',mat2str(offset))
	fprintf('OUTPUT IMAGE SIZE: %s\n',mat2str([outsize numoutchans sum(sizetable(:,4))]))
	switch outclass
		case 'double'
			bypel=8;
		case 'single'
			bypel=4;
		case {'uint16','int16'}
			bypel=2;
		case {'uint8','logical'}
			bypel=1;
	end
	fprintf('MEMORY USED BY OUTPUT IMAGE: %1.2f MB\n',bypel*numel(outpict)/1E6)
end

fidx=1;
for p=1:numpicts
	% image class needs to be adapted to working image class
	thispict=imcast(inbucket{p},wclass);
	
	% image channels need to be made to fit outpict
	numthischans=size(thispict,3);
	if numthischans~=numoutchans
		% does image need alpha added?
		if mod(numthischans,2) && ~mod(numoutchans,2) 
			thispict=cat(3,thispict,ones(size(thispict(:,:,1,:))));
		end
		numthischans=size(thispict,3);
		
		% does image need to be expanded?
		if numthischans==1 && numoutchans==3
			thispict=repmat(thispict(:,:,1),[1 1 3]);
		elseif numthischans==2 && numoutchans==4
			thispict=cat(3,repmat(thispict(:,:,1),[1 1 3]),thispict(:,:,2));
		end
	end
	
	thissize=[size(thispict,1) size(thispict,2) size(thispict,3) size(thispict,4)];
	
	
	if strcmp(fit,'rigid')
		for f=1:thissize(4)
			thisframe=thispict(:,:,:,f);
			
			% pad/crop for offsets
			if offset(p,1)>0
				switch gravity	
					case {'c','e','w'} % pad n edge x2
						padblock=bsxfun(@times,ones([offset(p,1)*2 thissize(2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
						thisframe=cat(1,padblock,thisframe);
					case {'n','ne','nw'} % pad n edge
						padblock=bsxfun(@times,ones([offset(p,1) thissize(2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
						thisframe=cat(1,padblock,thisframe);
					case {'s','se','sw'} % crop s edge
						thisframe=thisframe(1:end-offset(p,1),:,:);
				end
			elseif offset(p,1)<0
				switch gravity	
					case {'c','e','w'} % pad s edge x2
						padblock=bsxfun(@times,ones([-offset(p,1)*2 thissize(2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
						thisframe=cat(1,thisframe,padblock);
					case {'n','ne','nw'} % crop n edge
						thisframe=thisframe(-offset(p,1)+1:end,:,:);
					case {'s','se','sw'} % pad s edge
						padblock=bsxfun(@times,ones([-offset(p,1) thissize(2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
						thisframe=cat(1,thisframe,padblock);
				end
			end
			thissize(1)=size(thisframe,1);
			thissize(2)=size(thisframe,2);
			
			if offset(p,2)>0 
				switch gravity	
					case {'c','n','s'} % pad w edge x2
						padblock=bsxfun(@times,ones([thissize(1) offset(p,2)*2 numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
						thisframe=cat(2,padblock,thisframe);
					case {'w','nw','sw'} % pad w edge	
						padblock=bsxfun(@times,ones([thissize(1) offset(p,2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
						thisframe=cat(2,padblock,thisframe);
					case {'e','ne','se'} % crop e edge
						thisframe=thisframe(:,1:end-offset(p,2),:);
				end
			elseif offset(p,2)<0
				switch gravity	
					case {'c','n','s'} % pad e edge x2
						padblock=bsxfun(@times,ones([thissize(1) -offset(p,2)*2 numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
						thisframe=cat(2,thisframe,padblock);
					case {'w','nw','sw'} % crop w edge
						thisframe=thisframe(:,-offset(p,2)+1:end,:);
					case {'e','ne','se'} % pad e edge
						padblock=bsxfun(@times,ones([thissize(1) -offset(p,2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
						thisframe=cat(2,thisframe,padblock);
				end
			end
			thissize(1)=size(thisframe,1);
			thissize(2)=size(thisframe,2);
			
			% pad/crop to fit stack
			margins=abs(thissize(1:2)-outsize(1:2));
			if thissize(1)<outsize(1) % pad v
				switch gravity	
					case {'c','e','w'}
						padblock1=bsxfun(@times,ones([floor(margins(1)/2) thissize(2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
						padblock2=bsxfun(@times,ones([ceil(margins(1)/2) thissize(2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
						thisframe=cat(1,padblock1,thisframe,padblock2);
					case {'n','ne','nw'}
						padblock=bsxfun(@times,ones([margins(1) thissize(2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
						thisframe=cat(1,thisframe,padblock);
					case {'s','se','sw'}
						padblock=bsxfun(@times,ones([margins(1) thissize(2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
						thisframe=cat(1,padblock,thisframe);
				end
			elseif thissize(1)>outsize(1) % crop v
				switch gravity	
					case {'c','e','w'}
						thisframe=thisframe(floor(margins(1)/2)+1:end-ceil(margins(1)/2),:,:);
					case {'n','ne','nw'}
						thisframe=thisframe(1:outsize(1),:,:);
					case {'s','se','sw'}
						thisframe=thisframe(end-outsize(1)+1:end,:,:);
				end
			end
			
			if thissize(2)<outsize(2) % pad h
				switch gravity	
					case {'c','n','s'}
						padblock1=bsxfun(@times,ones([outsize(1) floor(margins(2)/2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
						padblock2=bsxfun(@times,ones([outsize(1) ceil(margins(2)/2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
						thisframe=cat(2,padblock1,thisframe,padblock2);
					case {'w','nw','sw'}	
						padblock=bsxfun(@times,ones([outsize(1) margins(2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
						thisframe=cat(2,thisframe,padblock);
					case {'e','ne','se'}
						padblock=bsxfun(@times,ones([outsize(1) margins(2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
						thisframe=cat(2,padblock,thisframe);
				end
			elseif thissize(2)>outsize(2) % crop h
				switch gravity	
					case {'c','n','s'}
						thisframe=thisframe(:,floor(margins(2)/2)+1:end-ceil(margins(2)/2),:);
					case {'w','nw','sw'}	
						thisframe=thisframe(:,1:outsize(2),:);
					case {'e','ne','se'}
						thisframe=thisframe(:,end-outsize(2)+1:end,:);
				end
			end

			outpict(:,:,:,fidx)=imcast(thisframe,outclass);
			fidx=fidx+1;
		end
		
	else % circumscribe/inscribe scaling
		thisar=thissize(1)/thissize(2);
		outar=outsize(1)/outsize(2);
		
		if thisar==outar
			for f=1:thissize(4)
				outpict(:,:,:,fidx)=imcast(imresize(thispict(:,:,:,f),outsize,interpolation),outclass);
				fidx=fidx+1;
			end
			
		elseif thisar<outar
			for f=1:thissize(4)
				thisframe=thispict(:,:,:,f);
				
				if strcmp(fit,'circumscribe')
					% crop right/left edges
					thisframe=imresize(thisframe,[outsize(1) NaN],interpolation);
					switch gravity
						case {'c','n','s'}
							margins=abs(size(thisframe,2)-outsize(2));
							thisframe=thisframe(:,floor(margins/2):end-ceil(margins/2)-1,:);
						case {'w','nw','sw'}
							thisframe=thisframe(:,1:outsize(2),:);
						case {'e','ne','se'}
							thisframe=thisframe(:,end-outsize(2)+1:end,:);
					end

				else % inscribe
					% pad top/bottom edges
					thisframe=imresize(thisframe,[NaN outsize(2)],interpolation);
					margins=outsize(1)-size(thisframe,1);
					switch gravity
						case {'c','e','w'}
							padblock1=bsxfun(@times,ones([floor(margins/2) outsize(2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
							padblock2=bsxfun(@times,ones([ceil(margins/2) outsize(2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
							thisframe=cat(1,padblock1,thisframe,padblock2);
						case {'n','ne','nw'}
							padblock=bsxfun(@times,ones([margins outsize(2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
							thisframe=cat(1,thisframe,padblock);
						case {'s','se','sw'}
							padblock=bsxfun(@times,ones([margins outsize(2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
							thisframe=cat(1,padblock,thisframe);
					end
				end		
			
				outpict(:,:,:,fidx)=imcast(thisframe,outclass);
				fidx=fidx+1;
			end
			
		elseif thisar>outar
			for f=1:thissize(4)
				thisframe=thispict(:,:,:,f);
			
				if strcmp(fit,'circumscribe')
					% crop top bottom edges
					thisframe=imresize(thisframe,[NaN outsize(2)],interpolation);
					switch gravity
						case {'c','e','w'}
							margins=abs(size(thisframe,1)-outsize(1));
							thisframe=thisframe(floor(margins/2):end-ceil(margins/2)-1,:,:);
						case {'n','ne','nw'}
							thisframe=thisframe(1:outsize(1),:,:);
						case {'s','se','sw'}
							thisframe=thisframe(end-outsize(1)+1:end,:,:);
					end

				else % inscribe
					% pad left/right edges
					thisframe=imresize(thisframe,[outsize(1) NaN],interpolation);
					margins=outsize(2)-size(thisframe,2);
					switch gravity
						case {'c','n','s'}
							padblock1=bsxfun(@times,ones([outsize(1) floor(margins/2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
							padblock2=bsxfun(@times,ones([outsize(1) ceil(margins/2) numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
							thisframe=cat(2,padblock1,thisframe,padblock2);
						case {'w','nw','sw'}
							padblock=bsxfun(@times,ones([outsize(1) margins numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
							thisframe=cat(2,thisframe,padblock);
						case {'e','ne','se'}
							padblock=bsxfun(@times,ones([outsize(1) margins numoutchans],wclass),reshape(padding,[1 1 numel(padding)]));
							thisframe=cat(2,padblock,thisframe);
					end
				end
				
				outpict(:,:,:,fidx)=imcast(thisframe,outclass);
				fidx=fidx+1;
			end
		end
	end
end

clear inbucket thispict thisframe

% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

end





























