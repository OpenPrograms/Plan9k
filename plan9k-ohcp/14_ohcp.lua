local server = kernel.modules.ohcpSrv

kernel.modules.ocnet.proto[0xCF] = function(iface, remoteAddr, data)
    if data:byte(1) == 0 and server then
        server.read(iface, remoteAddr, data)
    elseif data:byte(1) == 1 then
        if data:byte(2) == 0 then
            local address, sub = string.unpack("c4B", data:sub(3))
            
            iface.ip4.addr[#iface.ip4.addr + 1] = {address, sub}
            
            local full = math.floor(sub / 8)
            local subaddr = address:sub(1, full)
            if sub % 8 ~= 0 then
                subaddr = subaddr .. string.char(address:byte(full + 1) & (0xff << (8 - (sub % 8)))) .. ("\0"):rep(3 - full)
            else
                subaddr = subaddr .. ("\0"):rep(4 - full)
            end
            
            kernel.modules.router.ip4routeAdd(subaddr, sub, address, iface)
            
            if iface.ipAdvertise then
                iface.ipAdvertise(address)
            end
          
        elseif data:byte(2) == 2 then
            local address, src = string.unpack("c4c4", data:sub(3))
            kernel.modules.router.ip4routeAdd("\0\0\0\0", 0, src, address)
        end
    end
end

local sysfs = kernel.modules.sysfs
if not sysfs.data.net.ohcp then
    sysfs.data.net.ohcp = {}
end

sysfs.data.net.ohcp.run = {
    __type = "f",
    write = function(h, data)
        local iface = data:match("([^%s]+)")
        if not iface or not kernel.modules.interface.interfaces[iface] then
            kernel.io.println("ohcp_client: No such device")
            return
        end
        iface = kernel.modules.interface.interfaces[iface]
        iface.broadcast("\0", 0xCF)
    end
}
