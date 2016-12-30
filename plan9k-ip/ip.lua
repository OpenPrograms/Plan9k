local fs = require "filesystem"

local args = {...}

local interfaces = {}
for i in fs.list("/sys/net/if") do
    interfaces[#interfaces + 1] = i:sub(1, #i-1)
end

local command = {}

command.r = function() --route
    if not args[2] then
        for l in io.lines("/sys/net/v4/route") do
            print(l)
        end
        return
    end
    if args[2] == "add" then
        local h = fs.open("/sys/net/v4/route_add", "w")
        local res, e = h:write(table.concat(args, " ", 3))
        h:close()
        if not res and e then
            print("Error: " .. tostring(e))
        end
    end
end

command.a = function() --address
    if args[2] == "add" then
        if args[4] ~= "dev" then
            print("Usage: ip addr add [a.d.d.r/net] dev [device]")
            return
        end
        
        local h = fs.open("/sys/net/if/" .. args[5] .. "/v4/addr", "w")
        local res, e = h:write(args[3])
        h:close()
        if not res and e then
            print("Error: " .. tostring(e))
        end
    elseif not args[2] then
        for n, i in pairs(interfaces) do
            print(i .. ": ")
            for a in io.lines("/sys/net/if/" .. i .. "/v4/addr") do
                print("    " .. a)
            end
        end
    end

end

command.g = function() --gate iface
    if args[2] == "add" then
        local h = fs.open("/sys/net/gate", "w")
        local res, e = h:write(args[3])
        h:close()
        if not res and e then
            print("Error: " .. tostring(e))
        end
        print(tostring(res))
        
        
    end
end

command.o = function() --oc
    if args[2] == "add" then
        local h = fs.open("/sys/net/oc", "w")
        local res, e = h:write(table.concat(args, " ", 3))
        h:close()
        if not res and e then
            print("Error: " .. tostring(e))
        end
        print(tostring(res))
        
        
    end
end

command.t = function() --linked tunnel
    if args[2] == "add" then
        local h = fs.open("/sys/net/linked", "w")
        local res, e = h:write(args[3])
        h:close()
        if not res and e then
            print("Error: " .. tostring(e))
        end
        print(tostring(res))
        
        
    end
end

if not args[1] or not command[args[1]:sub(1,1)] then
    print("Usage: ip [ COMMAND ] ")
    return
end

command[args[1]:sub(1,1)]()
