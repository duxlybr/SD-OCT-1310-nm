function [error] = TheoreticalProfile (k,x,y)

y_s = (sinc(k*x/pi) - ((sinc(k*x/pi)./(k*x))-(cos(k*x)./(k*x)))./(k*x) );
error = sum(abs(y_s-y));


end