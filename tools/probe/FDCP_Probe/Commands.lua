-- /fdcpp list | run <id> | runall | setml | give <slot> <candidate#> | roll | item <link> | ping|pingbig|burst <raid|guild|officer|party|whisper name> | export | reset
local ADDON, P = ...

local function Cmd(msg)
    local cmd, arg = string.match(msg or "", "^(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    if cmd == "list" or cmd == "" then
        local db = P.DB()
        P.Print(#P.order .. " checks:")
        for _, id in ipairs(P.order) do
            local c, r = P.checks[id], db.results[id]
            P.Print(string.format("%s [%s] %s - %s", id, c.area, c.title, r and tostring(r.result) or "not run"))
        end
    elseif cmd == "run" then
        local r, err = P.Run(string.upper(arg))
        if not r then P.Print(err) else P.Print(r.id .. ": " .. r.result .. " " .. r.details) end
    elseif cmd == "runall" then
        P.Print("ran " .. P.RunAll() .. " checks")
    elseif cmd == "setml" then
        local r = P.SetMasterLoot(); P.Print(r.id .. ": " .. r.result .. " " .. r.details)
    elseif cmd == "give" then
        local slot, cand = string.match(arg, "^(%d+)%s+(%d+)$")
        P.Give(slot, cand)
    elseif cmd == "roll" then
        local r = P.Roll(); P.Print(r.id .. ": " .. r.result .. " " .. r.details)
    elseif cmd == "item" then
        if arg == "" then P.Print("usage: /fdcpp item <shift-click an item link>"); return end
        P.ProbeItem(arg)
        for _, id in ipairs({ "S5b", "S5c" }) do local r = P.Run(id); P.Print(r.id .. ": " .. r.result .. " " .. r.details) end
    elseif cmd == "ping" or cmd == "pingbig" or cmd == "burst" then
        local fn = cmd == "ping" and P.Ping or (cmd == "pingbig" and P.PingBig or P.PingBurst)
        local r = fn(arg, 5); P.Print(r.id .. ": " .. r.result .. " " .. r.details)
    elseif cmd == "export" then
        P.ShowExport()
    elseif cmd == "reset" then
        P.Reset()
        P.Print("results and events cleared")
    else
        P.Print("/fdcpp list | run <id> | runall | setml | give <slot> <candidate#> | roll | item <link> | ping|pingbig|burst <raid|guild|officer|party|whisper name> | export | reset")
    end
end

SLASH_FDCPP1 = "/fdcpp"
SlashCmdList["FDCPP"] = function(msg) local ok, err = pcall(Cmd, msg); if not ok then P.Print("error: " .. tostring(err)) end end
