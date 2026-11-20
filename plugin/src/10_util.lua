-- Shared helpers. Everything here is a local in the single main.lua chunk.

-- Format a whole number with thousands separators (no string.gsub in the sandbox).
local function format_number(n)
    if type(n) ~= "number" then return tostring(n) end
    local negative = n < 0
    local s = tostring(math.floor(math.abs(n) + 0.5))
    local out, count = {}, 0
    for i = #s, 1, -1 do
        out[#out + 1] = string.sub(s, i, i)
        count = count + 1
        if count % 3 == 0 and i > 1 then out[#out + 1] = "," end
    end
    local reversed = {}
    for i = #out, 1, -1 do reversed[#reversed + 1] = out[i] end
    return (negative and "-" or "") .. table.concat(reversed)
end
