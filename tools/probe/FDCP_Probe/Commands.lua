-- /fdcpp list | run <id> | runall | setml | give <slot> <candidate#> | export | reset
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
    elseif cmd == "export" then
        P.ShowExport()
    elseif cmd == "reset" then
        P.Reset()
        P.Print("results and events cleared")
    else
        P.Print("/fdcpp list | run <id> | runall | setml | give <slot> <candidate#> | export | reset")
    end
end

SLASH_FDCPP1 = "/fdcpp"
SlashCmdList["FDCPP"] = function(msg) local ok, err = pcall(Cmd, msg); if not ok then P.Print("error: " .. tostring(err)) end end
