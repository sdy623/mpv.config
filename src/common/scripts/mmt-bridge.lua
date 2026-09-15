-- SPDX-License-Identifier: GPL-3.0-or-later
-- Optional MMT launcher bridge, independent of the Blu-ray plugin.
local utils=require 'mp.utils'
local input=require 'mp.input'
local o={launcher=''}
require('mp.options').read_options(o,'mmt-bridge')
local executable=mp.get_property('executable-path','')
local launcher=o.launcher~='' and mp.command_native({'expand-path',o.launcher}) or utils.join_path(utils.split_path(executable),'MPV-Anime.exe')
mp.register_script_message('mmt-url', function()
    input.get({prompt='MMT/TLV 明文流的 HTTP(S) 地址：', submit=function(url)
        if url and url:match('^https?://') then mp.commandv('loadfile', 'mmt+' .. url)
        else mp.osd_message('请输入 HTTP 或 HTTPS 地址', 4) end
    end})
end)
mp.add_hook('on_load',5,function()
    local path=mp.get_property('path','')
    local low = path:lower():gsub('%?.*$', '')
    if low:match('%.mmts$') or low:match('%.mmt$') or low:match('%.tlv$') or low:match('^mmt%+https?://') then
        local args={launcher, '--mmt-source', path, '--volume='..mp.get_property('volume','50'), '--mute='..mp.get_property('mute','no'), '--pause='..mp.get_property('pause','no'), '--save-position-on-quit='..mp.get_property('save-position-on-quit','yes')}
        local ipc=mp.get_property('input-ipc-server','')
        if ipc~='' then args[#args+1]='--input-ipc-server='..ipc end
        local ok = mp.command_native({name='subprocess', args=args, detach=true, playback_only=false})
        if ok and ok.status == 0 then mp.commandv('quit') else mp.osd_message('MMT 播放入口启动失败', 5) end
        return
    end
end)
