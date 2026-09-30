
function imgDouble = oct2_processRawData(measurement, BscansToProcess, processingParams)
%measurement is the output from oct1_readRawData
%BscansToProcess are the bscans to process, it can be one integer or an array
%processingParams is a structure with the processing parameters
%
%output is the processed data (double)

if nargin==0
    file = '../medidasprueba/crosshairtests/medida1.bin';
    measurement = oct2_readRawData(file,10);
end

if nargin<2 || isempty(BscansToProcess)
    BscansToProcess=1:size(measurement.rawdata,3);
end

if nargin<3 || isempty(processingParams)
    %processing params.
    processingParams.substractBackgroundFlag=1;
    processingParams.spectralShapingFlag=1;
    processingParams.spectralShapingVals=[0.5 0.1]; %this is the approximate fit to a gauusian of the spectra.
    processingParams.dispCompensationFlag=0;
    processingParams.dispCompensationVals=[2 0];
    processingParams.shifEvenBscansPixels=0;
end



%first read the processing parameters from structure
substractBackgroundFlag=processingParams.substractBackgroundFlag;
spectralShapingFlag    =processingParams.spectralShapingFlag;
spectralShapingVals    =processingParams.spectralShapingVals;
dispCompensationFlag   =processingParams.dispCompensationFlag;
dispCompensationVals   =processingParams.dispCompensationVals;
shifEvenBscansPixels   =processingParams.shifEvenBscansPixels;


if isfield(measurement,'background')==0
    measurement.background = mean( measurement.rawdata, 3 );
end


%get some basic info about the data
nPixels         = size(measurement.rawdata,1) ; %in sdoct it is always 4096
nAscansPerBscan = size(measurement.rawdata,2) ;

imgDouble=zeros(measurement.ScanInfo.samples_in_Aline/2 ,nAscansPerBscan, length(BscansToProcess));

for i = 1:length(BscansToProcess)
    
    ind_Bscan=BscansToProcess(i);
    
    %get detector data for that bscan
    data=double( measurement.rawdata(:,:,ind_Bscan) );
    
    %substract background
    if substractBackgroundFlag
        %%substract background (this is just substract the average)
        %data = data - repmat(mean(data,2) , 1 , nAscansPerBscan );
        
        %there is always one extra bscan. empty. I'm guessing here that that is the bacground
        bkg=double( measurement.background );
        data= data - repmat(mean(bkg,2), 1, nAscansPerBscan);
    end
    
    
    
    %k linearization (use the file saved in measurementInf (oct2 should be calibration file)
    %datalinear = interp1(0:4095 , data, measurement.kCalibrationCurve,'pchip','extrap');
    %data=datalinear;

    
    %spectral shaping.
    if spectralShapingFlag
        gaussCenter = spectralShapingVals(1);
        gaussWidth  = spectralShapingVals(2);
        %
        xdata = 0:(nPixels-1);
        xdata = xdata / (nPixels-1);
        spShaping = exp( - (xdata - gaussCenter).^2 / (2*gaussWidth^2) );
        spShaping = spShaping ./ max(spShaping);
        %figure, plot(data(:,1:10),'-b'), hold on, plot(spShaping*50,'-r')
        data = data .* repmat(spShaping',1,nAscansPerBscan) ;
    end
    
    
    
    %dispersion compensation (as it was for the murcia ssoct)
    if dispCompensationFlag
        n2=dispCompensationVals(1);
        n3=dispCompensationVals(2);
        %
        xdata = 0:(nPixels-1);
        xdata = xdata - xdata(length(xdata)/2+1);
        phase = -(n2/1e6*xdata.^2 + n3/1e9*xdata.^3) ;
    else
        phase = zeros(1,nPixels);
    end
    %
    data = data  .*  exp(1i*repmat(phase',1,nAscansPerBscan));

    
    %FFT
    data = fft ( data ) ; %checked
    data=abs(data(1:nPixels/2,:));
    
    
    
%     %%if it is a pair image number, fliplr
%     if mod(ind_Bscan,2)==0
%         data = fliplr(data);
%     end
    data=flipud(data);
    
    
    %if it is even shift it the amount specified in Shift even imgs:
    if mod(ind_Bscan,2)==0
        if shifEvenBscansPixels>0
            data(:,abs(shifEvenBscansPixels)+1:end)=data(:,1:end-abs(shifEvenBscansPixels));
        else
            data(:,1:end-abs(shifEvenBscansPixels))=data(:,abs(shifEvenBscansPixels)+1:end);
        end
    end
    
    
    
    
    %log scale so that result is is dB
    data = 20*log10(data);
    
    %save data (which is not the oct image in double precission)
    imgDouble(:,:,i)=data;
    
        
end

if nargin==0
    c=[min(imgDouble(:)) max(imgDouble(:))];
    figure,colormap gray, 
    for i = 1:length(BscansToProcess)
        clf, imagesc(imgDouble(:,:,i)), caxis(c), colorbar, drawnow
    end
    imgDouble=[];
end