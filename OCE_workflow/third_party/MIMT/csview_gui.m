function varargout = csview_gui(varargin)
%   CSVIEW_GUI()
%       This is the GUIDE GUI tool for CSVIEW()
%       User is presented with a control panel and empty figure window
%       Select a color space from the menu
%       Optionally, enable and position a test point using the sliders
%       See CSVIEW() for more info.
%

% Last Modified by GUIDE v2.5 11-Nov-2015 16:20:12

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @csview_gui_OpeningFcn, ...
                   'gui_OutputFcn',  @csview_gui_OutputFcn, ...
                   'gui_LayoutFcn',  [] , ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT


% --- Executes just before csview is made visible.
function csview_gui_OpeningFcn(hObject, eventdata, handles, varargin)
    % Choose default command line output for csview
    handles.output = hObject;

    % Update handles structure
    guidata(hObject, handles);
    
    figure
	subplot(1,1,1);
	margin=0.01;
	set(gca,'position',[margin margin 1-2*margin 1-2*margin]);
    set(gcf,'tag','CSVIEW_PLOT');
	
    global plot_spc;
    global plot_point;
    global plot_invert;
    global axes_reset;
    global axrange;
    global position;
    global falpha;
    falpha=1;
    axes_reset=true;
    plot_point=false;


    % UIWAIT makes csview wait for user response (see UIRESUME)
    % uiwait(handles.figure1);


% --- Outputs from this function are returned to the command line.
function varargout = csview_gui_OutputFcn(hObject, eventdata, handles) 
    % varargout  cell array for returning output args (see VARARGOUT);
    % hObject    handle to figure
    % eventdata  reserved - to be defined in a future version of MATLAB
    % handles    structure with handles and user data (see GUIDATA)

    % Get default command line output from handles structure
    varargout{1} = handles.output;


function popupmenu1_Callback(hObject, eventdata, handles)
    contents=cellstr(get(hObject,'String'));
    spc=lower(contents{get(hObject,'Value')});
    global plot_spc; 
    global axes_reset;
    global axrange;
    global position;
    global falpha;
    axes_reset=true;
    switch spc
        case 'hsv'
            sliderange=[0 360; 0 1.5; 0 1];
            axrange=[-1.5 1.5; -1.5 1.5; 0 1];
            axstrings={'H', 'S', 'V'};
        case 'hsl'
            sliderange=[0 360; 0 1.5; 0 1];
            axrange=[-1.5 1.5; -1.5 1.5; 0 1];
            axstrings={'H', 'S', 'L'};
        case 'hsi'
            sliderange=[0 360; 0 1.5; 0 1];
            axrange=[-1.5 1.5; -1.5 1.5; 0 1];
            axstrings={'H', 'S', 'I'};
        case 'yuv'
            sliderange=[0 1; -1 1; -1 1];
            axrange=[-1 1; -1 1; 0 1];
            axstrings={'Y', 'U', 'V'};
        case 'yiq'
            sliderange=[0 1; -1 1; -1 1];
            axrange=[-1 1; -1 1; 0 1];
            axstrings={'Y', 'I', 'Q'};
        case 'ypbpr'
            sliderange=[0 1; -1 1; -1 1];
            axrange=[-1 1; -1 1; 0 1];
            axstrings={'Y', 'Pb', 'Pr'};
        case 'ycbcr'
            sliderange=[0 1; -1 1; -1 1]*255;
            axrange=[-1 1; -1 1; 0 1]*255;
            axstrings={'Y', 'Cb', 'Cr'};
        case 'ydbdr'
            sliderange=[0 1; -2 2; -2 2];
            axrange=[-2 2; -2 2; 0 1];
            axstrings={'Y', 'Db', 'Dr'};
        case 'ciexyz'
            spc='xyz';
            sliderange=[-1.5 1.5; 0 1; -1.5 1.5];
            axrange=[-1.5 1.5; -1.5 1.5; 0 1];
            axstrings={'X', 'Y', 'Z'};
        case 'cieluv' 
            spc='luv';
            sliderange=[0 100; -200 200; -200 200];
            axrange=[-200 200; -200 200; 0 100];
            axstrings={'L', 'U', 'V'};
        case 'cielab'
            spc='lab';
            sliderange=[0 100; -200 200; -200 200];
            axrange=[-200 200; -200 200; 0 100];
            axstrings={'L', 'A', 'B'};
        case 'srlab2'
            spc='srlab';
            sliderange=[0 100; -200 200; -200 200];
            axrange=[-200 200; -200 200; 0 100];
            axstrings={'L', 'A', 'B'};
        case 'cielab lch'
            spc='lchab';
            sliderange=[0 100; 0 200; 0 360];
            axrange=[-200 200; -200 200; 0 100];
            axstrings={'L', 'C', 'H'};
        case 'srlab2 lch'
            spc='lchsr';
            sliderange=[0 100; 0 200; 0 360];
            axrange=[-200 200; -200 200; 0 100];
            axstrings={'L', 'C', 'H'};
        case 'cieluv lch'
            spc='lchuv';
            sliderange=[0 100; 0 200; 0 360];
            axrange=[-200 200; -200 200; 0 100];
            axstrings={'L', 'C', 'H'};
        case 'hsy'
            sliderange=[0 360; 0 2; 0 1];
            axrange=[-1.5 1.5; -1.5 1.5; 0 1];
            axstrings={'H', 'S', 'Y'};
        case 'huslab'
            sliderange=[0 360; 0 200; 0 100];
            axrange=[-263 263; -263 263; 0 100];
            axstrings={'H', 'S', 'L'};
        case 'husluv'
            sliderange=[0 360; 0 200; 0 100];
            axrange=[-263 263; -263 263; 0 100];
            axstrings={'H', 'S', 'L'};
    end
    plot_spc=spc;
    
    set(handles.slider1,'Min',sliderange(1,1),'Max',sliderange(1,2),'Value',0);
    set(handles.slider2,'Min',sliderange(2,1),'Max',sliderange(2,2),'Value',0);
    set(handles.slider3,'Min',sliderange(3,1),'Max',sliderange(3,2),'Value',0);
    position=[0 0 0]; % in xyz coordinates
    set(handles.text2,'String',axstrings{1});
    set(handles.text3,'String',axstrings{2});
    set(handles.text4,'String',axstrings{3});
    set(handles.text5,'String',num2str(position(1)));
    set(handles.text6,'String',num2str(position(2)));
    set(handles.text7,'String',num2str(position(3)));
    set(handles.text8,'String','FaceAlpha');
    set(handles.text9,'String',num2str(falpha));
    set(handles.slider1,'Value',position(1));
    set(handles.slider2,'Value',position(2));
    set(handles.slider3,'Value',position(3));
    updatefig();

