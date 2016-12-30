local network = require "network"
local shell = require "shell"
local event = require "event"

local args, options = shell.parse(...)

local h = network.open(999) --pass -1 for auto assign

if not h then
    print("Couldn't open port")
    return
end

local host = network.resolve(args[1])
local port = tonumber(args[2])

local eof = false
while true do
    while (io.input().remaining and io.input().remaining() ~= 0 or (not eof and not io.input().remaining)) do
        local toread = 1500
        if io.input().remaining then toread = io.input().remaining() end
        local data = io.read(math.min(toread or 1500, 1500))
        if not data then
            eof = true
        else
            h:write(host, port, data)
            io.stderr:write(data)
        end
    end
    local e = {event.pull()}
    if e[1] then
        if e[1] == "udp_message" then
            io.write(e[5])
        elseif e[1] == "interrupted" then
            h:close()
            os.exit()
        end
    end
end
