function outpict=lcdemu(inpict,vangle,screenprofile)
%   LCDEMU(INPICT,{ANGLE},{SCREENPROFILE})
%       Emulate the effect of using an old or low-quality TN-type LCD monitor
%       Both horizontal and vertical viewing angle influence is emulated
%       Image is assumed to be scaled to vertical screen extents
%
%   INPICT is an image (I or RGB)
%   ANGLE is the nominal vertical viewing angle (default 0)
%       the default case assumes gaze is centered and orthogonal to screen
%       viewing angle varies over image area based on assumptions of screen geometry
%       increasing ANGLE emulates an upward gaze from a lower position
%       decreasing ANGLE emulates a downward gaze from a higher position
%       allowed range of ANGLE varies with the hardware model (see below)
%   SCREENPROFILE selects a hardware profile.  Default is 'generic'.
%       'generic' is an initial model derived from comparative analysis [-14 14]
%       The following profiles were measured electronically
%       'acer' is an Acer 7736z laptop screen [-19 19]
%       'sceptre' is a Sceptre X9G-NagaV [-15 15]
%       'hannsg' is a Hanns-G HG281D [-13 13]
%
%   CLASS SUPPORT:
%       inputs may be 'uint8','uint16','int16','single','double', or 'logical'
%       return class matches INFRAMES class


% Although this is a very rough modeling attempt, it should clearly demonstrate that
% viewing angle influence does not cause a gamma shift in the typical sense of the word
% as used with CRT monitors.  The error cannot be compensated by a simple power function; 
% furthermore, the effect cannot be compensated by any single 1-D function.
% To make matters worse, subpixel sharing and white/black point variation and inversion
% causes difficulty when trying to compare intensity maps to density maps!
% Dithered images may not be angle-invariant, and the relationship between the perceivved
% grey levels of an intensity map and a density map may not be angle-invariant.

% https://www.researchgate.net/publication/264050335_Limitations_of_visual_gamma_corrections_in_LCD_displays

% In short, shitty panels are fucking useless for graphics work.
% Given any comfortable combination of image/screen size and viewing distance, it is not possible
% to have all parts of an image represented uniformly.  
% The ability to simultaneously compare image regions by eye is lost.  

if ~exist('vangle','var')
	vangle=0;
end

if ~exist('screenprofile','var')
	screenprofile='generic';
end

% safeguard things so bsxfun doesn't explode
try
	[inpict inclass]=imcast(inpict,'double');
catch b
	error('LCDEMU: Unsupported image class for INPICT')
end

inpict=min(max(inpict,0),1);
s=size(inpict);

% profiles captured using an AMS TSL235R-LF sensor + arduino
% if you want a copy of the autoprofiler gui and uc code, ask me.
% these aren't expected to be perfect; i have no means of calibration
% these all use relative black/white points and assume gamma=2.2
% since values are normalized per min/max readings on each display
% this means that black level performance isn't emulated (backlight bleed)
% similarly, backlight nonuniformity is not emulated

