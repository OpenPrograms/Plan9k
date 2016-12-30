local term = require("term")

function usage()
    print(
[[Usage:
 man [page] ...
 
 try 'man man'

Manual page viewer.]])
end

local args = {...}
if not args[1] then usage() return end

local file = "/usr/share/man/" .. args[1] .. ".md"

file = io.open(file)

if not file then
    print("Page not found")
    return
end

term.clear()
local _, h = term.getResolution()
io.write("\x1b[1;1H")
print("...",h)
for i = 1, h - 2 do
    local line = file:read("*l")
    if not line then print("input end")return end
    print(line)
end

io.write("\x1b47m\x1b30m--Manual--\x1b39m\x1b49m")

while true do
    local c = io.read(1)
    if c == "\n" then
        local line = file:read("*l")
        if not line then return end
        print("\r\x1b[K" .. line)
        io.write("\x1b47m\x1b30m--Manual--\x1b39m\x1b49m")
    elseif c == "q" then
        return
    end
end
