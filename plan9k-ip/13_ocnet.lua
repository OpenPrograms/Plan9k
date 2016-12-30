local ipacc = kernel.modules.ip.accept

local interfaces = {}
proto = {}

function customModem(addr, iface)
    interfaces[addr] = iface
end

local function modemFilter(localAddr, remoteAddr, vlan, _, iproto, data)
    if not interfaces[localAddr] or not interfaces[localAddr][vlan] then
        if interfaces[localAddr] and interfaces[localAddr].customModem then
            return interfaces[localAddr].customModem(localAddr, remoteAddr, vlan, iproto, data)
        end
        kernel.io.println("MODEM FILT fail " .. tostring(localAddr))
        return true
    end
    local iface = interfaces[localAddr][vlan]
    
    if iproto == 0x46 then
        iface.buf = iface.buf .. data
        ipacc(iface)
    elseif iproto == 0x0C then
        if data:byte(1) == 0x01 then
            if #data <= 17 then
                iface.peers[data:sub(2)] = remoteAddr
            end
        elseif data:byte(1) == 0x02 then
            for _, addr in pairs(iface.ip4.addr) do
                component.invoke(iface.modem, "send", remoteAddr, vlan, 0x0C, "\x01" .. addr[1])
            end
        end
    elseif proto[iproto] then
        proto[iproto](iface, remoteAddr, data)
    end
    return false
end

kernel.modules.sysfs.data.net.oc = {
    __type = "f",
    write = function(h, data)
        local modem, vlan = data:match("([^%s]+)%s*(%d*)")
        modem = component.get(modem)
        if not modem or component.type(modem) ~= "modem" then
            kernel.io.println("/sys/net/oc: No modem with such address")
            return nil, "No modem with such address"
        end
        
        vlan = vlan and tonumber(vlan) or 1
        
        if not component.invoke(modem, "open", vlan) then
            kernel.io.println("/sys/net/oc: Modem had already port open")
            return nil, "Modem had already port open"
        end
        
        local muuid = kernel.modules.util.uuidBin(modem)
        local name = "oc" .. kernel.modules.util.toHex(kernel.modules.ip.ipChecksum(string.pack(">Hc16", vlan, muuid))):upper()
        local iface = kernel.modules.interface.register(name, component.invoke(modem, "maxPacketSize") - 12 , true)
        iface.modem = modem
        
        if not interfaces[modem] then
            interfaces[modem] = {}
        end
        interfaces[modem][vlan] = iface
        
        iface.peers = {}
        iface.vlan = vlan
        
        iface.writeIP = function(data, dest, ipv, multi)
            if not multi and iface.peers[dest] then
                return component.invoke(modem, "send", iface.peers[dest], vlan, 0x46, data) and #data
            elseif multi then
                return component.invoke(modem, "broadcast", vlan, 0x46, data) and #data
            end
            kernel.io.debug("OCnet: Destination Host Unreachable")
            return false, "Destination Host Unreachable"
        end
        
        iface.write = function(data, proto, dest)
            return component.invoke(modem, "send", dest, vlan, proto, data) and #data
        end
        
        iface.broadcast = function(data, proto)
            return component.invoke(modem, "broadcast", vlan, proto, data) and #data
        end
        
        component.invoke(modem, "broadcast", vlan, 0x0C, "\x02")
        
        kernel.modules.ip.initInterface(iface)
        
        iface.stop = function()
            interfaces[modem][vlan] = nil
        end
        
        iface.ipAdvertise = function(addr)
            component.invoke(modem, "broadcast", vlan, 0x0C, "\x01" .. addr)
        end
        
        iface.timer = kernel.modules.timer.add(function()
            component.invoke(modem, "broadcast", vlan, 0x0C, "\x02")
        end, 300)
        
        return name
    end
}

function start()
    kernel.modules.threading.eventFilters.signal.modem_message = modemFilter
end
