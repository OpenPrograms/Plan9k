local network = require "network"
local computer = require "computer"
local args = {...}

if not args[1] then
    print("Usage: ping [address]")
    return
end

local size = tonumber(args[2]) or 64

local host = network.resolve(args[1])

if not host then
    print("Couldn't resolve host " .. tostring(args[1]))
    return
end

print("PING " .. args[1] .. " " .. size .. "(" .. (size + 28) .. ") bytes of data")

local start = computer.uptime()

local status, err = network.ping(host, 5, size, 1, 32)

if not status then
    print(err)
    return
end

if status == "success" then
    print("64 bytes from " .. args[1] .. ": icmp_seq=1 ttl=32 time=" .. math.floor((computer.uptime() - start) * 1000) .. " ms")
elseif status == "timeout" then
    print("Request timed out.")
end
