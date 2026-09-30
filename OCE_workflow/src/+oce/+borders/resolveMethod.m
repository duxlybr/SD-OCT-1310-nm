function detector = resolveMethod(methodName)
%RESOLVEMETHOD Resolve a configured border detector without executing it.

    methodName = string(methodName);
    if ~isscalar(methodName) || ismissing(methodName)
        error('OCE:Borders:UnsupportedMethod', ...
            'BorderOptions.method must be one supported scalar string.');
    end
    methodName = strtrim(methodName);
    switch methodName
        case "phantom"
            detector = @oce.borders.methods.findPhantomBorders;
        case "adaptive_corneal"
            detector = @oce.borders.methods.findAdaptiveCornealBorders;
        case "in_vivo_corneal"
            detector = @oce.borders.methods.findInVivoCornealBorders;
        otherwise
            error('OCE:Borders:UnsupportedMethod', ...
                ['Unsupported BorderOptions.method "%s". Supported methods ' ...
                 'are phantom, adaptive_corneal, and in_vivo_corneal.'], ...
                methodName);
    end
end
