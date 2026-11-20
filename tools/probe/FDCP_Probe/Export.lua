-- Export frame: all results (and the recorded events) as selected text, to copy and send to the owner's notes.
local ADDON, P = ...

function P.BuildExport()
    local db = P.DB()
    local lines = { "FDCPP export build=" .. P.Build() .. " checks=" .. #P.order }
    for _, id in ipairs(P.order) do
        local r = db.results[id]
        if r then
            lines[#lines + 1] = string.format("%s|%s|%s|%s|%s", r.id, tostring(r.result), tostring(r.details),
                tostring(r.build), tostring(r.time))
        else
            lines[#lines + 1] = id .. "|not run"
        end
    end
    lines[#lines + 1] = "events=" .. #db.events
    for _, e in ipairs(db.events) do
        lines[#lines + 1] = string.format("E|%s|%.1f|enc=%s|%s|args=%d|secret=%s", e.event, e.time, tostring(e.encounter),
            e.restriction, e.args, e.secretArgs)
    end
    return table.concat(lines, "\n")
end

function P.ShowExport()
    if not P.exportFrame then
        local f = CreateFrame("Frame", "FDCPProbeExport", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(640, 420)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f.TitleText:SetText("FDCP Probe export (Ctrl+C)")
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -32)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(580)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(edit)
        f.edit = edit
        P.exportFrame = f
    end
    local f = P.exportFrame
    f.edit:SetText(P.BuildExport())
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end
