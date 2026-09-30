function [labelText, fileText] = formatConditionLabel(dimensionKeys, dimensionValues, idxCell, dimsToUse, varargin)
%FORMATCONDITIONLABEL Build readable labels for experiment conditions.
%
% Usage:
%   [labelText, fileText] = oce.results.formatConditionLabel( ...
%       dimensionKeys, dimensionValues, idxCell, dimsToUse);
%
% Inputs:
%   dimensionKeys   - String/cell array with experiment dimension names.
%   dimensionValues - Cell array of value lists, one cell per dimension.
%   idxCell         - Cell array with selected indices for each dimension.
%   dimsToUse       - Numeric indices of dimensions to include in the label.
%
% Optional name-value arguments:
%   "Separator"          default: " - "
%   "FileSeparator"      default: "_"
%   "IncludeKeyFallback" default: true
%
% Outputs:
%   labelText - Human-readable label, e.g. "3500 Hz - 50 mVpp"
%   fileText  - File-safe label, e.g. "3500Hz_50mVpp"

    p = inputParser;
    addParameter(p, 'Separator', " - ", @(x) ischar(x) || isstring(x));
    addParameter(p, 'FileSeparator', "_", @(x) ischar(x) || isstring(x));
    addParameter(p, 'IncludeKeyFallback', true, @islogical);
    parse(p, varargin{:});

    dimensionKeys = string(dimensionKeys(:))';
    separator = string(p.Results.Separator);
    fileSeparator = string(p.Results.FileSeparator);

    if isempty(dimsToUse)
        labelText = "All conditions";
        fileText = "AllConditions";
        return;
    end

    labelParts = strings(1, numel(dimsToUse));
    fileParts  = strings(1, numel(dimsToUse));

    for i = 1:numel(dimsToUse)
        dimIdx = dimsToUse(i);
        key = dimensionKeys(dimIdx);
        value = get_dimension_value(dimensionValues, idxCell, dimIdx);

        labelParts(i) = format_label_part(key, value, p.Results.IncludeKeyFallback);
        fileParts(i)  = make_file_safe(format_file_part(key, value));
    end

    labelText = strjoin(labelParts, separator);
    fileText = strjoin(fileParts, fileSeparator);

    if strlength(fileText) == 0
        fileText = "Condition";
    end
end

function value = get_dimension_value(dimensionValues, idxCell, dimIdx)
    if dimIdx > numel(idxCell) || isempty(idxCell{dimIdx})
        value = "";
        return;
    end

    valueIdx = idxCell{dimIdx};

    if valueIdx > numel(dimensionValues{dimIdx})
        error('Index %d exceeds number of values for dimension %d.', valueIdx, dimIdx);
    end

    value = string(dimensionValues{dimIdx}{valueIdx});
end

function labelPart = format_label_part(key, value, includeKeyFallback)
    key = string(key);
    value = string(value);

    switch key
        case "frequency_Hz"
            labelPart = append(value, " Hz");
        case "frequency_kHz"
            labelPart = append(value, " kHz");
        case "voltage_mVpp"
            labelPart = append(value, " mVpp");
        case "period_us"
            labelPart = append(value, " us");
        case "period_ms"
            labelPart = append(value, " ms");
        case "strain_percent"
            labelPart = append(value, "%");
        case "pressure_mmHg"
            labelPart = append(value, " mmHg");
        case "IOP_mmHg"
            labelPart = append(value, " mmHg");
        case "temperature_C"
            labelPart = append(value, " C");
        case "rep_id"
            labelPart = append("Rep ", value);
        case "run_id"
            labelPart = value;
        otherwise
            [baseName, unitLabel] = split_key_unit(key);

            if strlength(unitLabel) > 0
                labelPart = append(value, " ", unitLabel);
            elseif includeKeyFallback
                labelPart = append(pretty_key(baseName), ": ", value);
            else
                labelPart = value;
            end
    end
end

function filePart = format_file_part(key, value)
    key = string(key);
    value = string(value);

    switch key
        case "frequency_Hz"
            filePart = append(value, "Hz");
        case "frequency_kHz"
            filePart = append(value, "kHz");
        case "voltage_mVpp"
            filePart = append(value, "mVpp");
        case "period_us"
            filePart = append(value, "us");
        case "period_ms"
            filePart = append(value, "ms");
        case "strain_percent"
            filePart = append(value, "pc");
        case "pressure_mmHg"
            filePart = append(value, "mmHg");
        case "IOP_mmHg"
            filePart = append(value, "mmHg");
        case "temperature_C"
            filePart = append(value, "C");
        case "rep_id"
            filePart = append("Rep", value);
        case "run_id"
            filePart = value;
        otherwise
            [baseName, unitLabel] = split_key_unit(key);

            if strlength(unitLabel) > 0
                filePart = append(value, unitLabel);
            else
                filePart = append(baseName, "_", value);
            end
    end
end

function [baseName, unitLabel] = split_key_unit(key)
    key = string(key);
    knownSuffixes = [ ...
        "_Hz", "_kHz", "_mVpp", "_percent", "_mmHg", ...
        "_us", "_ms", "_s", "_mm", "_um", "_nm", ...
        "_N", "_mN", "_C"];

    knownUnits = [ ...
        "Hz", "kHz", "mVpp", "%", "mmHg", ...
        "us", "ms", "s", "mm", "um", "nm", ...
        "N", "mN", "C"];

    baseName = key;
    unitLabel = "";

    for i = 1:numel(knownSuffixes)
        suffix = knownSuffixes(i);

        if endsWith(key, suffix)
            baseName = extractBefore(key, strlength(key) - strlength(suffix) + 1);
            unitLabel = knownUnits(i);
            return;
        end
    end
end

function textOut = pretty_key(key)
    textOut = replace(string(key), "_", " ");
end

function safeText = make_file_safe(textIn)
    safeText = regexprep(char(textIn), '[^\w.-]', '_');
    safeText = regexprep(safeText, '_+', '_');
    safeText = string(regexprep(safeText, '^_|_$', ''));

    if strlength(safeText) == 0
        safeText = "Condition";
    end
end
