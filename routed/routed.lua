local network = require "network"
local shell = require "shell"
local event = require "event"
local fs = require "filesystem"
local computer = require "computer"

local args, options = shell.parse(...)

local h = network.open(520)
local CMD_RESPONSE = 2
local mcast_rip = network.resolve("224.0.0.9")

local function ip4string(addr)
    return "" .. addr:byte(1) .. "." .. addr:byte(2) .. "." .. addr:byte(3) .. "." .. addr:byte(4) 
end

function ip4parse(addr)
    local b1, b2, b3, b4, port = addr:match("(%d+).(%d+).(%d+).(%d+):?(%d*)")
    if not b1 then
        return
    end
    return b1 and string.char(tonumber(b1)) .. string.char(tonumber(b2)) .. string.char(tonumber(b3)) .. string.char(tonumber(b4)), port and tonumber(port)
end

local nextUpdate = computer.uptime() + 30

while true do
    local e = {event.pull(nextUpdate - computer.uptime())}
    if e[1] then
        if e[1] == "udp_message" then
            local _, sip, sport, dport, frame = table.unpack(e)
            local cmd, ripv, n = string.unpack(">BBxx", frame)
            if cmd == CMD_RESPONSE then
                if ripv == 2 then
                    frame = frame:sub(5)
                    local r = fs.open("/sys/net/v4/route", "r")
                    local rroutes = r:read(math.huge)
                    r:close()
                    
                    local routes = {}
                    
                    for line in rroutes:gmatch("([^\n]+)") do
                        local n = line:gmatch("([^%s]+)")
                        local a1, a2, a3, a4, mask = n():match("(%d+)%.(%d+)%.(%d+)%.(%d+)/(%d+)")
                        local addr = string.pack("BBBB", tonumber(a1), tonumber(a2), tonumber(a3), tonumber(a4))
                        local info = {}
                        for key in n do
                            info[key] = n()
                        end
                        
                        routes[#routes + 1] = {addr = addr, subnet = tonumber(mask), info = info}
                    end
                    
                    while #frame >= 20 do
                        local addrFamily, routeTag, network, netmask, nextHop, metric = string.unpack(">HHc4I4c4I4", frame)
                        local subnet = (32 - math.log((~netmask & 0xffffffff) + 1,  2)) | 0
                        
                        local valid = true
                            
                        for _, route in pairs(routes) do
                            if route.addr == network and route.subnet == subnet then
                                if not route.info["via"] or metric + 1 >= (tonumber(route.info["metric"]) or math.huge) then
                                    valid = false
                                    break
                                end
                            end
                        end
                        
                        if metric < 16 and valid then
                            metric = metric + 1
                            
                            --print(ip4string(network) .. "/" .. subnet .. " via " .. ip4string(sip:sub(2)) .. " proto rip metric " .. metric)
                            local h = fs.open("/sys/net/v4/route_add", "w")
                            h:write(ip4string(network) .. "/" .. subnet .. " via " .. ip4string(sip:sub(2)) .. " proto rip metric " .. metric)
                            h:close()
                        end
                        frame = frame:sub(21)
                    end
                end
            end
        elseif e[1] == "interrupted" then
            --h:close()
            --os.exit()
        end
    else
        nextUpdate = computer.uptime() + 30
        local r = fs.open("/sys/net/v4/route", "r")
        local routes = r:read(math.huge)
        r:close()
        
        local entries = {}
        for line in routes:gmatch("([^\n]+)") do
            local n = line:gmatch("([^%s]+)")
            local a1, a2, a3, a4, mask = n():match("(%d+)%.(%d+)%.(%d+)%.(%d+)/(%d+)")
            local addr = string.pack("BBBB", tonumber(a1), tonumber(a2), tonumber(a3), tonumber(a4))
            local info = {}
            for key in n do
                info[key] = n()
            end
            entries[#entries + 1] = string.pack(">HHc4I4c4I4", 2, 0, addr, (0xffffffff << (32 - mask)) & 0xffffffff, "\0\0\0\0", info["metric"])
        end
        
        for i = 1, #entries, 20 do
            local packet = "\2\2\0\0"
            for ent = i, i + 19 do
                if entries[ent] then
                    packet = packet .. entries[ent]
                end
            end
            h:write(mcast_rip, 520, packet)
        end
    end
end
