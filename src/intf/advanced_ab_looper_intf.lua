-- Advanced A-B Looper helper interface for VLC 3.x
-- Runtime looping is driven only by active_start_us / active_end_us.
-- Saved presets are ignored by the engine.

local STATE_FILE = vlc.config.userdatadir() .. "/advanced_ab_looper.state"
local RUNTIME_FILE = vlc.config.userdatadir() .. "/advanced_ab_looper.runtime"

local POLL_US = 5000             -- 5 ms
local STATE_REFRESH_US = 100000  -- 100 ms control-plane refresh
local SAFETY_MARGIN_US = 20000   -- seek 20 ms before B to avoid observable overshoot
local SEEK_GUARD_US = 50000
local RUNTIME_WRITE_US = 50000

local state = {
    enabled = false,
    start_us = nil,
    end_us = nil
}

local next_state_read = 0
local last_seek_at = 0
local next_runtime_write = 0

local function format_time(us)
    us = tonumber(us) or 0
    local total_ms = math.floor(us / 1000 + 0.5)
    local ms = total_ms % 1000
    local total_s = math.floor(total_ms / 1000)
    local s = total_s % 60
    local total_m = math.floor(total_s / 60)
    local m = total_m % 60
    local h = math.floor(total_m / 60)
    return string.format("%02d:%02d:%02d.%03d", h, m, s, ms)
end

local function read_state()
    local f = vlc.io.open(STATE_FILE, "r")
    if not f then
        state = {enabled = false, start_us = nil, end_us = nil}
        return
    end

    local p = {}
    local content = f:read("*all") or ""
    f = nil

    for line in content:gmatch("[^\r\n]+") do
        local k, v = line:match("^([%w_]+)=(.-)$")
        if k then p[k] = v end
    end

    local version = tonumber(p.version) or 0
    local enabled = p.enabled == "1"
    local a, b

    if version >= 3 then
        a = tonumber(p.active_start_us)
        b = tonumber(p.active_end_us)
    elseif version == 2 then
        -- Backward compatibility only: derive the old active preset once.
        local old_id = tonumber(p.active_id) or 0
        local n = tonumber(p.loop_count) or 0
        for i = 1, n do
            local id = tonumber(p["loop_" .. i .. "_id"])
            if id == old_id then
                a = tonumber(p["loop_" .. i .. "_start_us"])
                b = tonumber(p["loop_" .. i .. "_end_us"])
                break
            end
        end
    end

    if not (a and b and a >= 0 and b > a) then
        enabled = false
        a, b = nil, nil
    end

    state = {
        enabled = enabled,
        start_us = a,
        end_us = b
    }
end

local function write_runtime(t)
    local f = vlc.io.open(RUNTIME_FILE, "w")
    if not f then return end

    f:write("current_us=" .. tostring(t or 0) .. "\n")
    f:write("current_text=" .. format_time(t or 0) .. "\n")
    f:write("enabled=" .. (state.enabled and "1" or "0") .. "\n")
    f:write("active_start_us=" .. tostring(state.start_us or 0) .. "\n")
    f:write("active_end_us=" .. tostring(state.end_us or 0) .. "\n")
    f:flush()
    f = nil
end

vlc.msg.info("[Advanced A-B Looper] v2.3 helper started")

while true do
    local now = vlc.misc.mdate()

    if now >= next_state_read then
        read_state()
        next_state_read = now + STATE_REFRESH_US
    end

    local input = vlc.object.input()
    if input then
        local t = vlc.var.get(input, "time")
        if t then
            if state.enabled and state.start_us and state.end_us then
                local trigger = state.end_us - SAFETY_MARGIN_US
                if trigger < state.start_us then trigger = state.end_us end

                if t >= trigger and now - last_seek_at >= SEEK_GUARD_US then
                    vlc.var.set(input, "time", state.start_us)
                    last_seek_at = now
                end
            end

            if now >= next_runtime_write then
                write_runtime(t)
                next_runtime_write = now + RUNTIME_WRITE_US
            end
        end
    end

    vlc.misc.mwait(vlc.misc.mdate() + POLL_US)
end