switch lower(screenprofile)
	case 'generic'
		% this was a generic initial approximation
		% developed via comparative analysis by eye
		anglerange=[-25 25];	% range of angles represented by vertical axis of tfmap
		inclangle=22;			% included angle of image (vertical)
		aspectratio=16/9;
		Yest=[0.25 0.2677 0.2849 0.3012 0.316 0.329 0.3396 0.3474 0.352 0.3528 0.3494 0.3415 0.3295 0.3141 0.2956 0.2747 0.2518 0.2275 0.2024 0.1769 0.1515 0.1269 0.1036 0.08198 0.0627 0.04625 0.03294 0.02266 0.01525 0.01056 0.008428 0.008689 0.01119 0.01577 0.02226 0.03052 0.04038 0.05169 0.06427 0.07799 0.09267 0.1082 0.1243 0.1409 0.1579 0.175 0.1922 0.2092 0.2259 0.2421 0.2577 0.2726 0.2869 0.3006 0.3136 0.3261 0.3381 0.3496 0.3606 0.3711 0.3813 0.3911 0.4005 0.4096 0.4184 0.427 0.4354 0.4436 0.4516 0.4595 0.4673 0.475 0.4827 0.4903 0.4981 0.5058 0.5138 0.522 0.5306 0.5397 0.5494 0.5599 0.5712 0.5836 0.597 0.6117 0.6277 0.6452 0.6642 0.685 0.7076 0.7321 0.7587 0.7874 0.8184 0.8518 0.8871 0.9239 0.9617 1;0.04998 0.04934 0.04886 0.04871 0.04907 0.05009 0.0519 0.05452 0.0579 0.06203 0.06688 0.07242 0.07864 0.08549 0.09297 0.101 0.1097 0.1188 0.1285 0.1387 0.1493 0.1604 0.1719 0.1838 0.196 0.2086 0.2214 0.2346 0.248 0.2617 0.2755 0.2895 0.3037 0.3181 0.3325 0.347 0.3615 0.3761 0.3907 0.4052 0.4197 0.4341 0.4485 0.4627 0.4767 0.4906 0.5042 0.5176 0.5308 0.5437 0.5562 0.5685 0.5805 0.5921 0.6035 0.6146 0.6254 0.636 0.6464 0.6565 0.6664 0.676 0.6855 0.6948 0.7039 0.7129 0.7216 0.7303 0.7388 0.7472 0.7554 0.7636 0.7716 0.7796 0.7875 0.7953 0.8031 0.8109 0.8186 0.8263 0.8339 0.8416 0.8493 0.857 0.8648 0.8725 0.8804 0.8883 0.8963 0.9043 0.9125 0.9207 0.9291 0.938 0.9502 0.9674 0.9856 0.9987 1.002 1.001;0.2 0.2048 0.2095 0.2143 0.2192 0.2242 0.2292 0.2343 0.2396 0.245 0.2506 0.2563 0.2622 0.2683 0.2746 0.281 0.2876 0.2943 0.3012 0.3082 0.3153 0.3226 0.3301 0.3376 0.3453 0.3531 0.361 0.369 0.3771 0.3854 0.3937 0.4021 0.4107 0.4193 0.428 0.4367 0.4456 0.4545 0.4634 0.4725 0.4816 0.4907 0.4999 0.5091 0.5184 0.5277 0.5371 0.5465 0.5559 0.5653 0.5747 0.5842 0.5936 0.6031 0.6126 0.622 0.6315 0.6409 0.6504 0.6598 0.6692 0.6786 0.688 0.6974 0.7067 0.716 0.7253 0.7345 0.7437 0.7528 0.7619 0.771 0.78 0.7889 0.7978 0.8066 0.8153 0.8239 0.8323 0.8405 0.8484 0.856 0.8632 0.87 0.8764 0.8822 0.8875 0.8923 0.8964 0.8998 0.9024 0.9035 0.9025 0.8983 0.8903 0.878 0.8618 0.8428 0.8219 0.8001];
			
	case 'acer'
		% ACER 7736z (ca 2009)
		% 17" 16:9 display at about 20"
		anglerange=[-30 30];	% range of angles represented by vertical axis of tfmap
		inclangle=22;			% included angle of image (vertical)
		aspectratio=16/9;
		Yest=[0 0.1101 0.1352 0.1422 0.142 0.1383 0.1331 0.1279 0.1262 0.1293 0.1407 0.1614 0.188 0.2233 0.264 0.3112 0.3615 0.4236 0.4958 0.5905 0.7079;0.05532 0.09138 0.0999 0.1054 0.115 0.1325 0.1589 0.1911 0.2248 0.2655 0.3131 0.3606 0.4083 0.4618 0.5164 0.574 0.631 0.6961 0.7652 0.8457 0.9276;0.04083 0.1071 0.1596 0.2071 0.2482 0.2926 0.3402 0.3872 0.4311 0.4794 0.5301 0.5807 0.6279 0.6781 0.7266 0.775 0.82 0.8682 0.9149 0.9629 1;0.1288 0.1911 0.2506 0.3016 0.3439 0.3877 0.4334 0.477 0.5167 0.5593 0.6027 0.6449 0.6832 0.7227 0.7596 0.7951 0.8271 0.8597 0.8899 0.9182 0.9327;0.2132 0.2686 0.3198 0.3619 0.3952 0.4287 0.4623 0.4933 0.5207 0.5492 0.5771 0.6033 0.6262 0.6488 0.6691 0.6879 0.7038 0.7196 0.7331 0.7439 0.7367];
		
	case 'sceptre'
		% SCEPTRE X9G-NagaV (ca 2005)
		% 19" 4:3 display at about 22"
		% brightness at 30%
		anglerange=[-30 30];	% range of angles represented by vertical axis of tfmap
		inclangle=30;			% included angle of image (vertical)
		aspectratio=4/3;
		Yest=[0.03482 0 0.02541 0.05438 0.08056 0.109 0.1373 0.1676 0.1954 0.2233 0.2492 0.2797 0.3124 0.352 0.3966 0.4444 0.4878 0.5369 0.6002 0.6751 0.7163;0.1551 0.1551 0.1611 0.1734 0.196 0.2368 0.2799 0.3257 0.3639 0.4027 0.4364 0.4748 0.5144 0.5615 0.6123 0.6637 0.7093 0.7586 0.8177 0.8818 0.9165;0.1529 0.1598 0.1768 0.2087 0.2545 0.3201 0.3826 0.4427 0.4899 0.5354 0.5735 0.6144 0.6554 0.7029 0.7519 0.7993 0.8398 0.8823 0.9289 0.9752 1;0.1586 0.1672 0.1931 0.2376 0.2928 0.3681 0.4354 0.4976 0.5452 0.5907 0.6275 0.6667 0.7044 0.7477 0.7909 0.8317 0.8658 0.9 0.9365 0.9707 0.9891;0.09987 0.1215 0.1644 0.2247 0.2899 0.3667 0.4324 0.4897 0.5322 0.571 0.6019 0.6334 0.6632 0.6962 0.7283 0.7579 0.7818 0.8045 0.8276 0.8469 0.8584];
		
	case 'hannsg'
		% HANNS G HG281D (ca 2007)
		% 28" 16:10 display at about 24"
		anglerange=[-30 30];	% range of angles represented by vertical axis of tfmap
		inclangle=34;			% included angle of image (vertical)
		aspectratio=16/10;
		Yest=[0.06405 0.08346 0.1056 0.1248 0.1371 0.1467 0.1543 0.1653 0.1809 0.2056 0.2312 0.2633 0.3008 0.3491 0.407 0.4694 0.5302 0.6052 0.7023 0.8074 0.8729;0.09656 0.09854 0.1029 0.1106 0.1216 0.1423 0.1749 0.2204 0.2655 0.316 0.3584 0.405 0.4522 0.5085 0.5701 0.6334 0.6913 0.7585 0.8377 0.9187 0.9652;0.09854 0.09854 0.1039 0.1185 0.1418 0.1809 0.2321 0.2958 0.3522 0.4126 0.4587 0.508 0.5573 0.6139 0.6739 0.734 0.7868 0.8424 0.907 0.967 1;0.09944 0.09763 0.109 0.137 0.176 0.231 0.2965 0.3699 0.4309 0.4935 0.5417 0.5907 0.6381 0.6897 0.743 0.7929 0.8351 0.8788 0.9254 0.962 0.9751;0.04182 0 0.0643 0.1221 0.1789 0.2459 0.3195 0.3947 0.4551 0.5144 0.5589 0.6025 0.6431 0.687 0.7299 0.7685 0.799 0.8296 0.8584 0.8735 0.8666];

