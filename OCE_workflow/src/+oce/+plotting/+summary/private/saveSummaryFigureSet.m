function artifacts = saveSummaryFigureSet(figures, fileNames, rootdir)
%SAVESUMMARYFIGURESET Persist already-rendered summary figures.

    figures = figures(:);
    fileNames = string(fileNames(:));
    if numel(figures) ~= numel(fileNames)
        error('OCE:Plotting:SummaryFigureSetShape', ...
            'Summary figure handles and file names must have matching counts.');
    end

    saveFolder = fullfile(string(rootdir), "Summary Figures");
    if ~isfolder(saveFolder)
        mkdir(saveFolder);
    end

    artifacts = strings(2 * numel(figures), 1);
    for index = 1:numel(figures)
        figurePath = fullfile(saveFolder, fileNames(index) + ".fig");
        imagePath = fullfile(saveFolder, fileNames(index) + ".png");
        savefig(figures(index), figurePath);
        exportgraphics(figures(index), imagePath, 'Resolution', 300);
        artifacts(2 * index - 1) = string(figurePath);
        artifacts(2 * index) = string(imagePath);
    end
end
