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
    assert(lib and lib.overlays and type(lib.overlays.registerHudText) == "function",
        "Framework.createHud: adamant-ModpackLib overlays are not available")

    local HUD_LINE_HEIGHT = 24
    local componentName = "ModpackMark_" .. packId

    local _, initFingerprint = hash.GetConfigHash()
    local currentHash = config.ModEnabled and initFingerprint or ""
    local hashDirty = false
    local markerHidden = hideHashMarker == true
    local markerVisible = true
    local marker = nil

    if not markerHidden then
        marker = lib.overlays.registerStackedText({
            id = "framework:" .. packId .. ":hash",
            componentName = componentName,
            region = "middleRightStack",
            order = lib.overlays.order.framework + packIndex,
            textArgs = {
                Color = theme.colors.text,
            },
            text = function()
                return currentHash
            end,
            visible = function()
                return markerVisible and config.ModEnabled == true and currentHash ~= ""
            end,
        })
    end

    local function UpdateModMark()
        if marker then
            marker.refresh()
        end
    end

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
