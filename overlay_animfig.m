function [hFig,hAx,hCB,hImages] = overlay_animfig(Base,Over,varargin)
% Overlay an AlphaMap "movie" on top of a ColorMapped "movie"
% This view utilizes composit_anigfig(...)
%
% Input:
%   Base: Color or grayscale image sequence ontop of which AlphaMap will be
%         displayed. If image is grayscale, it will converted to an RGB
%         image using the specified colormap
%
%   Over: Grayscale image sequence to overlay.
%
% Both Base and Over can be specified as numeric arrays, cell arrays or
% animation structures (see composit_animfig)
%
% The color of Over can be specified by 'OverlayColor', or by specifying an
% image in the anim struct Over(n).CData = ...
%
% Parameters:
%   'colormap': colormap to use for Base images
%   'CLim': colorlims to use when applying colormap to base image
%   'ALim': Alim of axes
%       'auto': use the default values (scales to match image extents)
%       'global': use max/min for all frames in Over
%       'average' use average of max/min for frames in Over
%   'Figure',hFig: specify figure to use;
%   'frameupdate_fn':@(hFig,hAx,currentFrame) specify a callback to execute when frame
%                    is changed. See compsit_animfig for how to retrieve
%                    current frame and image data.

if ~isstruct(Over) && ~iscell(Over) && ~(isnumeric(Over)&&ndims(Over)<4)
    error('Invalid type for over');
end

p = inputParser;
p.CaseSensitive = false;
addParameter(p,'colormap','gray',@(x) ischar(x)||isnumeric(x)&&(size(x,2)==3));
addParameter(p,'OverlayColor',[1,0,0], @(x) isnumeric(x)&&numel(x)==3);
addParameter(p,'ALim','global',@(x) ischar(x)&&any(strcmpi(x,{'auto','global','average'}))||isnumeric(x)&&numel(x)==2);
addParameter(p,'CLim','global',@(x) ischar(x)&&any(strcmpi(x,{'global','average'}))||isnumeric(x)&&numel(x)==2);
addParameter(p,'Figure',[],@(x) isempty(x)||ishghandle(x));
addParameter(p,'frameupdate_fn',[],@(x) isempty(x)||isa(x,'function_handle'));

parse(p,varargin{:});

if iscell(Over)
    cOver = Over;
    Over = struct('AlphaData',{});
    for n=1:numel(cOver)
        if ~isnumeric(cOver{n})||ndims(cOver{n})>2
            error('Specified cell array for Over contained non-image (matrix) data');
        end
        Over(n).AlphaData = cOver;
    end
end

if isnumeric(Over)
    mOver = Over;
    Over = struct('AlphaData',{});
    for n=1:size(mOver,3)
        Over(n).AlphaData = mOver(:,:,n);
    end
end

%% Data is struct, add color information
if ~isfield(Over,'AlphaData')
    error('If specifying Over as a struct, it must contain AlphaData')
end
if ~isfield(Over,'CData')
    for n=1:numel(Over)
        [H,W] = size(Over(n).AlphaData);
        Over(n).CData = repmat(reshape(p.Results.OverlayColor,1,1,[]),H,W);
    end
end
%% Determine ALim
ALim = p.Results.ALim;
Alow = NaN(numel(Over),1);
Ahigh = NaN(numel(Over),1);
for n=1:numel(Over)
    Alow(n) = nanmin(Over(n).AlphaData(:));
    Ahigh(n) = nanmax(Over(n).AlphaData(:));
end

if ischar(ALim)
    switch lower(ALim)
        case'auto'

        case 'global'
            ALim = [min(Alow),max(Ahigh)];
        case 'average'
            ALim = [nanmean(Alow),nanmean(Ahigh)];
    end
end

AExt = [min(Alow),max(Ahigh)];

% All overdata should be scaled to the alphamap
[Over.AlphaDataMapping] = deal('scaled');

%% Setup colorscale limits
if ischar(p.Results.CLim)
    
    if isstruct(Base)
        CL = zeros(numel(Base),2);
        for n=1:numel(Base)
            if ndims(Base(n).CData)<3
                CL(n,1) = nanmin(Base(n).CData(:));
                CL(n,2) = nanmax(Base(n).CData(:));
            else
                CL(n,:) = NaN;
            end
        end
    elseif ndims(Base)<4 %Base is a 3d matrix
        CL = zeros(size(Base,3),2);
        CL(:,1) = nanmin(nanmin(Base,[],2),[],1);
        CL(:,2) = nanmax(nanmax(Base,[],2),[],1);
    end
    switch lower(p.Results.CLim)     
        case 'global'
            CLIM = [nanmin(CL(:,1)),nanmax(CL(:,2))];
        case 'average'
            CLIM = nanmean(CL,1);
    end
else
    CLIM = p.Results.CLim;
end
%% Create AnimFig
[hFig,hAx,hImages,hCB] = composit_animfig(Base,Over,...
                            'colormap',p.Results.colormap,...
                            'CLim','manual',...%p.Results.CLim,...
                            'Figure',p.Results.Figure,...
                            'frameupdate_fn',@FrameUpdateFcn,...
                            'ShowColorbar',true,...
                            'ColorbarWidth',15,...
                            'PreSaveFcn',@PreSaveAnim,...
                            'PostSaveFcn',@PostSaveAnim);
%% Set CLim to proper value
set(hAx,'CLim',CLIM);

%% Setup ALim
if isnumeric(ALim)
    set(hAx,'ALim',ALim);
    set(hCB,'ALim',ALim);
