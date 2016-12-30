local sysfs = kernel.modules.sysfs

sysfs.data.net.ohcp = {
    pool = {
        __type = "f",
        write = function(h, data)
            local ifname, base, sub, count, gw = data:match("([^%s]+)%s+([%d%.]+)/(%d+)%s+(%d+)%s*([%d%.]*)")
            if not base then
                kernel.io.println("pool_add_v4: invalid pattern")
                return nil
            end
            local iface = kernel.modules.interface.interfaces[ifname]
            if not iface then
                kernel.io.println("pool_add_v4: no such interface")
                return nil
            end
            local baseStr = kernel.modules.ip.ip4parse(base)
            if not baseStr then
                kernel.io.println("pool_add_v4: invalid address")
                return nil
            end
            
            if gw and not kernel.modules.ip.ip4parse(gw) then
                kernel.io.println("pool_add_v4: invalid gateway address")
                return nil
            end
            
            
            
            if not iface.ohcp then iface.ohcp = {} end
            if not iface.ohcp.pool then iface.ohcp.pool = {} end
            
            iface.ohcp.pool[#iface.ohcp.pool + 1] = {
                base = string.unpack(">I4", baseStr),
                next = 0,
                max = tonumber(count),
                lease = {},
                sub = tonumber(sub),
                gate = gw and kernel.modules.ip.ip4parse(gw) or nil,
            }
        end
    }
}

function read(iface, remoteAddr, data)
    if data:byte(1) == 0 then
        if iface.ohcp and iface.ohcp.pool then
            for _, pool in ipairs(iface.ohcp.pool) do
                if pool.lease[remoteAddr] then
                    iface.write(string.pack(">BBI4B", 1, 0, pool.lease[remoteAddr], pool.sub), 0xCF, remoteAddr)
                    if pool.gate then
                        iface.write(string.pack(">BBc4I4", 1, 2, pool.gate, pool.lease[remoteAddr]), 0xCF, remoteAddr)
                    end
                    break
                elseif pool.next < pool.max then
                    pool.lease[remoteAddr] = pool.base + pool.next
                    pool.next = pool.next + 1
                    iface.write(string.pack(">BBI4B", 1, 0, pool.lease[remoteAddr], pool.sub), 0xCF, remoteAddr)
                    if pool.gate then
                        iface.write(string.pack(">BBc4I4", 1, 2, pool.gate, pool.lease[remoteAddr]), 0xCF, remoteAddr)
                    end
                    break
                end
            end
        end
    end
end
