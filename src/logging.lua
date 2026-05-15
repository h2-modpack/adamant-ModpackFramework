Framework.logging = Framework.logging or {}

local logging = Framework.logging

local function FormatMessage(prefix, fmt, ...)
    if select("#", ...) > 0 then
        return prefix .. string.format(fmt, ...)
    end
    return prefix .. tostring(fmt)
end

function logging.warn(packId, fmt, ...)
    print(FormatMessage("[" .. tostring(packId) .. "] ", fmt, ...))
end

function logging.warnIf(packId, enabled, fmt, ...)
    if enabled then
        logging.warn(packId, fmt, ...)
    end
end
