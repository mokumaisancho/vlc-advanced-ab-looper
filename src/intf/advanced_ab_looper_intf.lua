-- Advanced A-B Looper helper interface for VLC 3.x
-- Runtime state is track-bound by exact media URI.
-- The helper refuses to loop if the playing item differs from the armed track.

local STATE_FILE = vlc.config.userdatadir() .. "/advanced_ab_looper.state"
local RUNTIME_FILE = vlc.config.userdatadir() .. "/advanced_ab_looper.runtime"

local POLL_US = 5000
local STATE_REFRESH_US = 100000
local SAFETY_MARGIN_US = 20000
local SEEK_GUARD_US = 50000
local RUNTIME_WRITE_US = 50000

local state = {
    enabled = false,
    track_uri = nil,
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

local function current_uri()
    local item = vlc.input.item()
    if not item then return nil end
    return item:uri()
end

local function read_state()
    local f = vlc.io.open(STATE_FILE, "r")
    if not f then
        state = {enabled = false, track_uri = nil, start_us = nil, end_us = nil}
        return
    end

    local p = {}
    local content = f:read("*all") or ""
    f = nil

    for line in content:gmatch("[^\r\n]+") do
        local k, v = line:match("^([%w_]+)=(.-)$")
        if k then p[k] = v end
    end

    local enabled = p.enabled == "1"
    local uri = p.track_uri
    local a = tonumber(p.active_start_us)
    local b = tonumber(p.active_end_us)

    if tonumber(p.version) ~= 4
        or not uri or uri == ""
        or not (a and b and a >= 0 and b > a) then
        enabled = false
        uri, a, b = nil, nil, nil
    end

    state = {
        enabled = enabled,
        track_uri = uri,
        start_us = a,
        end_us = b
    }
end

local function write_runtime(t, uri, track_matches)
    local f = vlc.io.open(RUNTIME_FILE, "w")
    if not f then return end

    f:write("current_us=" .. tostring(t or 0) .. "\n")
    f:write("current_text=" .. format_time(t or 0) .. "\n")
    f:write("current_uri=" .. tostring(uri or "") .. "\n")
    f:write("armed_uri=" .. tostring(state.track_uri or "") .. "\n")
    f:write("track_matches=" .. (track_matches and "1" or "0") .. "\n")
    f:write("enabled=" .. (state.enabled and "1" or "0") .. "\n")
    f:write("active_start_us=" .. tostring(state.start_us or 0) .. "\n")
    f:write("active_end_us=" .. tostring(state.end_us or 0) .. "\n")
    f:flush()
    f = nil
end

vlc.msg.info("[Advanced A-B Looper] v2.4 helper started")

while true do
    local now = vlc.misc.mdate()

    if now >= next_state_read then
        read_state()
        next_state_read = now + STATE_REFRESH_US
    end

    local input = vlc.object.input()
    if input then
        local t = vlc.var.get(input, "time")
        local uri = current_uri()
        local track_matches =
            state.track_uri ~= nil and uri ~= nil and state.track_uri == uri

        if t then
            if state.enabled and track_matches and state.start_us and state.end_us then
                local trigger = state.end_us - SAFETY_MARGIN_US
                if trigger < state.start_us then trigger = state.end_us end

                if t >= trigger and now - last_seek_at >= SEEK_GUARD_US then
                    vlc.var.set(input, "time", state.start_us)
                    last_seek_at = now
                end
            end

            if now >= next_runtime_write then
                write_runtime(t, uri, track_matches)
                next_runtime_write = now + RUNTIME_WRITE_US
            end
        end
    end

    vlc.misc.mwait(vlc.misc.mdate() + POLL_US)
end
