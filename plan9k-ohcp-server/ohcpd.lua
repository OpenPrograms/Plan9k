function start()
    local fs = require "filesystem"
    local text = require "text"
    
    print("\x1b[32m>>\x1b[39m Configure ohcp server")
    if not fs.exists("/etc/ohcp-pools") then
        print("\x1b[31m!!\x1b[39m /etc/ohcp-pools DOES NOT EXIST!")
        return
    end
    for line in io.lines("/etc/ohcp-pools") do
        local h = fs.open("/sys/net/ohcp/pool", "w")
        h:write(line)
        h:close()
    end
end
