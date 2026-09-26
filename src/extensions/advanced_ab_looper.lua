-- Advanced A-B Looper for VLC 3.x - compact multi-loop UI
-- Requires advanced_ab_looper_intf.lua running as a Lua interface.

local dlg
local start_input, end_input, loop_selector
local status_label, current_label, active_label
local loops = {}
local next_id = 1
local enabled = false
local active_id = 0
local STATE_FILE, RUNTIME_FILE

function descriptor()
    return {
        title = "Advanced A-B Looper",
        version = "2.2.0",
        author = "OpenAI",
        shortdesc = "Multi time-specified A-B loop",
        description = "Store multiple A-B ranges and activate one exact loop at a time in VLC 3.x.",
        capabilities = {}
    }
end

local function state_path()
    if not STATE_FILE then STATE_FILE = vlc.config.userdatadir() .. "/advanced_ab_looper.state" end
    return STATE_FILE
end
local function runtime_path()
    if not RUNTIME_FILE then RUNTIME_FILE = vlc.config.userdatadir() .. "/advanced_ab_looper.runtime" end
    return RUNTIME_FILE
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
    if seconds and seconds >= 0 then return math.floor(seconds * 1000000 + 0.5) end
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

local function sort_loops()
    table.sort(loops, function(a,b) return a.id < b.id end)
end

local function find_loop(id)
    for i, lp in ipairs(loops) do if lp.id == id then return lp, i end end
    return nil, nil
end

local function selected_id()
    if not loop_selector then return nil end
    local id = loop_selector:get_value()
    if not id or id == 0 then return nil end
    return tonumber(id)
end

local function set_status(s)
    if status_label then status_label:set_text(s) end
    if dlg then dlg:update() end
end

