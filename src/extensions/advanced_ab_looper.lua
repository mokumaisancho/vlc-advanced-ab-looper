-- Advanced A-B Looper for VLC 3.x - track-scoped preset library
-- Runtime source of truth: the visible A/B fields.
-- Persistent presets are stored per absolute media path in one JSON file.

local dlg
local start_input, end_input, loop_selector
local status_label, current_label, active_label, track_label, library_label

local LIBRARY_FILE = vlc.config.userdatadir() .. "/advanced_ab_looper_library.json"
local STATE_FILE = vlc.config.userdatadir() .. "/advanced_ab_looper.state"

local library = {version = 1, tracks = {}}
local loops = {}
local next_id = 1
local current_path = nil
local current_uri = nil
local enabled = false
local active_start_us = nil
local active_end_us = nil

function descriptor()
    return {
        title = "Advanced A-B Looper",
        version = "2.4.0",
        author = "OpenAI",
        shortdesc = "Track-scoped time-specified A-B looper",
        description = "A/B fields drive the loop. Presets are isolated by absolute media path.",
        capabilities = {"input-listener"}
    }
end

local function trim(s)
    if not s then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

local function parse_time(text)
    text = trim(text):gsub(",", ".")
    if text == "" then return nil end

    local h, m, s = text:match("^(%d+):(%d+):(%d+%.?%d*)$")
    if h then
        h, m, s = tonumber(h), tonumber(m), tonumber(s)
        if m >= 60 or s >= 60 then return nil end
        return math.floor((h * 3600 + m * 60 + s) * 1000000 + 0.5)
    end

    m, s = text:match("^(%d+):(%d+%.?%d*)$")
    if m then
        m, s = tonumber(m), tonumber(s)
        if s >= 60 then return nil end
        return math.floor((m * 60 + s) * 1000000 + 0.5)
    end

    local seconds = tonumber(text)
    if seconds and seconds >= 0 then
        return math.floor(seconds * 1000000 + 0.5)
    end
    return nil
end

local function format_time(us)
    us = tonumber(us) or 0
    if us < 0 then us = 0 end
    local total_ms = math.floor(us / 1000 + 0.5)
    local ms = total_ms % 1000
    local total_s = math.floor(total_ms / 1000)
    local s = total_s % 60
    local total_m = math.floor(total_s / 60)
    local m = total_m % 60
    local h = math.floor(total_m / 60)
    return string.format("%02d:%02d:%02d.%03d", h, m, s, ms)
end

