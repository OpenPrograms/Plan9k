local ipacc = kernel.modules.ip.accept

kernel.modules.sysfs.data.net.linked = {
    __type = "f",
    write = function(h, data)
        local modem = data:match("([^%s]+)")
        modem = component.get(modem)
        if not modem or component.type(modem) ~= "tunnel" then
            kernel.io.println("/sys/net/linked: No linked card with such address")
            return nil, "No modem with such address"
        end
        
        local muuid = kernel.modules.util.uuidBin(modem)
        local name = "link" .. kernel.modules.util.toHex(kernel.modules.ip.ipChecksum(string.pack(">c16", muuid))):upper()
        local iface = kernel.modules.interface.register(name, component.invoke(modem, "maxPacketSize") - 12 , true)
        iface.modem = modem
        
        iface.writeIP = function(data, dest, ipv, mcast)
            return component.invoke(modem, "send", data) and #data
        end
        
        iface.customModem = function(localAddr, remoteAddr, vlan, d1, d2)
            iface.buf = iface.buf .. d1
            ipacc(iface)
            return false
        end
        
        kernel.modules.ocnet.customModem(modem, iface)
        kernel.modules.ip.initInterface(iface)
        
        iface.stop = function()
            kernel.modules.ocnet.customModem(modem, nil)
        end
        
        return name
    end
}
