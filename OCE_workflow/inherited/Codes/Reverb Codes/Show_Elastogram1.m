function []=Show_Elastogram1(Bmode,Vshear,params)

m=params.bmode_int_limit;
axes_m_x=params.bmode_axes{1};
axes_m_y=params.bmode_axes{2};

n=params.vshear_int_limit;
axes_n_x=params.vshear_axes{1};
axes_n_y=params.vshear_axes{2};

val=params.transparency;
mask=params.maskBmode;
mask1=params.maskElasto;

% Create the background
%   This example uses a blend of colors from left to right, converted to a TrueColor image
%   Use repmat to replicate the pattern in the matrix
%   Use the "jet" colormap to specify the color space

I = uint8(255*mat2gray(Bmode.*mask, [m(1) m(2)]));
bg = ind2rgb(I,gray(255));
% Create an image and its corresponding transparency data
%   This example uses a random set of pixels to create a TrueColor image
II = uint8(255*mat2gray(Vshear, [n(1) n(2)]));
im = ind2rgb(II,jet(255));


%   Now set up axes that overlay the background with the image
%   Notice how the image is resized from specifying the spatial 
%   coordinates to locate it in the axes.
ibg2 = image(axes_m_x*1e3,axes_m_y*1e3,bg);
%axis off
axis equal
hold on
%   Overlay the image, and set the transparency previously calculated
iim2 = image(im,'XData',[axes_n_x(1)*1e3 axes_n_x(end)*1e3],'YData',[axes_n_y(1)*1e3 axes_n_y(end)*1e3]);

transp=zeros(size(Vshear));
transp=transp+val*mask1;

set(iim2,'AlphaData',transp);
axis([axes_m_x(1)*1e3 round(axes_m_x(end)*1e3) axes_m_y(1)*1e3 axes_m_y(end)*1e3])
xlabel('x-axis (mm)');
ylabel('z-axis (mm)');
colorbar;
colormap(jet);
caxis([n(1) n(2)]);
set(gca,'FontSize',12);
%saveas(ibg2,['Figure_',num2str(k),'.tiff'])


end