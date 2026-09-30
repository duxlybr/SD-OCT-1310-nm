function [detM, ConNum] = mRLFE(k,w,c1,mu,rho_s,cf,rho_f,d)

c2 = sqrt(mu/rho_s);

alpha_f2 = ((k^2)-(w/cf)^2 );
alpha2 = ( (k^2)-(w/c1)^2 );
betha2 = ( (k^2)-(w/c2)^2 );

betha = sqrt(betha2);
alpha = sqrt(alpha2);
alpha_f = sqrt(alpha_f2);

M(1,1) = (k^2 + betha^2)*sinh(alpha*d);
M(1,2) = (2*k*betha)*sinh(betha*d);
M(1,3) = (k^2 + betha^2)*cosh(alpha*d);
M(1,4) = (2*k*betha)*cosh(betha*d);
M(1,5) = 0;

M(2,1) = (2*k*alpha)*cosh(alpha*d);
M(2,2) = (k^2 + betha^2)*cosh(betha*d);
M(2,3) = (2*k*alpha)*sinh(alpha*d);
M(2,4) = (k^2 + betha^2)*sinh(betha*d);
M(2,5) = 0;

M(3,1) = -(k^2 + betha^2)*sinh(alpha*d);
M(3,2) = -(2*k*betha)*sinh(betha*d);
M(3,3) = (k^2 + betha^2)*cosh(alpha*d);
M(3,4) = (2*k*betha)*cosh(betha*d);
M(3,5) = rho_f*(w^2)/mu;

M(4,1) = (2*k*alpha)*cosh(alpha*d);
M(4,2) = (k^2 + betha^2)*cosh(betha*d);
M(4,3) = -(2*k*alpha)*sinh(alpha*d);
M(4,4) = -(k^2 + betha^2)*sinh(betha*d);
M(4,5) = 0;

M(5,1) = (alpha)*cosh(alpha*d);
M(5,2) = (k)*cosh(betha*d);
M(5,3) = -(alpha)*sinh(alpha*d);
M(5,4) = -(k)*sinh(betha*d);
M(5,5) = -alpha_f;

%detM = real(det(M));
detM = 0;
ConNum = cond(M);

end