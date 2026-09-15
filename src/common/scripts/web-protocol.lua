-- Bilibili-Evolved / Bilibili-Playin-Mpv URL format, handled inside mpv.
-- Only media URLs and a small playback option set are accepted. No shell runs.
local utils = require 'mp.utils'
local function decode(s) return (s:gsub('%%(%x%x)', function(h) return string.char(tonumber(h,16)) end)) end
local function media_url(s)
    local host=s:match('^https://([^/]+)')
    if not host or host:find('[@:#%s]') then error('需要有效的 HTTPS 音视频地址') end
    host=host:lower()
    for _,suffix in ipairs({'bilivideo.com','bilivideo.cn','akamaized.net'}) do
        if host==suffix or host:sub(-#suffix-1)=='.'..suffix then return s end
    end
    error('此连接只接收 B 站 CDN 的音视频')
end
local function parse(uri)
    if #uri>30000 or uri:sub(1,6):lower()~='mpv://' then error('无效的 MPV 连接') end
    local text=decode(uri:sub(7))
    if text:find('[\r\n%z]') then error('参数包含无效字符') end
    local args,word,quoted={},'',false
    for i=1,#text do
        local c=text:sub(i,i)
        if c=='"' then quoted=not quoted
        elseif c:match('%s') and not quoted then
            if #word>0 then args[#args+1]=word; word='' end
        else word=word..c end
    end
    if quoted then error('参数引号不完整') end
    if #word>0 then args[#args+1]=word end
    local result={title='Bilibili · MPV'}
    for _,arg in ipairs(args) do
        if arg:sub(1,13)=='--audio-file=' then
            if result.audio then error('请一次输出一个视频') end
            result.audio=media_url(arg:sub(14))
        elseif arg:sub(1,21)=='--http-header-fields=' then
            if arg:sub(22):lower()~='referer:https://www.bilibili.com/' then error('请求头格式不受支持') end
        elseif arg:sub(1,20)=='--force-media-title=' then result.title=arg:sub(21)
        elseif arg:sub(1,8)=='--start=' and arg:sub(9):match('^%d+%.?%d*$') then result.start=arg:sub(9)
        elseif arg:sub(1,1)=='-' then error('网页包含不支持的选项')
        else
            if result.video then error('请一次输出一个视频') end
            result.video=media_url(arg)
        end
    end
    if not result.video then error('没有视频流') end
    return result
end
mp.register_script_message('validate-web-link',function(uri)
    local ok,value=pcall(parse,uri or '')
    mp.set_property_native('user-data/web-validation',{valid=ok,audio=ok and value.audio~=nil or false})
end)
mp.add_hook('on_load',3,function()
    local path=mp.get_property('path','')
    if path:sub(1,6):lower()~='mpv://' then return end
    local ok,value=pcall(parse,path)
    if not ok then
        mp.osd_message('B 站连接无法打开：'..tostring(value):gsub('^.-:%d+: ',''),8)
        mp.set_property('stream-open-filename','memory://'); return
    end
    mp.set_property_native('file-local-options/http-header-fields',{'Referer: https://www.bilibili.com/'})
    mp.set_property_native('file-local-options/audio-files',value.audio and {value.audio} or {})
    mp.set_property('file-local-options/force-media-title',value.title)
    mp.set_property_bool('file-local-options/ytdl',false)
    mp.set_property_bool('file-local-options/save-position-on-quit',false)
    if value.start then mp.set_property('file-local-options/start',value.start) end
    mp.set_property('stream-open-filename',value.video)
    mp.set_property_native('user-data/web-source',{site='Bilibili',separate_audio=value.audio~=nil})
end)
