-- Reopen Windows audio output after device changes; an optional preferred device is configurable.
-- This build's internal ao-reload command is regression-tested in the repair pack.
local o={enabled=true,preferred_name='',preferred_channel=''}
require('mp.options').read_options(o,'audio-router')
if not o.enabled then return end
local expected=mp.get_property('audio-device','auto')
local mode=o.preferred_name~='' and 'prefer-device' or 'system-default'
local loaded=false
local description=''
local status='starting'
local reason='startup'
local retries,reloads=0,0
local debounce,retry_timer
local pending_force=false
local recovering,exhausted=false,false
local next_probe=0
local warned=false
local retry_delays={0.25,0.75,1.5,3,5,8}
local last_signature,last_target

local function catalog()
    return mp.get_property_native('audio-device-list',{})
end
local function find_main(devices)
    if o.preferred_name=='' then return nil end
    local name=o.preferred_name:lower():gsub('%s+','')
    local channel=o.preferred_channel:lower():gsub('%s+','')
    local matches={}
    for _,device in ipairs(devices) do
        local label=(device.description or ''):lower():gsub('%s+','')
        if (device.name or ''):match('^wasapi/') and label:find(name,1,true)
            and label:find(channel,1,true) then
            matches[#matches+1]=device
        end
    end
    if #matches==1 then return matches[1] end
end
local function exists(name,devices)
    if name=='auto' then return true end
    for _,device in ipairs(devices) do if device.name==name then return true end end
    return false
end
local function target(devices)
    if mode~='prefer-device' then return expected end
    local device=find_main(devices)
    return device and device.name or 'auto'
end
local function has_audio()
    for _,track in ipairs(mp.get_property_native('track-list',{})) do
        if track.type=='audio' and track.selected then return true end
    end
    return false
end
local function healthy()
    return mp.get_property('current-ao')=='wasapi'
end
local function publish()
    mp.set_property_native('user-data/audio-routing',{
        mode=mode,device=expected,description=description,status=status,
        reason=reason,retries=retries,reloads=reloads,
        current_ao=mp.get_property('current-ao','none'),
    })
end
local function cancel_retry()
    if retry_timer then retry_timer:kill(); retry_timer=nil end
    recovering=false
end
local function recover_output(force,slow)
    if not loaded or not has_audio() then publish(); return end
    cancel_retry()
    recovering=true
    exhausted=false
    retries=0
    local limit=slow and 1 or #retry_delays
    local attempt
    attempt=function()
        retry_timer=nil
        if not loaded or not has_audio() then cancel_retry(); return end
        if healthy() and not force then
            recovering=false
            status='ready'
            warned=false
            publish()
            return
        end
        if retries>=limit then
            recovering=false
            exhausted=true
            status='waiting-for-output'
            next_probe=mp.get_time()+30
            if not warned then
                warned=true
                mp.osd_message('声音输出暂不可用，正在自动重试；请检查声卡或其他软件的 ASIO / 独占输出',6)
            end
            publish()
            return
        end
        force=false
        retries=retries+1
        reloads=reloads+1
        status='reopening-output'
        -- Never change pause, volume, mute, position, or the user's selected track.
        local ok,err=mp.commandv('ao-reload')
        if not ok then mp.msg.warn('Audio reopen: '..tostring(err)) end
        publish()
        retry_timer=mp.add_timeout(retry_delays[retries],attempt)
    end
    retry_timer=mp.add_timeout(0.15,attempt)
end
local function route(why,force,show)
    local devices=catalog()
    local device=mode=='prefer-device' and find_main(devices) or nil
    local next_target=target(devices)
    local changed=mp.get_property('audio-device','auto')~=next_target
    expected=next_target -- Set before assigning, so our notification is not manual.
    reason=why
    if mode=='prefer-device' then
        description=device and device.description or '系统默认输出（偏好设备暂不可用）'
    elseif mode=='system-default' then description='系统默认输出'
    else description=expected end
    if changed then mp.set_property('audio-device',expected) end
    status=healthy() and 'ready' or 'waiting-for-device'
    publish()
    if changed or force or (not healthy() and not recovering and not exhausted) then
        recover_output(force or changed)
    end
    if show then mp.osd_message('声音输出：'..description,5) end
end
local function schedule(why,force)
    pending_force=pending_force or force
    if debounce then debounce:kill() end
    debounce=mp.add_timeout(0.35,function()
        debounce=nil
        local reopen=pending_force
        pending_force=false
        route(why,reopen,false)
    end)
end

if expected~='auto' and exists(expected,catalog()) then mode='manual' end
mp.observe_property('audio-device-list','native',function(_,devices)
    devices=devices or catalog()
    local parts={}
    for _,device in ipairs(devices) do
        parts[#parts+1]=(device.name or '')..'|'..(device.description or '')
    end
    table.sort(parts)
    local signature=table.concat(parts,'\n')
    local next_target=target(devices)
    if signature~=last_signature then
        -- A disappearance and return inside the debounce window still forces reopen.
        local relevant=last_signature~=nil and
            (next_target~=last_target or next_target=='auto'
             or not exists(expected,devices) or not healthy())
        last_signature,last_target=signature,next_target
        exhausted=false
        schedule('device-list-changed',relevant)
    end
end)
mp.observe_property('audio-device','string',function(_,value)
    if value and value==mp.get_property('audio-device') and value~=expected then
        mode='manual'
        expected=value
        cancel_retry()
        exhausted=false
        route('manual-selection',false,false)
    end
end)
mp.observe_property('current-ao','string',function()
    if not loaded then return end
    if healthy() then status='ready'; exhausted=false; publish()
    elseif not recovering and not exhausted then schedule('output-lost',false) end
end)
mp.add_hook('on_load',2,function()
    loaded=false
    cancel_retry()
    exhausted=false
    if mode=='manual' and not exists(expected,catalog()) then mode='prefer-device' end
    route('file-loading',false,false)
end)
mp.register_event('file-loaded',function()
    loaded=true
    route('file-loaded',false,false)
end)
mp.register_event('end-file',function()
    loaded=false
    cancel_retry()
end)
-- Low-cost fallback check. No periodic AO reopening while output is healthy.
mp.add_periodic_timer(2,function()
    if not loaded or recovering then return end
    if exhausted then
        if mp.get_time()>=next_probe and exists(expected,catalog()) then
            reason='slow-output-retry'
            recover_output(false,true)
        end
    else route('health-check',false,false) end
end)
mp.register_script_message('select-minifuse',function(which)
    mode='prefer-device'
    mp.set_property_bool('audio-exclusive',which=='exclusive')
    route('minifuse-selected',true,true)
end)
mp.register_script_message('recover',function()
    mode='prefer-device'
    mp.set_property_bool('audio-exclusive',false)
    route('user-recover',true,true)
    mp.set_property_bool('mute',false)
end)
mp.register_script_message('system-default',function()
    mode='system-default'
    expected='auto'
    mp.set_property('audio-device','auto')
    mp.set_property_bool('audio-exclusive',false)
    route('system-default-selected',true,true)
end)
