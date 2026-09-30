function outpict=imfold(inpict,varargin)
% IMFOLD(INPICT,{SEQUENCE},{METHOD})
%    generate an image stack as if repeatedly fan-folding an image
%    
%
%    INPICT is an I/IA or RGB/RGBA image
%    SEQUENCE the intended fold sequence (cell array of strings)
%       the format for a single operation string is [N AXIS DIRECTION]
%         N is the number of folds to perform
%         AXIS along which the image is subdivided 'h' or 'v'
%         DIRECTION of the first fold 'u' or 'o' for under or over
%       EXAMPLE: {'3hu','2vo','1hu'}
%
%    METHOD specify how image size should be adjusted when tiling
%       since an image dimension cannot be evenly subdivided by all integers
%       'grow' replicates edge vectors to fit
%       'trim' deletes edge vectors to fit 
%       'fit' selects best of either 'grow' or 'trim' behaviors (default)
%       'scale' simply scales the image to fit
%           when using 'scale', the interpolation method can also be selected
%           'bicubic' (default), or 'nearest' are supported
%
%   NOTE:
%      if using large N and/or long SEQUENCE, it's easy to reduce an image
%      into a very deep stack of small frames.  The fact that the frames get 
%      small means that the artifacts caused by METHOD may be significant.
%


sequence={'1hu','1vu'};
method='fit';
interpolant='bicubic';
dim=2;
It=1;

for a=1:nargin-1
	if iscell(varargin{a})
		sequence=varargin{a};
	elseif ischar(varargin{a})
		key=lower(varargin{a});
		if ismember(key,{'fit','scale','grow','trim'})
			method=key;
		elseif ismember(key,{'bicubic','nearest'})
			interpolant=key;
		else
			error('IMFOLD: unknown key %s',key)
		end
	end
end

numops=numel(sequence);
inclass=class(inpict);

% to reduce accumulated error, use FP data if scaling with cont interpolant
if strcmp(method,'scale') && strcmp(interpolant,'bicubic')
	outpict=imcast(inpict,'double');
	recast=1;
else 
	outpict=inpict;
	recast=0;
end


for op=1:numops
	
	% PARSE OP STRING ====================================================
	thisop=sequence{op};
	Nf=str2double(thisop(1:end-2));
	Nt=Nf+1;

	ts=lower(thisop(end-1));
	switch ts
		case 'v'
			dim=1;
		case 'h'
			dim=2;
		otherwise
			error('IMFOLD: unknown axis %s in operation %s',ts,thisop)
	end

	ts=lower(thisop(end));
	if ismember(ts,{'u','o'})
		direction=ts;
	else
		error('IMFOLD: unknown direction %s in operation %s',ts,thisop)
	end
	
	
	% ADJUST DIMENSIONS ====================================================	
	s=[size(outpict,1) size(outpict,2)];
	Pgrow=Nt-mod(s(dim),Nt);
	if Pgrow~=Nt;
		Ptrim=Nt-Pgrow;
		
		%[s(dim) Nt mod(s(dim),Nt) s(dim)+Pgrow s(dim)-Ptrim]
		%[Pgrow Ptrim]
		if ismember(method,{'fit','grow','trim'})
			if Pgrow<=Ptrim || strcmp(method,'grow')
				% grow
				if dim==1
					outpict=cat(dim,repmat(outpict(1,:,:,:),[floor(Pgrow/2) 1 1 1]),...
						outpict,repmat(outpict(end,:,:,:),[ceil(Pgrow/2) 1 1 1]));
				else
					outpict=cat(dim,repmat(outpict(:,1,:,:),[1 floor(Pgrow/2) 1 1]),...
						outpict,repmat(outpict(:,end,:,:),[1 ceil(Pgrow/2) 1 1]));
				end
			else
				% trim
				if dim==1
					outpict=outpict(1+floor(Ptrim/2):end-ceil(Ptrim/2),:,:,:);
				else
					outpict=outpict(:,1+floor(Ptrim/2):end-ceil(Ptrim/2),:,:);
				end
			end
		else % scale
			[Pd idx]=min([Pgrow Ptrim]);
			if idx==1; Pd=Pgrow; else Pd=-Ptrim; end
			
			if dim==1
				outpict=fourdee(@imresize,outpict,[s(1)+Pd s(2)],interpolant);
			else
				outpict=fourdee(@imresize,outpict,[s(1) s(2)+Pd],interpolant);
			end
		end
	end
	
	
	% TILING & STACKING ====================================================
	if strcmp(direction,'u')
		index=1:1:Nt;
	else
		index=Nt:-1:1;
	end
	
	s=[size(outpict,1) size(outpict,2)];
	st=s(dim)/Nt; % this should be evenly divisible now, if it's not, adjustdims() is broken
	lastoutpict=outpict;
	for It=1:Nt;
		firstpx=1+(index(It)-1)*st;
		
		%[s(dim) Nt firstpx firstpx+st-1]
		if It==1
			if dim==1
				outpict=checkflip(lastoutpict(firstpx:firstpx+st-1,:,:,:));
			else
				outpict=checkflip(lastoutpict(:,firstpx:firstpx+st-1,:,:));
			end
		else
			if dim==1
				outpict=cat(4,outpict,checkflip(lastoutpict(firstpx:firstpx+st-1,:,:,:)));
			else
				outpict=cat(4,outpict,checkflip(lastoutpict(:,firstpx:firstpx+st-1,:,:)));
			end
		end
	end
end


if recast
	outpict=imcast(outpict,inclass);
end


% ====================================================
	function out=checkflip(tile)
		if ~mod(index(It),2)
			out=flipdim(tile,dim);
			out=flipdim(out,4);
		else
			out=tile;
		end
	end

end