else
    set(hAx,'ALimMode','auto');
    set(hCB,'ALimMode','auto');
end
                        
%% create colorscale image & histogram in the colorbar

[Counts,edges] = histcounts(Over(1).AlphaData(:),'BinLimits',AExt);
[Y,X] = edges2stairs(edges,Counts);
lX = log10(X);
lX(X==0) = 0;
hHistLine = plot(hCB,lX,Y,'-k','linewidth',1.5,'hittest','off');
hold(hCB,'on');

%create image for colorscale
AL = get(hAx,'ALim');
XLIM = get(hCB,'XLim');
EXT = [min(AExt(1),AL(1)),max(AExt(2),AL(2))]; %extents of the colorscale
ylim(hCB,EXT); %set colorscal extents
cb_cdata = repmat(reshape(p.Results.OverlayColor,1,1,[]),200,1);
cb_adata = linspace(EXT(1),EXT(2),200)';
hImCB = image(hCB,'CData',cb_cdata,...
    'AlphaData',cb_adata,...
    'AlphaDataMapping','scaled',...
    'XData',[0,XLIM(2)],...
    'YData',EXT,...
    'HitTest','off');

axis(hCB,'tight');
set(hCB,'XLim',[0,XLIM(2)]);
uistack(hImCB,'down'); %move image to back

% create high/low  level lines
hL_low = plot(hCB,[0,XLIM(2)],[AL(1),AL(1)],':k','linewidth',3);
hL_up = plot(hCB,[0,XLIM(2)],[AL(2),AL(2)],':k','linewidth',3);

set(hCB,'ALim',AL); %set alim of colorscale equal to hAx so that the gradients match

set(hL_low,'ButtonDownFcn',@(h,~) LowBtnDwn(h,hCB,hAx,hImCB));
set(hL_up,'ButtonDownFcn',@(h,~) UpBtnDwn(h,hCB,hAx,hImCB));

set(hCB,'XDir','Reverse',...
    'XTick',[],...
    'Box','off',...
    'YAxislocation','right',...
    'TickDir','out');
xlabel(hCB,'Log_{10}(Count)');

    function FrameUpdateFcn(hF,~,cF)
        %cF = getappdata(hF,'curFrame');
        FR = getappdata(hF,'FrameData');
        od = FR{2}(cF).AlphaData;
        [C,E] = histcounts(od(:),'BinLimits',AExt);
        [Y,X] = edges2stairs(E,C);
        lX = log10(X);
        lX(X==0) = 0;
        set(hHistLine,'xdata',lX,'ydata',Y);
        
        if ~isempty(p.Results.frameupdate_fn)
            p.Results.frameupdate_fn(hF,getappdata(hF,'hAx'),cF)
        end
    end

    function PreSaveAnim()
        al = get(hAx,'ALim');
        ylim(hCB,al);
        
        set(hImCB,'AlphaData',linspace(al(1),al(2),200)','YData',al);
        set(hCB,'ALim',al);

        set(hHistLine,'visible','off');
        set(hL_low,'visible','off');
        set(hL_up,'visible','off');
        try
        delete(hCB.XLabel);
        catch
        end
    end
    function PostSaveAnim()
        al = get(hAx,'ALim');
        EXT = [min(AExt(1),al(1)),max(AExt(2),al(2))]; %extents of the colorscale
        ylim(hCB,EXT);
        set(hImCB,'AlphaData',linspace(EXT(1),EXT(2),200)',...
            'YData',EXT);
        set(hCB,'alim',al);
        set(hHistLine,'visible','on');
        set(hL_low,'visible','on');
        set(hL_up,'visible','on');
        xlabel(hCB,'Log_{10}(Count)');
    end
end

function LowBtnDwn(h,hCB,hAx,hImCB)
set(gcf,'WindowButtonUpFcn',@RelFn);
set(gcf,'WindowButtonMotionFcn',@MotFn)
    function MotFn(~,~)
        cp = hCB.CurrentPoint;
        y = cp(1,2);
        set(h,'ydata',[y,y]);
    end
    function RelFn(hF,~)
        set(hF,'WindowButtonUpFcn',[]);
        set(hF,'WindowButtonMotionFcn',[]);
        AL = get(hAx,'ALim');
        AL(1) = h.YData(1);
        set(hAx,'ALim',AL);
        set(hCB,'ALim',AL);
        Ext = get(hCB,'YLim');
        cb_adata = linspace(Ext(1),Ext(2),200)';
        set(hImCB,'YData',Ext,'AlphaData',cb_adata);
        
    end

end

function UpBtnDwn(h,hCB,hAx,hImCB)
set(gcf,'WindowButtonUpFcn',@RelFn);
set(gcf,'WindowButtonMotionFcn',@MotFn)
    function MotFn(~,~)
        cp = hCB.CurrentPoint;
        y = cp(1,2);
        set(h,'ydata',[y,y]);
    end
    function RelFn(hF,~)
        set(hF,'WindowButtonUpFcn',[]);
        set(hF,'WindowButtonMotionFcn',[]);
        AL = get(hAx,'ALim');
        AL(2) = h.YData(1);
        set(hAx,'ALim',AL);
        set(hCB,'ALim',AL);
        Ext = get(hCB,'YLim');
        cb_adata = linspace(Ext(1),Ext(2),200)';
        set(hImCB,'YData',Ext,'AlphaData',cb_adata);
    end

end