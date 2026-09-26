-- macOS VLC 3 bridge: auto-load selected preset into visible A/B fields.
-- VLC 3 Lua dropdowns expose get_value() but no selection-change callback,
-- so RUN.command launches this accessibility watcher.

property lastPreset : ""

on findRole(theWindow, targetRole)
    set foundItems to {}
    try
        set allItems to entire contents of theWindow
        repeat with uiItem in allItems
            try
                if role of uiItem is targetRole then set end of foundItems to uiItem
            end try
        end repeat
    end try
    return foundItems
end findRole

repeat
    try
        tell application "System Events"
            if exists process "VLC" then
                tell process "VLC"
                    set targetWindow to missing value
                    repeat with w in windows
                        try
                            if name of w contains "Advanced A-B Looper" then
                                set targetWindow to w
                                exit repeat
                            end if
                        end try
                    end repeat

                    if targetWindow is not missing value then
                        set popups to my findRole(targetWindow, "AXPopUpButton")
                        set fields to my findRole(targetWindow, "AXTextField")

                        if (count of popups) ≥ 1 and (count of fields) ≥ 2 then
                            set presetText to value of item 1 of popups as text

                            if presetText is not lastPreset then
                                set lastPreset to presetText
                                if presetText starts with "#" then
                                    set oldDelims to AppleScript's text item delimiters
                                    set AppleScript's text item delimiters to " | "
                                    set parts to text items of presetText
                                    set AppleScript's text item delimiters to oldDelims

                                    if (count of parts) ≥ 3 then
                                        set value of item 1 of fields to item 2 of parts
                                        set value of item 2 of fields to item 3 of parts
                                    end if
                                end if
                            end if
                        end if
                    end if
                end tell
            end if
        end tell
    end try
    delay 0.15
end repeat