function popupmenu1_CreateFcn(hObject, eventdata, handles)
    if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
        set(hObject,'BackgroundColor','white');
    end


% --- Executes on slider movement.
function slider1_Callback(hObject, eventdata, handles)
    global position;
    position(1)=get(hObject,'Value');
    set(handles.text5,'String',num2str(position(1)));
    updatefig();
    
function slider1_CreateFcn(hObject, eventdata, handles)
    % Hint: slider controls usually have a light gray background.
    if isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
        set(hObject,'BackgroundColor',[.9 .9 .9]);
    end



% --- Executes on slider movement.
function slider2_Callback(hObject, eventdata, handles)
    global position;
    position(2)=get(hObject,'Value');
    set(handles.text6,'String',num2str(position(2)));
    updatefig();
    
function slider2_CreateFcn(hObject, eventdata, handles)
    if isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
        set(hObject,'BackgroundColor',[.9 .9 .9]);
    end


% --- Executes on slider movement.
function slider3_Callback(hObject, eventdata, handles)
    global position;
    position(3)=get(hObject,'Value');
    set(handles.text7,'String',num2str(position(3)));
    updatefig();
    
function slider3_CreateFcn(hObject, eventdata, handles)
    if isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
        set(hObject,'BackgroundColor',[.9 .9 .9]);
    end

% --- Executes on slider movement.
function slider5_Callback(hObject, eventdata, handles)
    global falpha;
    falpha=get(hObject,'Value');
    set(handles.text9,'String',num2str(falpha));
    updatefig();

% --- Executes during object creation, after setting all properties.
function slider5_CreateFcn(hObject, eventdata, handles)
    if isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
        set(hObject,'BackgroundColor',[.9 .9 .9]);
    end


% --- Executes on button press in checkbox1.
function checkbox1_Callback(hObject, eventdata, handles)
    val=get(hObject,'value');
    global plot_point;
    if val==0
        plot_point=false;
    else
        plot_point=true;
    end
    updatefig();


% --- Executes on button press in checkbox2.
function checkbox2_Callback(hObject, eventdata, handles)
    val=get(hObject,'value');
    global plot_invert;
    plot_invert=val;
    updatefig();


function updatefig()
    global plot_spc;
    global plot_point;
    global plot_invert;
    global axes_reset;
    global position;
    global axrange;
    global falpha;
    
    figure(findobj('tag','CSVIEW_PLOT'));
    
    if ~axes_reset
        xl=get(gca,'xlim');
        yl=get(gca,'ylim');
        zl=get(gca,'zlim');
        daspect=get(gca,'dataaspectratio');
        cpos=get(gca,'cameraposition');
    else
        xl=axrange(1,:);
        yl=axrange(2,:);
        zl=axrange(3,:).*[0.9 1.1];
    end
    pos=get(gca,'position');
    set(gca,'xlim',xl,'ylim',yl,'zlim',zl);
    
    if ~isempty(plot_spc)
        if isempty(plot_invert) || plot_invert==0
            if ~plot_point
                csview(plot_spc,'alpha',falpha)
            else
                csview(plot_spc,'testpoint',position,'alpha',falpha)
            end
        elseif plot_invert==1
            if ~plot_point
                csview(plot_spc,'invert',1,'alpha',falpha)
            else
                csview(plot_spc,'testpoint',position,'invert',1,'alpha',falpha)
            end
        end
    end
    
    set(gca,'position',pos);
    if ~axes_reset
        set(gca,'cameraposition',cpos,'dataaspectratio',daspect);
    else
        axes_reset=false;
    end
    
    
    
   

    
    
    
    
