local interfaces = {}
_G.interfaces = interfaces

--ip is ip enabled - boolean
function register(name, mtu, ip)
    if interfaces[name] then
        error("Interface exists!")
    end
    interfaces[name] = {name = name, mtu = mtu, buf = "", ip = ip}
    return interfaces[name]
end

function unregister(name)
    kernel.io.println("unregister interface " .. name)
    if not interfaces[name] then
        error("Interface doesn't exist!")
    end
    if interfaces[name].stop then
        pcall(interfaces[name].stop)
    end
    kernel.modules.router.delInterface(interfaces[name])
    interfaces[name] = nil
end

local sysfs = kernel.modules.sysfs
sysfs.data.net["if"] = setmetatable({}, {
        __newindex = function()error("Access denied")end,
        __index = function(_,k)
            if interfaces[k] then
                local sysif = {
                    mtu = sysfs.roFile(interfaces[k].mtu),
                    v4 = {
                        addr = {
                            __type = "f",
                            write = function(h, data)
                                local net, sub = data:match("([%d%.]+)/(%d+)")
                                if not net then
                                    kernel.io.println("addr_add_v4: invalid pattern")
                                    return nil
                                end
                                sub = tonumber(sub)
                                local address = kernel.modules.ip.ip4parse(net)
                                interfaces[k].ip4.addr[#interfaces[k].ip4.addr + 1] = {address, sub}
                                
                                local full = math.floor(sub / 8)
                                local subaddr = address:sub(1, full)
                                if sub % 8 ~= 0 then
                                    subaddr = subaddr .. string.char(address:byte(full + 1) & (0xff << (8 - (sub % 8)))) .. ("\0"):rep(3 - full)
                                else
                                    subaddr = subaddr .. ("\0"):rep(4 - full)
                                end
                                
                                kernel.modules.router.ip4routeAdd(subaddr, sub, address, interfaces[k], 1, "kernel")
                                
                                if interfaces[k].ipAdvertise then
                                    interfaces[k].ipAdvertise(address)
                                end
                            end,
                            read = function(h, n)
                                if h.read then return nil end
                                h.read = true
                                local d = ""
                                for n, addr in pairs(interfaces[k].ip4.addr) do
                                    d = d .. kernel.modules.ip.ip4string(addr[1]) .. "/" .. tostring(addr[2]) .. "\n"
                                end
                                return d
                            end
                        }
                    }
                }
                if interfaces[k].ip then
                    sysif.proto = sysfs.roFile("IP4 IP6")
                end
                return sysif
            end
        end,
        __pairs = function()
            return next, kernel.modules.util.cloneTab(interfaces), nil
        end
    })

kernel.modules.gc.onShutdown(function()
    for i in pairs(interfaces) do
        unregister(i)
    end
end)
