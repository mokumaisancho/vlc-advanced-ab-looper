-- Advanced A-B Looper helper interface for VLC 3.x - multi-loop engine
-- High-frequency boundary watcher. Only the active loop is executed.

local STATE_FILE = vlc.config.userdatadir() .. "/advanced_ab_looper.state"
local RUNTIME_FILE = vlc.config.userdatadir() .. "/advanced_ab_looper.runtime"
local POLL_US = 5000             -- 5 ms
local STATE_REFRESH_US = 100000  -- 100 ms; avoid disk reads every poll
local SAFETY_MARGIN_US = 20000   -- seek 20 ms before B to avoid observable B overshoot
local SEEK_GUARD_US = 50000
local RUNTIME_WRITE_US = 50000

local state={enabled=false,active_id=0,loops={}}
local next_state_read=0
local last_seek_at=0
local next_runtime_write=0

local function format_time(us)
    us=tonumber(us) or 0
    local total_ms=math.floor(us/1000+0.5)
    local ms=total_ms%1000
    local total_s=math.floor(total_ms/1000)
    local s=total_s%60
    local total_m=math.floor(total_s/60)
    local m=total_m%60
    local h=math.floor(total_m/60)
    return string.format("%02d:%02d:%02d.%03d",h,m,s,ms)
end

local function read_state()
    local f=vlc.io.open(STATE_FILE,"r")
    if not f then return end
    local p={}
    local content = f:read("*all") or ""
    f = nil
    for line in content:gmatch("[^\r\n]+") do
        local k,v=line:match("^([%w_]+)=(.-)$")
        if k then p[k]=v end
    end
    if tonumber(p.version) ~= 2 then return end
    local n=tonumber(p.loop_count) or 0
    local parsed={}
    for i=1,n do
        local id=tonumber(p["loop_"..i.."_id"])
        local a=tonumber(p["loop_"..i.."_start_us"])
        local b=tonumber(p["loop_"..i.."_end_us"])
        if id and a and b and a>=0 and b>a then parsed[id]={start_us=a,end_us=b} end
    end
    state={enabled=p.enabled=="1",active_id=tonumber(p.active_id) or 0,loops=parsed}
end

local function write_runtime(t)
    local f=vlc.io.open(RUNTIME_FILE,"w")
    if not f then return end
    f:write("current_us="..tostring(t or 0).."\n")
    f:write("current_text="..format_time(t or 0).."\n")
    f:write("enabled="..(state.enabled and "1" or "0").."\n")
    f:write("active_id="..tostring(state.active_id or 0).."\n")
    f:flush()
    f = nil
end

vlc.msg.info("[Advanced A-B Looper] v2.1 helper started")
while true do
    local now=vlc.misc.mdate()
    if now >= next_state_read then
        read_state()
        next_state_read=now+STATE_REFRESH_US
    end
    local input=vlc.object.input()
    if input then
        local t=vlc.var.get(input,"time")
        if t then
            if state.enabled then
                local lp=state.loops[state.active_id]
                if lp then
                    local trigger=lp.end_us-SAFETY_MARGIN_US
                    if trigger < lp.start_us then trigger=lp.end_us end
                    if t >= trigger and now-last_seek_at >= SEEK_GUARD_US then
                        vlc.var.set(input,"time",lp.start_us)
                        last_seek_at=now
                    end
                end
            end
            if now >= next_runtime_write then
                write_runtime(t)
                next_runtime_write=now+RUNTIME_WRITE_US
            end
        end
    end
    vlc.misc.mwait(vlc.misc.mdate()+POLL_US)
end
