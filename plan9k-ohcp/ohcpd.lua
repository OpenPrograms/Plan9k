local component = require "component"
local fs = require "filesystem"

local arg = {...}
local interfaces = {}

for i in fs.list("/sys/net/if") do
    if i:sub(1,2) == "oc" then
        interfaces[#interfaces + 1] = i
    end
end

if #arg > 0 then
    if not fs.exists("/sys/net/if/" .. arg[1]) then
        print("No such interface")
        return
    end
    print("Sending OHCP request")
    h = fs.open("/sys/net/ohcp/run")
    h:write(arg[1])
    h:close()
elseif #interfaces == 1 then
    print("Sending OHCP request for " .. interfaces[1])
    h = fs.open("/sys/net/ohcp/run")
    h:write(interfaces[1])
    h:close()
elseif #interfaces > 1 then
    print("More than 1 interface, specify interface name")
elseif #interfaces == 0 then
    local modems = {}
    for a in component.list("modem") do
        modems[#modems + 1] = a
    end
    if #modems ~= 1 then
        print("Can't implicitly create interface")
        print("Ethier no or more than 1 network cards installed")
        return
    end
    local h = fs.open("/sys/net/oc", "w")
    local res, e = h:write(modems[1])
    h:close()
    if not res and e then
        print("interface creation failed: " .. tostring(e))
    end
    print("Created interface " .. tostring(res))
    print("Sending OHCP request for " .. res)
    h = fs.open("/sys/net/ohcp/run")
    h:write(res)
    h:close()
else
    print("Usage: ohcpd [interface name]")
    print("You can skip interface name if there is only 1")
    print("network card installed or 1 oc interface is created")
end
