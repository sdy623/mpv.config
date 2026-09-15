-- Native 100% is a rendering mode, not merely a one-shot window resize.
local native=mp.get_property('video-unscaled','no')=='yes'
local resize_timer
local function publish()
    mp.set_property_native('user-data/window-tools',{
        mode=native and 'native-100' or 'fit-window',
        description=native and '100% 原始像素（1:1）' or '随窗口缩放',
    })
end
local function pixels()
    mp.set_property_bool('keepaspect',true)
    mp.set_property_bool('hidpi-window-scale',false)
    mp.set_property_number('video-zoom',0)
    mp.set_property_number('video-scale-x',1)
    mp.set_property_number('video-scale-y',1)
    mp.set_property_number('video-pan-x',0)
    mp.set_property_number('video-pan-y',0)
    mp.set_property_number('panscan',0)
    mp.set_property('video-unscaled',native and 'yes' or 'no')
    publish()
end
local function resize(scale,show)
    if resize_timer then resize_timer:kill() end
    resize_timer=mp.add_timeout(0.12,function()
        resize_timer=nil
        if not mp.get_property_number('width') then return end
        local ok,err=mp.set_property_number('current-window-scale',scale)
        if not ok then mp.osd_message('窗口大小设置失败：'..tostring(err),5)
        elseif show then mp.osd_message(show,4) end
    end)
end
local function windowed()
    mp.set_property_bool('fullscreen',false)
    mp.set_property_bool('window-maximized',false)
end
mp.register_script_message('native-100',function()
    native=true
    pixels()
    windowed()
    if not mp.get_property_number('width') then
        mp.osd_message('已启用 100% 原始像素；打开视频后生效',4)
    else resize(1,'100% 原始像素（1:1）；Alt+9 恢复随窗口缩放') end
end)
mp.register_script_message('fit-window',function()
    native=false
    if resize_timer then resize_timer:kill(); resize_timer=nil end
    pixels()
    mp.osd_message('已恢复随窗口缩放',3)
end)
mp.register_script_message('set-scale',function(value)
    local scale=tonumber(value)
    if not scale or scale<=0 then return end
    if not mp.get_property_number('width') then mp.osd_message('请先打开视频',4); return end
    native=false
    pixels()
    windowed()
    resize(scale,string.format('窗口大小 %.0f%%',scale*100))
end)
mp.register_script_message('fit-screen',function()
    local v=mp.get_property_native('video-out-params',{})
    local w,h=mp.get_property_number('display-width'),mp.get_property_number('display-height')
    if w and h and v.dw and v.dh then
        native=false
        pixels()
        windowed()
        resize(math.min(w*0.85/v.dw,h*0.85/v.dh),'适应屏幕（随窗口缩放）')
    else mp.osd_message('请先打开视频',4) end
end)
mp.register_event('file-loaded',function()
    -- Keep the chosen mode across playlist entries and watch-later restoration.
    if native then pixels() else mp.set_property('video-unscaled','no'); publish() end
    if native and not mp.get_property_bool('fullscreen',false)
        and not mp.get_property_bool('window-maximized',false) then resize(1) end
end)
publish()
