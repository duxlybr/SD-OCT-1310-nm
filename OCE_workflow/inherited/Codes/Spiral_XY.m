function [xy] = Spiral_XY(nAscans,nturns,Xaxis,Yaxis)


%nAscans = 800; % No. Vertical Lines

pos = [0 0 ;    % startpoint
       -1 0 ] ;  % endpoint
% engine
dp = diff(pos,1,1) ;
R = hypot(dp(1), dp(2)) ;
phi0 = atan2(dp(2), dp(1)) ;
phi = linspace(0, nturns*2*pi, nAscans) ; % 10000 = resolution
r = linspace(0, R, numel(phi)) ;
x = pos(1,1) + r .* cos(phi + phi0) ;
y = pos(1,2) + r  .* sin(phi + phi0) ;

Dist = sqrt(((diff(x)).^2)+((diff(y)).^2));
DistSum(1) = 0; DistSum(2:length(Dist)+1) = cumsum(Dist); 
xy = interp1(DistSum,[x' y'],linspace(DistSum(1),DistSum(end),length(DistSum))','spline');
xy(:,1) = xy(:,1)*Xaxis/2;
xy(:,2) = xy(:,2)*Yaxis/2;
pos(:,1) = pos(:,1)*Xaxis/2;
pos(:,2) = pos(:,2)*Yaxis/2;

figure
plot(xy(:,1),xy(:,2),'bo-',pos(:,1),pos(:,2),'ro-') ; % nturns crossings, including end point
axis equal

end