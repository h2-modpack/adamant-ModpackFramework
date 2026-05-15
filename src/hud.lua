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
    assert(lib and lib.overlays and type(lib.overlays.defineOwned) == "function",
        "Framework.createHud: adamant-ModpackLib overlays are not available")

    local componentName = "ModpackMark_" .. packId

    local _, initFingerprint = hash.GetConfigHash()
    local currentHash = config.ModEnabled and initFingerprint or ""
    local hashDirty = false
    local markerHidden = hideHashMarker == true
    local markerContext = nil

    if not markerHidden then
        lib.overlays.defineOwned("adamant-framework." .. packId .. ".hud", function(overlays)
            overlays.createLine("hash", {
                componentName = componentName,
                region = "middleRightStack",
                order = lib.overlays.order.framework + packIndex,
                visible = function()
                    return config.ModEnabled == true and currentHash ~= ""
                end,
                minWidth = 120,
                textArgs = {
                    Color = theme.colors.text,
                },
            })
            overlays.onCommit(function(ctx)
                markerContext = ctx
                ctx.setLine("hash", currentHash)
                ctx.refresh("hash")
            end)
        end)
    end

    local function UpdateModMark()
        if markerContext then
            markerContext.setLine("hash", currentHash)
            markerContext.refresh("hash")
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
        markHashDirty   = markHashDirty,
        flushPendingHash = flushPendingHash,
        updateHash      = updateHash,
        getConfigHash   = hash.GetConfigHash,
        applyConfigHash = hash.ApplyConfigHash,
    }
end
