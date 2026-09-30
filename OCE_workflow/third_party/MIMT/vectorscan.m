function wpict=vectorscan(inpict,numlines,scanamp,varargin)
%   OUTPICT=VECTORSCAN(INPICT, NUMLINES, AMPLITUDE, {OPTIONAL PARAMS})
%       Loosely emulates the appearance of a scan processor output on a
%       monochrome display with persistence.  Vertical deflection and beam intensity
%       are modulated by input image luminance.  Includes optional noise
%       parameters and scan decay to mimic an asynchronous camera capture.
%       Can operate on single images or 4-D sequences. 
%        
%   INPICT is a single image or a 4-D image sequence. 
%       RGB images are flattened by extracting a luma channel
%       Output image has same number of frames (dim 4) as INPICT
%       Output aspect ratio is not the same as the input aspect ratio
%       due to the fact that height is increased to accomodate line amplitude
%       If the user is okay with edge clipping, just use IMCROP() as desired.
%   NUMLINES is the number of scan lines in each output field
%   AMPLITUDE is the maximum vertical amplitude (relative to image height)
%   SRAD is the radius used for input smoothing (default = 4)
%   LINESCALE is the maximum line width (default = 4)
%   LINECOLOR is the line color for the output (default is [0 1 0.6])
%   BLOOM (0 or 1) toggles highlight emphasis (default is 1)
%   NOISEAMP is the amplitude of superimposed noise (relative to max signal amp)
%       (default is 0.01)
%   NOISESPAR noise sparsity. 0 is uniformly noisy, whereas values near 1
%       result in occasional spikes (default is 0.999)
%   JITTER line jitter relative to maximum signal amplitude (default is 0.02)
%   DECAYAMT amount by which scan decays per field (default is 0.3)
%   OUTSCALE output scaling WRT input dimensions. 0 for maximum available
%       (default is 1)

% Tested on R2009b and R2015b under linux.  
% The rendering method is crude and relies on figure capture and many calls to line().  
% Performance is absurdly worse in R2015b due to changes to line() and getframe()
% I think the only way to fix this retarded thing is to stop using line() like an idiot.

% defaults
srad=4;
linescale=4;
linecolor=imtweak([0 1 0],'hsv',[1/10 1 1]);
bloom=1; 
noiseamp=0.01;
noisespar=0.999;
jitter=0.02;
decayamt=0.3;
outscale=1; 

numlines=round(numlines);

for k=1:2:length(varargin);
    switch lower(varargin{k})
        case 'srad'
            srad=varargin{k+1};
        case 'linescale'
            linescale=varargin{k+1};
        case 'linecolor'
            linecolor=varargin{k+1};
        case 'bloom'
            bloom=varargin{k+1};
        case 'noiseamp'
            noiseamp=varargin{k+1};
        case 'noisespar'
            noisespar=varargin{k+1};
        case 'jitter'
            jitter=varargin{k+1};
        case 'decayamt'
            decayamt=varargin{k+1};
        case 'outscale'
            outscale=varargin{k+1};
        otherwise
            disp(sprintf('VECTORSCAN: unknown input parameter name %s',varargin{k}))
            return
    end
end

hstep=1;    % horizontal step size (px)
s=size(inpict);
hscale=s(1)*scanamp;
vstep=round(s(1)/numlines);
linecolor=1-linecolor;

% figure window is maximized to get largest rendering area 
% captured image will be resized back to appropriate geometry
figure(1)
set(gcf,'Units','normalized','Position',[0,0,1,1],'visible','off');
axes('position',[0 0 1 1]);

for f=1:1:size(inpict,4);
    if size(inpict,3)==3
        luma=mono(inpict(:,:,:,f),'y'); 
    elseif size(inpict,3)==1
        luma=inpict(:,:,:,f);
    end
    luma=flipud(imcast(luma,'double'));
    h=fspecial('disk',srad);
    luma=imfilter(luma,h);
	
    % create scaling ramp to simulate redraw async
    allsteps=s(1)*(s(2)-hstep);
    scanramp=(1-decayamt)+decayamt*(1:1:allsteps)/(allsteps);
    scanramp=circshift(fliplr(scanramp),round([0 -f*allsteps*0.3]));

    for row=1:vstep:s(1);
        % create noise vector for each row
        rownoise=rand(1,s(2))-1/2;
        nmask=rownoise>-noisespar/2 & rownoise<noisespar/2;
        rownoise(nmask)=0;
        rownoise(~nmask)=rownoise(~nmask)*hscale*noiseamp*2;
        rowoffset=jitter*hscale*(rand()-1/2); % offset per line
        
        for col=1:hstep:s(2)-hstep;
            rscale=scanramp(min(row*(s(2)-hstep)+col,allsteps)); % this probably isn't correct
            cscale=mean(luma(row,col:col+hstep));
			% this is slow as hell
            line(col:col+hstep,luma(row,col:col+hstep)*hscale ...
                +row+rownoise(col:col+hstep)+rowoffset,...
                'color',1-((1-linecolor)*cscale*rscale), ...
                'linewidth',linescale*cscale+1E-4);
            if row==1 && col==1; hold on; end
        end
    end

    set(gca,'xlim',[0 s(2)],'ylim',[0 s(1)+hscale]);
    set(gca,'ytick',[],'xtick',[]);

	% under R2009b, getframe defeats attempts to render to an invisible figure
	% by setting 'visible' 'on' and constantly stealing window focus
	% in these cases, getframe is slow and completely occupies computer use
	% hardcopy frees up focus, but image is worse.
	% under R2015b, getframe doesn't steal focus, but it's slower anyway.
	
    pause(0.05);
	frame=frame2im(getframe(gca));
	cla;
	
    % remove border and pad array so blur artifacts can be cropped
	frame=imcast(frame,'double');
	fpict=1-cropborder(frame,2);
    fpict=padarray(fpict,22,0);
    
    % general line softening
    h=fspecial('disk',2);
    fpict=imfilter(fpict,h);
	
    % add extra emphasis to highlights 
	if bloom==1
        blpict=imadjustFB(fpict,[0.1 0.5],[0 0.7]);
        h=fspecial('gaussian',21,4);
        blpict=imfilter(blpict,h);
        fpict=fpict+2*blpict;
	end  
	
    % crop back to get rid of padding
    fpict=cropborder(fpict,20);
    
    % preallocate array based on whatever window geometry occurs
    % this is sloppy and assumes window doesn't change size
    % aspect ratio is corrected by adjusting width only
    if f==1
        sw=size(fpict);
        sout=round([sw(1) sw(1)/(s(1)+hscale)*s(2) 3 size(inpict,4)]);
        wpict=zeros(sout,'double');
		cpict=colorpict([size(wpict,1) size(wpict,2)],(1-linecolor),'double');
    end
    
    fpict=imresize(fpict,sout(1:2));
    wpict(:,:,:,f)=fpict;
end

% do bg underlay and frame blending
% setting axes bg color is faster, but getframe() produces terrible output 
% i.e. dark nonblack bg regions will be filled with artifacts
wpict=imblend(cpict,wpict,0.05,'screen');
wpict=imecho(wpict,2,'screen',0);

if outscale~=0
    wpict=fourdee(@imresize,wpict,[NaN outscale*size(inpict,2)]);
end

close(gcf);

return


