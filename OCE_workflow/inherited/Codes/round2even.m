function result = round2even(x)

Min = floor(x);
Max = ceil(x);

if ~mod(Min,2)
    result = Min;
else
    result = Max;
end

end
