local ipacc = kernel.modules.ip.accept

local connections = {}

local function internetFilter(localAddr, connectionId)
    if not connections[connectionId] then
        return true
    end
    local iface = connections[connectionId]
    local r = "\0"
    while r and #r > 0 do
        r = iface.conn.read()
        if r and #r > 0 then
            iface.buf = iface.buf .. r
            ipacc(iface)
        end
        if not r then
            kernel.io.println("net_in: Read error for " .. iface.name)
            kernel.modules.interface.unregister(iface.name)
        end
    end
    return false
end


kernel.modules.sysfs.data.net.gate = {
    __type = "f",
    write = function(h, data)
        local net = kernel._K.component.list("internet", true)()
        if not net then
            kernel.io.println("/sys/net/gate: No internet card")
            return nil, "No internet card"
        end
        
        local s, conn = pcall(kernel._K.component.invoke, net, "connect", data:match("[%.:0-9]+"))
        if not s then
            kernel.io.println("/sys/net/gate: connection error: " .. conn)
            return nil, "Couldn't connect"
        end
        
        if not conn then
            kernel.io.println("/sys/net/gate: Couldn't connect")
            return nil, "Couldn't connect"
        end
        
        local r, err = pcall(conn.finishConnect)
        if not r then
             kernel.io.println("gate conn err: ".. tostring(err))
             return nil, "Connection error (finishConnect)"
        end
        
        local rawip, rport = kernel.modules.ip.ip4parse(data)
        local name = "net" .. kernel.modules.util.toHex(kernel.modules.ip.ipChecksum(string.pack(">Hc4", rport, rawip))):upper()
        local iface = kernel.modules.interface.register(name, 2048, true)
        
        connections[conn.id()] = iface
        
        iface.conn = conn
        
        iface.writeIP = function(data, dest, ipv, multi)
            return conn.write(data)
        end
        
        iface.stop = function()
            conn.close()
        end
        
        kernel.modules.ip.initInterface(iface)
        
        return name
    end
}

function start()
    kernel.modules.threading.eventFilters.signal.internet_ready = internetFilter
end
