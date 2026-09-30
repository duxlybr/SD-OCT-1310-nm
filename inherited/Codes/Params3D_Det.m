function [OCE_system] = Params3D_Det(OCE_system)


Cut_ini = OCE_system.X3D_ini;
Size_length = OCE_system.Num3DX;

Bmode_tmp = OCE_system.Bmode;
Bmode_avg = mean(Bmode_tmp,1);
FlagFinish = 1;

while (FlagFinish)
    
    already_saved_flag = menu('Delay control', 'Right','RightMore', 'Left','LeftMore','Accept');
    if already_saved_flag ==1 % right
        if Cut_ini == 1
            Cut_ini = Cut_ini;
        else
            Cut_ini = Cut_ini - 1;
        end
    elseif already_saved_flag == 2 % right more   
        if Cut_ini == 20
            Cut_ini = Cut_ini;
        else
            Cut_ini = Cut_ini - 20;
        end              
    elseif already_saved_flag == 3 % left
        if Cut_ini == OCE_system.NumLateralPos
            Cut_ini = Cut_ini;
        else
            Cut_ini = Cut_ini + 1;
        end  
    elseif already_saved_flag == 4 % left more
        if Cut_ini == OCE_system.NumLateralPos - 20
            Cut_ini = Cut_ini;
        else
            Cut_ini = Cut_ini + 20;
        end          
    elseif already_saved_flag == 5 % right
        FlagFinish = 0;
    end
    
MatCut = [];
for i = 1:floor((OCE_system.NumLateralPos-Cut_ini)/Size_length)
    pos_ini = Cut_ini+Size_length*(i-1);
    pos_end = Cut_ini+Size_length*(i)-1;
    MatCut(i,:) = Bmode_avg(pos_ini:pos_end);
end

figure(1)
plot(MatCut')
drawnow

end

OCE_system.X3D_ini = Cut_ini;
OCE_system.Num3DY = floor((OCE_system.NumLateralPos-Cut_ini)/Size_length);

end