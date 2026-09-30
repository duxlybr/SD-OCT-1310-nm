function compare_regression_values(expected, actual, fieldPath, tolerances)
%COMPARE_REGRESSION_VALUES Compare canonical golden values with tolerances.

    if nargin < 3 || strlength(string(fieldPath)) == 0
        fieldPath = "value";
    end
    if nargin < 4
        tolerances = struct('floatingAbsolute', 0, 'floatingRelative', 0);
    end

    fieldPath = string(fieldPath);
    assert_same(class(expected), class(actual), fieldPath + ".class");
    assert_same(size(expected), size(actual), fieldPath + ".size");

    if isstruct(expected)
        assert_same(sort(fieldnames(expected)), sort(fieldnames(actual)), ...
            fieldPath + ".fields");
        fields = fieldnames(expected);
        for idx = 1:numel(expected)
            for f = 1:numel(fields)
                name = fields{f};
                compare_regression_values(expected(idx).(name), ...
                    actual(idx).(name), ...
                    fieldPath + "(" + idx + ")." + name, tolerances);
            end
        end
        return;
    end

    if istable(expected)
        assert_same(expected.Properties.VariableNames, ...
            actual.Properties.VariableNames, fieldPath + ".VariableNames");
        for f = 1:width(expected)
            name = expected.Properties.VariableNames{f};
            compare_regression_values(expected.(name), actual.(name), ...
                fieldPath + "." + name, tolerances);
        end
        return;
    end

    if iscell(expected)
        for idx = 1:numel(expected)
            compare_regression_values(expected{idx}, actual{idx}, ...
                fieldPath + "{" + idx + "}", tolerances);
        end
        return;
    end

    if isnumeric(expected) || islogical(expected)
        compare_numeric(expected, actual, fieldPath, tolerances);
        return;
    end

    if ~isequaln(expected, actual)
        fail(fieldPath, expected, actual, NaN, NaN, NaN, NaN);
    end
end

function compare_numeric(expected, actual, fieldPath, tolerances)
    if ~isequal(isnan(expected), isnan(actual))
        fail(fieldPath + ".NaNMask", isnan(expected), isnan(actual), ...
            NaN, NaN, 0, 0);
    end

    if isinteger(expected) || islogical(expected)
        if ~isequal(expected, actual)
            idx = find(expected ~= actual, 1);
            fail(fieldPath + "(" + idx + ")", expected(idx), actual(idx), ...
                abs(double(expected(idx)) - double(actual(idx))), NaN, 0, 0);
        end
        return;
    end

    finiteMask = isfinite(expected) & isfinite(actual);
    if ~isequal(isinf(expected), isinf(actual)) || ...
            any(expected(isinf(expected)) ~= actual(isinf(actual)))
        fail(fieldPath + ".InfMask", expected, actual, NaN, NaN, 0, 0);
    end

    absDiff = abs(double(actual) - double(expected));
    relDiff = zeros(size(absDiff));
    denom = max(abs(double(expected)), realmin('double'));
    relDiff(finiteMask) = absDiff(finiteMask) ./ denom(finiteMask);
    threshold = tolerances.floatingAbsolute + ...
        tolerances.floatingRelative .* abs(double(expected));
    mismatch = finiteMask & absDiff > threshold;

    if any(mismatch(:))
        idx = find(mismatch, 1);
        fail(fieldPath + "(" + idx + ")", expected(idx), actual(idx), ...
            absDiff(idx), relDiff(idx), tolerances.floatingAbsolute, ...
            tolerances.floatingRelative);
    end
end

function assert_same(expected, actual, fieldPath)
    if ~isequaln(expected, actual)
        fail(fieldPath, expected, actual, NaN, NaN, 0, 0);
    end
end

function fail(fieldPath, expected, actual, absDiff, relDiff, absTol, relTol)
    error('OCE:Regression:Difference', ...
        ['Difference at %s. Expected=%s; Actual=%s; ' ...
         'absolute difference=%s; relative difference=%s; ' ...
         'absolute tolerance=%s; relative tolerance=%s.'], ...
        fieldPath, format_value(expected), format_value(actual), ...
        format_value(absDiff), format_value(relDiff), ...
        format_value(absTol), format_value(relTol));
end

function text = format_value(value)
    try
        text = mat2str(value);
    catch
        text = char(string(value));
    end
end
