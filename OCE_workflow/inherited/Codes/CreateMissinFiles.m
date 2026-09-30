function [] = CreateMissinFiles (pathname,NumLateral)

oldFolder = cd(pathname);
filenames = dir(fullfile(pathname,'*.dat'));
N = length(filenames);

if N < NumLateral
    Name = filenames(N).name;
    NewName = Name;
    [B,startIndex,endIndex] = regexp(Name,'\d*','Match');
  
    Bnum = str2double(B);
    
    ExtraNum = (NumLateral-N);
    for i = 1:ExtraNum
        NewNum = num2str(Bnum(1)+i);
        NewName(startIndex(1):endIndex(2)) = [NewNum,'.',num2str(Bnum(2))];
        status = copyfile(Name,NewName);
    end
end

cd(oldFolder);

end