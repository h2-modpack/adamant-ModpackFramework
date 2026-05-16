local hashCodec = {}

local TOKEN_ESCAPE = {
    ["%"] = "%25",
    ["|"] = "%7C",
    ["="] = "%3D",
}
local TOKEN_UNESCAPE = {
    ["25"] = "%",
    ["7C"] = "|",
    ["3D"] = "=",
    ["7c"] = "|",
    ["3d"] = "=",
}

local function EscapeToken(value)
    return tostring(value):gsub("[%%|=]", TOKEN_ESCAPE)
end

local function UnescapeToken(value)
    return tostring(value):gsub("%%(%x%x)", function(hex)
        return TOKEN_UNESCAPE[hex] or ("%" .. hex)
    end)
end

function hashCodec.serialize(kv)
    local keys = {}
    for k in pairs(kv) do
        table.insert(keys, k)
    end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        table.insert(parts, EscapeToken(k) .. "=" .. EscapeToken(kv[k]))
    end
    return table.concat(parts, "|")
end

function hashCodec.deserialize(str)
    local kv = {}
    if not str or str == "" then return kv end
    for entry in string.gmatch(str .. "|", "([^|]*)|") do
        local k, v = string.match(entry, "^([^=]+)=(.*)$")
        if k and v then
            kv[UnescapeToken(k)] = UnescapeToken(v)
        end
    end
    return kv
end

return hashCodec
