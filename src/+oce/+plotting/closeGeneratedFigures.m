function closeGeneratedFigures(figuresBefore, closeFigures)
%CLOSEGENERATEDFIGURES Close only figures created after the supplied snapshot.
    if ~closeFigures, return; end
    figuresAfter = findall(0, 'Type', 'figure');
    generatedFigures = setdiff(figuresAfter, figuresBefore);
    for i = 1:numel(generatedFigures)
        if isvalid(generatedFigures(i)), close(generatedFigures(i)); end
    end
end