end

% different gamma back-correction?
%Yest=Yest.^(1/2.2);
%Yest=Yest.^1.8;

% VERTICAL SETUP
tfmap=imresize(Yest,[1 1]*256,'bicubic');
% viewing angle can be adjusted further
inanglerange=[-1 1]*(diff(anglerange)-inclangle)/2;
deg2tfy=size(tfmap,1)/(anglerange(2)-anglerange(1));		% convert degrees to approx row in tfmap

% select proper subset of tfmap to create specific tf for given angles
va=min(max(-vangle,inanglerange(1)),inanglerange(2));
tfyrange=deg2tfy*(va+[-1 1]*inclangle/2)+size(tfmap,1)/2;
tfyrange=min(max(round(tfyrange),1),size(tfmap,1));
tf=tfmap(tfyrange(1):tfyrange(2),:);

% create angle map for given image and varange
% this will be used much like a second layer in mesh blending
x=linspace(0,1,s(2));
y=linspace(0,1,s(1));
[xx ypos]=meshgrid(x,y);
% create grid for v interplation
x=linspace(0,1,size(tf,2));
y=linspace(0,1,size(tf,1));
[xx yy]=meshgrid(x,y);

% HORIZONTAL SETUP
% intensity offset vs ha (x = image position L2R)
x4=[0 0.4 0.5 0.6 1];
y4=-0.02*[1 0 0 0 1];
cfp=0.9999999;
fit4=fit(x4',y4','smoothingspline','smoothingparam',cfp);
% truncate hiomap based on image aspect ratio
xfrange=0.5+[-0.5 0.5]*s(2)/(s(1)*aspectratio);
xfine=linspace(xfrange(1),xfrange(2),256);
y4fine=fit4(xfine)';
hiomap=imresize(y4fine,s(1:2),'bicubic');
	
outpict=zeros(size(inpict));
for c=1:size(inpict,3)
	% do interpolation for va emulation
	outpict(:,:,c)=interp2(xx,yy,tf,inpict(:,:,c),ypos,'bilinear');

	% do a halfass adjustment for ha emulation
	outpict(:,:,c)=outpict(:,:,c)+hiomap;
end

outpict=min(max(outpict,0),1);
outpict=imcast(outpict,inclass);

end