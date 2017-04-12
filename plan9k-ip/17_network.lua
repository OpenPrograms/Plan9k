local api = {}
local ip = kernel.modules.ip
local tcpudp = kernel.modules.tcpudp
local threading

kernel.userspace.package.preload.network = api

function api.resolve(host)
    local addr = ip.ip4parse(host)
    if addr then
        return {4, addr}
    end
end

function api.hostname(addr)
    if type(addr) == "table" then
        if addr[1] == 4 then
            return ip.ip4string(addr[2])
        end
    elseif type(addr) == "string" then
        if addr:byte(1) == 4 then
            return ip.ip4string(addr:sub(2))
        end
    end
end

udpOpen = {}

local udpBase = {}
function udpBase:write(host, rPort, data)
    checkArg(1, host, "table", "string")
    checkArg(2, rPort, "number")
    checkArg(3, data, "string")
    if type(host) == "string" then
        if #host == 5 and host:byte(1) == 4 then
            host = {4, host:sub(2)}
        else
            error("UDP4 send to invalid host")
        end
    end
    if self.port then
        if host[1] == 4 then
            return tcpudp.sendUDP4(host[2], self.port, rPort, data)
        end
    end
end

function udpBase:close()
    udpOpen[self.port] = nil
    self.port = nil
end

local udpNext = 0

local function openFor(port, pid)
    checkArg(1, port, "number", "nil")
    
    if not port then
        while udpOpen[(udpNext % (2^14)) + ((2^14) * 3)] do udpNext = udpNext + 1 end
        port = (udpNext % (2^14)) + ((2^14) * 3)
    end
    
    if port >= 2^16 or port < 0 then
        error("Invalid port " .. tostring(port))
    end
    
    if udpOpen[port] then
        error("Port already open")
    end
    
    udpOpen[port] = pid
    return setmetatable({port = port}, {__index = udpBase})
end

_G.openFor = openFor

function api.open(port)
    return openFor(port, threading.currentThread.pid)
end

kernel.modules.gc.onProcessKilled(function(thread)
    for k, v in pairs(udpOpen) do
        if v == thread.pid then
            udpOpen[k] = nil
        end
    end
end)

function api.ping(host, timeout, size, seq, ttl)
    checkArg(1, host, "table")
    checkArg(2, timeout, "number")
    checkArg(3, size, "number")
    checkArg(4, seq, "number")
    checkArg(5, ttl, "number")
    local randomString = (function()local s="" for i = 1, size do s = s .. string.char(math.random(0, 255))end return s end)()

    if host[1] == 4 then
        local s, err = tcpudp.ping4(host[2], threading.currentThread.pid, seq, randomString)
        if not s then
            return nil, err
        end
    end
    local deadline = computer.uptime() + (timeout or math.huge)
    
    while deadline > computer.uptime() do
        threading.currentThread.deadline = deadline
        local msg = coroutine.yield("ping")
        if msg and msg.ident == threading.currentThread.pid and msg.seq == seq and msg.data == randomString then
            return "success"
        end
    end
    return "timeout"
end

function start()
    threading = kernel.modules.threading
end