local function json_quote(s)
    s = tostring(s or "")
    local out = {'"'}
    for i = 1, #s do
        local c = s:sub(i, i)
        local b = string.byte(c)
        if c == '"' then
            out[#out + 1] = '\\"'
        elseif c == "\\" then
            out[#out + 1] = "\\\\"
        elseif c == "\b" then
            out[#out + 1] = "\\b"
        elseif c == "\f" then
            out[#out + 1] = "\\f"
        elseif c == "\n" then
            out[#out + 1] = "\\n"
        elseif c == "\r" then
            out[#out + 1] = "\\r"
        elseif c == "\t" then
            out[#out + 1] = "\\t"
        elseif b < 32 then
            out[#out + 1] = string.format("\\u%04x", b)
        else
            out[#out + 1] = c
        end
    end
    out[#out + 1] = '"'
    return table.concat(out)
end

local function json_unescape(s)
    local out = {}
    local i = 1
    while i <= #s do
        local c = s:sub(i, i)
        if c ~= "\\" then
            out[#out + 1] = c
            i = i + 1
        else
            local e = s:sub(i + 1, i + 1)
            if e == '"' or e == "\\" or e == "/" then
                out[#out + 1] = e
                i = i + 2
            elseif e == "b" then
                out[#out + 1] = "\b"
                i = i + 2
            elseif e == "f" then
                out[#out + 1] = "\f"
                i = i + 2
            elseif e == "n" then
                out[#out + 1] = "\n"
                i = i + 2
            elseif e == "r" then
                out[#out + 1] = "\r"
                i = i + 2
            elseif e == "t" then
                out[#out + 1] = "\t"
                i = i + 2
            elseif e == "u" then
                local hex = s:sub(i + 2, i + 5)
                local n = tonumber(hex, 16)
                if n and n < 128 then
                    out[#out + 1] = string.char(n)
                else
                    out[#out + 1] = "?"
                end
                i = i + 6
            else
                out[#out + 1] = e
                i = i + 2
            end
        end
    end
    return table.concat(out)
end

local function load_library()
    library = {version = 1, tracks = {}}
    local f = vlc.io.open(LIBRARY_FILE, "r")
    if not f then return true end

    local content = f:read("*all") or ""
    f = nil

    for line in content:gmatch("[^\r\n]+") do
        local escaped_path, loop_blob =
            line:match('^%s*{"path":"(.-)","loops":%[(.-)%]}%,?%s*$')
        if escaped_path and loop_blob then
            local path = json_unescape(escaped_path)
            local entry = {loops = {}}
            for id, a, b in loop_blob:gmatch(
                '{"id":(%d+),"start_us":(%d+),"end_us":(%d+)}'
            ) do
                id, a, b = tonumber(id), tonumber(a), tonumber(b)
                if id and a and b and a >= 0 and b > a then
                    entry.loops[#entry.loops + 1] = {
                        id = id,
                        start_us = a,
                        end_us = b
                    }
                end
            end
            library.tracks[path] = entry
        end
    end
    return true
end

local function save_library()
    local tmp = LIBRARY_FILE .. ".tmp"
    local f = vlc.io.open(tmp, "w")
    if not f then return false, "Cannot write loop library" end

    local paths = {}
    for path, entry in pairs(library.tracks) do
        if entry and entry.loops and #entry.loops > 0 then
            paths[#paths + 1] = path
        end
    end
    table.sort(paths)

    f:write("{\n  \"version\":1,\n  \"tracks\":[\n")
    for pi, path in ipairs(paths) do
        local entry = library.tracks[path]
        table.sort(entry.loops, function(a, b) return a.id < b.id end)

        f:write("    {\"path\":" .. json_quote(path) .. ",\"loops\":[")
        for i, lp in ipairs(entry.loops) do
            if i > 1 then f:write(",") end
            f:write(string.format(
                '{"id":%d,"start_us":%d,"end_us":%d}',
                lp.id, lp.start_us, lp.end_us
            ))
        end
        f:write("]}")
        if pi < #paths then f:write(",") end
        f:write("\n")
    end
    f:write("  ]\n}\n")
    f:flush()
    f = nil

    os.remove(LIBRARY_FILE)
    local ok = os.rename(tmp, LIBRARY_FILE)
    if not ok then return false, "Cannot replace loop library" end
    return true
end

local function current_media()
    local item = vlc.input.item()
    if not item then return nil, nil end
    local uri = item:uri()
    if not uri then return nil, nil end
    local path = vlc.strings.make_path(uri)
    if not path or path == "" or path:sub(1, 1) ~= "/" then
        return nil, uri
    end
    return path, uri
end

local function write_runtime_state(on, a, b, uri)
    local tmp = STATE_FILE .. ".tmp"
    local f = vlc.io.open(tmp, "w")
    if not f then return false, "Cannot write runtime state" end

    f:write("version=4\n")
    f:write("enabled=" .. (on and "1" or "0") .. "\n")
    f:write("track_uri=" .. tostring(uri or "") .. "\n")
    f:write("active_start_us=" .. tostring(a or 0) .. "\n")
    f:write("active_end_us=" .. tostring(b or 0) .. "\n")
    f:flush()
    f = nil

    os.remove(STATE_FILE)
    local ok = os.rename(tmp, STATE_FILE)
    if not ok then return false, "Cannot replace runtime state" end
    return true
end

local function read_runtime_state()
    local f = vlc.io.open(STATE_FILE, "r")
    if not f then return end
    local p = {}
    local content = f:read("*all") or ""
    f = nil
    for line in content:gmatch("[^\r\n]+") do
        local k, v = line:match("^([%w_]+)=(.-)$")
        if k then p[k] = v end
    end

    if tonumber(p.version) ~= 4 or p.track_uri ~= current_uri then
        enabled = false
        active_start_us = nil
        active_end_us = nil
        return
    end

    local a = tonumber(p.active_start_us)
    local b = tonumber(p.active_end_us)
    enabled = p.enabled == "1" and a and b and a >= 0 and b > a
    if a and b and a >= 0 and b > a then
        active_start_us = a
        active_end_us = b
    else
        active_start_us = nil
        active_end_us = nil
        enabled = false
    end
end

local function set_status(s)
    if status_label then status_label:set_text(s) end
    if dlg then dlg:update() end
end

local function find_loop(id)
    for i, lp in ipairs(loops) do
        if lp.id == id then return lp, i end
    end
    return nil, nil
end

local function selected_id()
    if not loop_selector then return nil end
    local id = loop_selector:get_value()
    if not id or id == 0 then return nil end
    return tonumber(id)
end

local function refresh_active_label()
    if not active_label then return end
    if active_start_us and active_end_us and active_end_us > active_start_us then
        active_label:set_text(string.format(
            "ACTIVE: %s -> %s   |   LOOP %s",
            format_time(active_start_us),
            format_time(active_end_us),
            enabled and "ON" or "OFF"
        ))
    else
        active_label:set_text("ACTIVE: none   |   LOOP OFF")
    end
end

local function refresh_selector()
    if not loop_selector then return end
    loop_selector:clear()
    table.sort(loops, function(a, b) return a.id < b.id end)
    loop_selector:add_value("Select preset...", 0)
    for _, lp in ipairs(loops) do
        loop_selector:add_value(
            string.format("#%d | %s | %s",
                lp.id, format_time(lp.start_us), format_time(lp.end_us)),
            lp.id
        )
    end
    refresh_active_label()
    if dlg then dlg:update() end
end

local function rebuild_track_context(force_clear)
    local new_path, new_uri = current_media()
    local changed = new_path ~= current_path or new_uri ~= current_uri

    current_path = new_path
    current_uri = new_uri
    loops = {}
    next_id = 1

    if current_path then
        local entry = library.tracks[current_path]
        if entry and entry.loops then
            loops = entry.loops
            local max_id = 0
            for _, lp in ipairs(loops) do
                if lp.id > max_id then max_id = lp.id end
            end
            next_id = max_id + 1
        end
    end

    if track_label then
        if current_path then
            track_label:set_text("TRACK: " .. current_path)
        elseif current_uri then
            track_label:set_text("TRACK: non-local media (presets disabled)")
        else
            track_label:set_text("TRACK: no media")
        end
    end

    if changed or force_clear then
        enabled = false
        active_start_us = nil
        active_end_us = nil
        write_runtime_state(false, nil, nil, current_uri)

        if start_input then start_input:set_text("") end
        if end_input then end_input:set_text("") end
    else
        read_runtime_state()
        if start_input and active_start_us and active_end_us then
            start_input:set_text(format_time(active_start_us))
            end_input:set_text(format_time(active_end_us))
        end
    end

    refresh_selector()
end

local function ensure_local_track()
    if not current_path or not current_uri then
        return false, "A local file is required for track-scoped loops"
    end
    return true
end

local function validate_inputs()
    local a = parse_time(start_input:get_text())
    local b = parse_time(end_input:get_text())
    if not a then return nil, nil, "Invalid A time" end
    if not b then return nil, nil, "Invalid B time" end
    if b <= a then return nil, nil, "B must be later than A" end
    return a, b, nil
end

local function persist_current_track()
    if not current_path then return false, "No local track" end
    if #loops == 0 then
        library.tracks[current_path] = nil
    else
        library.tracks[current_path] = {loops = loops}
    end
    return save_library()
end

function add_loop()
    local ok_track, msg_track = ensure_local_track()
    if not ok_track then set_status(msg_track); return end

    local a, b, err = validate_inputs()
    if err then set_status(err); return end

    loops[#loops + 1] = {id = next_id, start_us = a, end_us = b}
    local id = next_id
    next_id = next_id + 1

    local ok, msg = persist_current_track()
    if not ok then set_status(msg); return end
    refresh_selector()
    set_status("Saved preset #" .. id .. " for this track only")
end

function update_loop()
    local ok_track, msg_track = ensure_local_track()
    if not ok_track then set_status(msg_track); return end

    local id = selected_id()
    if not id then set_status("Select a preset to update"); return end
    local lp = find_loop(id)
    if not lp then set_status("Selected preset not found"); return end

    local a, b, err = validate_inputs()
    if err then set_status(err); return end

    lp.start_us, lp.end_us = a, b
    local ok, msg = persist_current_track()
    if not ok then set_status(msg); return end
    refresh_selector()
    set_status("Updated preset #" .. id .. " from visible A/B")
end

function delete_loop()
    local ok_track, msg_track = ensure_local_track()
    if not ok_track then set_status(msg_track); return end

    local id = selected_id()
    if not id then set_status("Select a preset to delete"); return end
    local _, idx = find_loop(id)
    if not idx then set_status("Selected preset not found"); return end

    table.remove(loops, idx)
    local ok, msg = persist_current_track()
    if not ok then set_status(msg); return end
    refresh_selector()
    set_status("Deleted preset #" .. id .. "; active loop unchanged")
end

function activate_screen()
    local ok_track, msg_track = ensure_local_track()
    if not ok_track then set_status(msg_track); return end

    local a, b, err = validate_inputs()
    if err then set_status(err); return end

    active_start_us = a
    active_end_us = b
    enabled = true

    local ok, msg = write_runtime_state(true, a, b, current_uri)
    if not ok then
        enabled = false
        set_status(msg)
        return
    end

    local input = vlc.object.input()
    if input then vlc.var.set(input, "time", a) end

    refresh_active_label()
    if dlg then dlg:update() end
    set_status("LOOP ON: visible A/B applied to this track")
end

function stop_loop()
    enabled = false
    local ok, msg = write_runtime_state(false, active_start_us, active_end_us, current_uri)
    if not ok then set_status(msg); return end
    refresh_active_label()
    if dlg then dlg:update() end
    set_status("LOOP OFF")
end

local function current_time_us()
    local input = vlc.object.input()
    if not input then return nil end
    return vlc.var.get(input, "time")
end

function refresh_current()
    local us = current_time_us()
    if not us then
        current_label:set_text("CURRENT: no media")
    else
        current_label:set_text(
            "CURRENT: " .. format_time(us) .. "   (" .. tostring(us) .. " us)"
        )
    end
    if dlg then dlg:update() end
end

function set_a_current()
    local us = current_time_us()
    if not us then set_status("No media playing"); return end
    start_input:set_text(format_time(us))
    refresh_current()
end

function set_b_current()
    local us = current_time_us()
    if not us then set_status("No media playing"); return end
    end_input:set_text(format_time(us))
    refresh_current()
end

function input_changed()
    -- Hard isolation: a new media item never inherits the previous item's loop.
    load_library()
    rebuild_track_context(true)
    refresh_current()
    set_status("Track changed: loaded only presets for the current absolute path")
end

function activate()
    load_library()

    dlg = vlc.dialog("Advanced A-B Looper")

    track_label = dlg:add_label("TRACK: no media", 1, 1, 6, 1, 560, 24)
    current_label = dlg:add_label("CURRENT: --:--:--.---", 1, 2, 4, 1, 420, 24)
    dlg:add_button("Refresh", refresh_current, 5, 2, 1, 1, 90, 28)

    dlg:add_label("A", 1, 3, 1, 1, 20, 24)
    start_input = dlg:add_text_input("", 2, 3, 3, 1, 250, 28)
    dlg:add_button("Current -> A", set_a_current, 5, 3, 1, 1, 110, 28)

    dlg:add_label("B", 1, 4, 1, 1, 20, 24)
    end_input = dlg:add_text_input("", 2, 4, 3, 1, 250, 28)
    dlg:add_button("Current -> B", set_b_current, 5, 4, 1, 1, 110, 28)

    dlg:add_label("Saved presets", 1, 5, 1, 1, 90, 24)
    loop_selector = dlg:add_dropdown(2, 5, 4, 1, 350, 28)

    dlg:add_button("Save New", add_loop, 1, 6, 1, 1, 85, 28)
    dlg:add_button("Update", update_loop, 2, 6, 1, 1, 75, 28)
    dlg:add_button("Delete", delete_loop, 3, 6, 1, 1, 75, 28)
    dlg:add_button("LOOP ON", activate_screen, 5, 6, 1, 1, 90, 28)
    dlg:add_button("LOOP OFF", stop_loop, 6, 6, 1, 1, 90, 28)

    active_label = dlg:add_label("ACTIVE: none   |   LOOP OFF", 1, 7, 6, 1, 560, 24)
    library_label = dlg:add_label("DB: " .. LIBRARY_FILE, 1, 8, 6, 1, 560, 24)
    status_label = dlg:add_label("Selecting a preset fills A/B automatically", 1, 9, 6, 1, 560, 24)

    rebuild_track_context(false)
    refresh_current()
end

function deactivate() end
function close() deactivate() end
