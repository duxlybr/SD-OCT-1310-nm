function assertExactNumericContract(expected, actual, variablePath)
%ASSERTEXACTNUMERICCONTRACT Compare numeric values with zero tolerance.

    if ~strcmp(class(expected), class(actual))
        error('OCE:Contract:Class', ...
            '%s class mismatch. Expected=%s Actual=%s.', ...
            variablePath, class(expected), class(actual));
    end
    if ~isequal(size(expected), size(actual))
        error('OCE:Contract:Size', ...
            '%s size mismatch. Expected=%s Actual=%s.', variablePath, ...
            mat2str(size(expected)), mat2str(size(actual)));
    end
    if isequaln(expected, actual)
        return;
    end

    equalValues = expected == actual;
    equalNaNs = isnan(expected) & isnan(actual);
    mismatchIndex = find(~(equalValues | equalNaNs), 1);
    expectedValue = expected(mismatchIndex);
    actualValue = actual(mismatchIndex);
    absoluteDifference = abs(double(actualValue) - double(expectedValue));
    if expectedValue == 0
        relativeDifference = absoluteDifference;
    else
        relativeDifference = absoluteDifference / abs(double(expectedValue));
    end
    error('OCE:Contract:Difference', ...
        ['Difference at %s(%d). Expected=%s; Actual=%s; ' ...
         'absolute difference=%g; relative difference=%g; ' ...
         'absolute tolerance=0; relative tolerance=0.'], ...
        variablePath, mismatchIndex, mat2str(expectedValue, 17), ...
        mat2str(actualValue, 17), absoluteDifference, relativeDifference);
end
