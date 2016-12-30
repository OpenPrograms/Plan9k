function start()
    local ip = loadfile("/bin/ip.lua")
    local fs = require "filesystem"
    local text = require "text"
    
    print("\x1b[32m>>\x1b[39m Configure network")
    if not fs.exists("/etc/netctl") then
        print("\x1b[31m!!\x1b[39m /etc/netctl DOES NOT EXIST!")
        return
    end
    for line in io.lines("/etc/netctl") do
        if line:sub(1,1) ~= "#" and #line > 0 then
            ip(table.unpack(text.tokenize(line)))
        end
    end
end
