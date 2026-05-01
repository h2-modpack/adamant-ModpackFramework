--- Create the HUD subsystem for one coordinator pack.
--- @param packId string Pack identifier used for component naming.
--- @param packIndex number Stable vertical stacking index for this pack.
--- @param hash table Hash subsystem returned by `Framework.createHash(...)`.
--- @param theme table Theme object returned by `Framework.createTheme(...)`.
--- @param config table Coordinator config table containing `ModEnabled`.
--- @param hideHashMarker boolean|nil Optional pack-level flag to suppress the HUD fingerprint marker.
--- @return table hud HUD object exposing marker/hash update helpers.
function Framework.createHud(packId, packIndex, hash, theme, config, hideHashMarker)
    assert(ScreenData and ScreenData.HUD and ScreenData.HUD.ComponentData,
        "Framework.createHud: game HUD globals are not ready; call Framework.init after game load")
    local modutil = rom.mods["SGG_Modding-ModUtil"]
    assert(modutil and modutil.mod and modutil.mod.Path and type(modutil.mod.Path.Wrap) == "function",
        "Framework.createHud: SGG_Modding-ModUtil is not available")

    local HUD_LINE_HEIGHT = 24
    local componentName = "ModpackMark_" .. packId

    local _, initFingerprint = hash.GetConfigHash()
    local currentHash = config.ModEnabled and initFingerprint or ""
    local displayedHash = nil
    local hashDirty = false
    local markerHidden = hideHashMarker == true
    local markerVisible = true

    if not markerHidden then
        ScreenData.HUD.ComponentData[componentName] = {
            RightOffset = 20,
            Y = 250 + (packIndex - 1) * HUD_LINE_HEIGHT,
            TextArgs = {
                Text = "",
                Font = "MonospaceTypewriterBold",
                FontSize = 18,
                Color = theme.colors.text,
                ShadowRed = 0.1,
                ShadowBlue = 0.1,
                ShadowGreen = 0.1,
                OutlineColor = { 0.113, 0.113, 0.113, 1 },
                OutlineThickness = 2,
                ShadowAlpha = 1.0,
                ShadowBlur = 1,
                ShadowOffset = { 0, 4 },
                Justification = "Right",
                VerticalJustification = "Top",
                DataProperties = { OpacityWithOwner = true },
            },
        }
    end

    local function UpdateModMark()
        if markerHidden then return end
        if not HUDScreen or not HUDScreen.Components[componentName] then return end
        local nextDisplay = markerVisible and currentHash or ""
        if nextDisplay == displayedHash then return end

        if nextDisplay == "" then
            ModifyTextBox({ Id = HUDScreen.Components[componentName].Id, ClearText = true })
        else
            ModifyTextBox({ Id = HUDScreen.Components[componentName].Id, Text = nextDisplay })
        end
        displayedHash = nextDisplay
    end

    modutil.mod.Path.Wrap("ShowHealthUI", function(base, args)
        base(args)
        if not markerHidden and config.ModEnabled then
            displayedHash = nil
            UpdateModMark()
        end
    end)

    local function updateHash()
        local _, fingerprint = hash.GetConfigHash()
        currentHash = fingerprint
        hashDirty = false
        UpdateModMark()
    end

    local function markHashDirty()
        hashDirty = true
    end

    local function flushPendingHash()
        if hashDirty and config.ModEnabled then
            updateHash()
        end
    end

    local function setMarkerVisible(visible)
        markerVisible = visible == true
        UpdateModMark()
    end

    local function setModMarker(enabled)
        if enabled then
            local _, fingerprint = hash.GetConfigHash()
            currentHash = fingerprint
            hashDirty = false
        else
            currentHash = ""
            hashDirty = false
        end
        displayedHash = nil
        UpdateModMark()
    end

    return {
        setModMarker    = setModMarker,
        setMarkerVisible = setMarkerVisible,
        markHashDirty   = markHashDirty,
        flushPendingHash = flushPendingHash,
        updateHash      = updateHash,
        getConfigHash   = hash.GetConfigHash,
        applyConfigHash = hash.ApplyConfigHash,
    }
end