local function write_state()
    local tmp = state_path() .. ".tmp"
    local f = vlc.io.open(tmp, "w")
    if not f then return false, "Cannot write state file" end
    sort_loops()
    f:write("version=2\n")
    f:write("enabled=" .. (enabled and "1" or "0") .. "\n")
    f:write("active_id=" .. tostring(active_id or 0) .. "\n")
    f:write("loop_count=" .. tostring(#loops) .. "\n")
    for i, lp in ipairs(loops) do
        f:write("loop_"..i.."_id="..tostring(lp.id).."\n")
        f:write("loop_"..i.."_start_us="..tostring(lp.start_us).."\n")
        f:write("loop_"..i.."_end_us="..tostring(lp.end_us).."\n")
    end
    f:flush()
    f = nil
    os.remove(state_path())
    local ok = os.rename(tmp, state_path())
    if not ok then return false, "Cannot replace state file" end
    return true
end

local function refresh_selector()
    loop_selector:clear()
    sort_loops()
    loop_selector:add_value("Select loop...", 0)
    for _, lp in ipairs(loops) do
        local marker = ""
        if lp.id == active_id then marker = enabled and " [ON]" or " [ACTIVE]" end
        local text = string.format("#%d  %s -> %s%s", lp.id, format_time(lp.start_us), format_time(lp.end_us), marker)
        loop_selector:add_value(text, lp.id)
    end
    if active_id ~= 0 then
        local lp = find_loop(active_id)
        if lp then
            active_label:set_text(string.format("ACTIVE #%d   %s -> %s   |   LOOP %s",
                active_id, format_time(lp.start_us), format_time(lp.end_us), enabled and "ON" or "OFF"))
        else
            active_label:set_text("ACTIVE: none   |   LOOP OFF")
        end
    else
        active_label:set_text("ACTIVE: none   |   LOOP OFF")
    end
    dlg:update()
end

local function load_state()
    local f = vlc.io.open(state_path(), "r")
    if not f then return end
    local p = {}
    local content = f:read("*all") or ""
    f = nil
    for line in content:gmatch("[^\r\n]+") do
        local k,v = line:match("^([%w_]+)=(.-)$")
        if k then p[k]=v end
    end
    if tonumber(p.version) ~= 2 then return end
    enabled = p.enabled == "1"
    active_id = tonumber(p.active_id) or 0
    loops = {}
    local n = tonumber(p.loop_count) or 0
    local max_id = 0
    for i=1,n do
        local id = tonumber(p["loop_"..i.."_id"])
        local a = tonumber(p["loop_"..i.."_start_us"])
        local b = tonumber(p["loop_"..i.."_end_us"])
        if id and a and b and a >= 0 and b > a then
            table.insert(loops, {id=id, start_us=a, end_us=b})
            if id > max_id then max_id=id end
        end
    end
    next_id = max_id + 1
end

local function validate_inputs()
    local a = parse_time(start_input:get_text())
    local b = parse_time(end_input:get_text())
    if not a then return nil,nil,"Invalid A time" end
    if not b then return nil,nil,"Invalid B time" end
    if b <= a then return nil,nil,"B must be later than A" end
    return a,b,nil
end

function add_loop()
    local a,b,err = validate_inputs()
    if err then set_status(err); return end
    table.insert(loops, {id=next_id, start_us=a, end_us=b})
    local id = next_id
    next_id = next_id + 1
    local ok,msg = write_state()
    if not ok then set_status(msg); return end
    refresh_selector()
    set_status("Added loop #"..id)
end

function update_loop()
    local id = selected_id()
    if not id then set_status("Select one loop to update"); return end
    local lp = find_loop(id)
    if not lp then set_status("Selected loop not found"); return end
    local a,b,err = validate_inputs()
    if err then set_status(err); return end
    lp.start_us, lp.end_us = a,b
    local ok,msg = write_state()
    if not ok then set_status(msg); return end
    refresh_selector()
    set_status("Updated loop #"..id)
end

function delete_loop()
    local id = selected_id()
    if not id then set_status("Select one loop to delete"); return end
    local _, idx = find_loop(id)
    if not idx then set_status("Selected loop not found"); return end
    table.remove(loops, idx)
    if active_id == id then active_id=0; enabled=false end
    local ok,msg = write_state()
    if not ok then set_status(msg); return end
    refresh_selector()
    set_status("Deleted loop #"..id)
end

function load_selected()
    local id = selected_id()
    if not id then set_status("Select one loop"); return end
    local lp = find_loop(id)
    if not lp then return end
    start_input:set_text(format_time(lp.start_us))
    end_input:set_text(format_time(lp.end_us))
    set_status("Loaded loop #"..id)
end

function activate_selected()
    local id = selected_id()
    if not id then set_status("Select one loop to activate"); return end
    local lp = find_loop(id)
    if not lp then return end
    active_id=id; enabled=true
    local ok,msg = write_state()
    if not ok then set_status(msg); return end
    local input = vlc.object.input()
    if input then vlc.var.set(input, "time", lp.start_us) end
    refresh_selector()
    set_status("LOOP ON: #"..id)
end

function stop_loop()
    enabled=false
    local ok,msg=write_state()
    if not ok then set_status(msg); return end
    refresh_selector()
    set_status("LOOP OFF")
end

local function current_time_us()
    local input=vlc.object.input()
    if not input then return nil end
    return vlc.var.get(input, "time")
end

function refresh_current()
    local us=current_time_us()
    if not us then current_label:set_text("CURRENT: no media"); dlg:update(); return end
    current_label:set_text("CURRENT: "..format_time(us).."   ("..tostring(us).." us)")
    dlg:update()
end

function set_a_current()
    local us=current_time_us()
    if not us then set_status("No media playing"); return end
    start_input:set_text(format_time(us)); refresh_current()
end

function set_b_current()
    local us=current_time_us()
    if not us then set_status("No media playing"); return end
    end_input:set_text(format_time(us)); refresh_current()
end

function activate()
    load_state()
    dlg=vlc.dialog("Advanced A-B Looper")

    current_label=dlg:add_label("CURRENT: --:--:--.---",1,1,4,1,420,24)
    dlg:add_button("Refresh",refresh_current,5,1,1,1,90,28)

    dlg:add_label("A",1,2,1,1,20,24)
    start_input=dlg:add_text_input("00:11:11.000",2,2,3,1,250,28)
    dlg:add_button("Current -> A",set_a_current,5,2,1,1,110,28)

    dlg:add_label("B",1,3,1,1,20,24)
    end_input=dlg:add_text_input("00:11:14.000",2,3,3,1,250,28)
    dlg:add_button("Current -> B",set_b_current,5,3,1,1,110,28)

    dlg:add_label("Saved loops",1,4,1,1,80,24)
    loop_selector=dlg:add_dropdown(2,4,4,1,350,28)

    dlg:add_button("Add",add_loop,1,5,1,1,75,28)
    dlg:add_button("Update",update_loop,2,5,1,1,75,28)
    dlg:add_button("Delete",delete_loop,3,5,1,1,75,28)
    dlg:add_button("Load",load_selected,4,5,1,1,75,28)
    dlg:add_button("LOOP ON",activate_selected,5,5,1,1,90,28)
    dlg:add_button("LOOP OFF",stop_loop,6,5,1,1,90,28)

    active_label=dlg:add_label("ACTIVE: none   |   LOOP OFF",1,6,6,1,520,24)
    status_label=dlg:add_label("Ready",1,7,6,1,520,24)

    refresh_selector()
    refresh_current()
end

function deactivate() end
function close() deactivate() end
