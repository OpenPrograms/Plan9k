local interfaces = kernel.modules.interface.interfaces
local ip = kernel.modules.ip
local ip4send = ip.ip4send

--route: key -> ip {{1 subnet, 2 via, 3 srcip, 4 interface, 5 metric, 6 proto}, {...}, ...}
--Route proto:
-- man ip > protocol RTPROTO

local SUBNET = 1
local VIA = 2
local SRC = 3
local IFACE = 4
local METRIC = 5
local PROTO = 6

routes4 = {}

local function matchBits(a, pattern, n)
    local full = math.floor(n / 8)
    local rest = n % 8
    
    if a:sub(1, full) ~= pattern:sub(1, full) then
        return false
    end
    
    if rest ~= 0 then
        return (a:byte(full + 1) & (0xff << (8 - rest))) == (pattern:byte(full + 1) & (0xff << (8 - rest)))
    end
    
    return true
end
_G.matchBits = matchBits

local function findBest4(to) --random factor for equal metric?
    local best = nil
    local bestnet = -1
    local bestmetric = math.huge
    for dest, routeGroup in pairs(routes4) do
        for n, route in ipairs(routeGroup) do
            if (route[SUBNET] > bestnet or route[METRIC] < bestmetric) and matchBits(to, dest, route[SUBNET]) then
                best = route
                bestnet = route[SUBNET]
                bestmetric = route[METRIC]
            end
        end
    end
    return best
end

function ip4src(dip)
    local r = findBest4(dip)
    if not r then return nil, "No route to host" end
    return r[SRC]
end

function ip4sendto(dip, proto, data)
    if matchBits(dip, "\224\0\0\0", 4) or dip == "\255\255\255\255" then
        for dest, routeGroup in pairs(routes4) do
            for n, route in ipairs(routeGroup) do
                if type(route[VIA]) == "table" then
                    ip4send(dip, route[SRC], proto, data, route[IFACE], nil, true)
                end
            end
        end
        return true, #data
    else
        local r = findBest4(dip)
        if not r then return nil, "No route to host" end
        local rdip = type(r[VIA]) == "string" and r[VIA] or nil
        local n, err = ip4send(dip, r[SRC], proto, data, r[IFACE], rdip, false)
        if err then
            return nil, err
        end
        return r[SRC], n
    end
end

function ip4forward(dip, frame) --Sip only for forwarded packets!
    local r = findBest4(dip)
    if not r then return false end
    local rdip = type(r[VIA]) == "string" and r[VIA] or nil
    local n = ip.ip4forward(frame, r[4], type(r[VIA]) == "string" and r[VIA] or dip)
end

--via can be ethier table for interface or string for ip
function ip4routeAdd(to, subnet, src, via, metric, proto)
    local iface = via
    if type(via) ~= "table" then
        local r = findBest4(via)
        if not r or type(r[VIA]) ~= "table" then return end
        iface = r[VIA]
        if not src then
            src = r[SRC]
        end
    end
    if not routes4[to] then routes4[to] = {} end
    routes4[to][#routes4[to] + 1] = {subnet, via, src, iface, metric, proto}
    return routes4[to]
end

function delInterface(iface)
    for k, routeGroup in pairs(routes4) do
        for n, route in ipairs(routeGroup) do
            if r[4] == iface then
                routes4[k] = nil
            end
        end
    end
end

------


kernel.modules.sysfs.data.net.v4 = {
    route = kernel.modules.sysfs.roFile(function()
        local s = ""
        for a, routeGroup in pairs(routes4) do
            for n, r in ipairs(routeGroup) do
                s = s .. ip.ip4string(a) .. "/" .. r[SUBNET]
                if type(r[VIA]) == "table" then
                    s = s .. " dev " .. tostring(r[IFACE].name) .. " proto " .. tostring(r[PROTO]) .. " metric " .. tostring(r[METRIC]) .. " src " .. tostring(ip.ip4string(r[SRC])) .. "\n"
                else
                    s = s .. " via " .. tostring(ip.ip4string(r[VIA])) .. " dev " .. tostring(r[IFACE].name) .. " proto " .. tostring(r[PROTO]) .. " metric " .. tostring(r[METRIC]) .. " src " .. tostring(ip.ip4string(r[SRC])) .. "\n"
                end
            end
        end
        return s
    end),
    route_add = {
        __type = "f",
        write = function(h, data)
            kernel.io.debug("route_add_v4: " .. tostring(data))
            local net, sub, dv, dst, rest = data:match("([%d%.]+)/(%d+)%s+([devia]+)%s([^%s]+)%s*(.*)%s*")
            
            if not net then
                kernel.io.println("route_add_v4: Invalid format")
                kernel.io.println("route_add_v4: \\-> " .. tostring(data))
                return nil, "Invalid format"
            end
            
            local via
            if dv == "dev" then
                via = interfaces[dst]
                if not via then
                    kernel.io.println("route_add_v4: invalid dst device")
                    kernel.io.println("route_add_v4: \\-> " .. tostring(data))
                    return
                end
            elseif dv == "via" then
                via = ip.ip4parse(dst)
                if not via then
                    kernel.io.println("route_add_v4: invalid dst ip format")
                    kernel.io.println("route_add_v4: \\-> " .. tostring(data))
                    return
                end
            else
                kernel.io.println("route_add_v4: need to specify either via or dev, got " .. dv)
                return
            end
            
            local metric = 1
            local proto = "static"
            local src = nil
            
            if rest then
                local n = rest:gmatch("([^%s]+)")
                local cur = n()
                while cur do
                    if cur == "metric" then
                        metric = tonumber(n() or "x")
                        if not metric then
                            kernel.io.println("route_add_v4: invalid metric")
                            return
                        end
                    elseif cur == "proto" then
                        proto = n()
                        if not metric then
                            kernel.io.println("route_add_v4: invalid proto")
                            return
                        end
                    elseif cur == "src" then
                        src = ip.ip4parse(n())
                        if not src then
                            kernel.io.println("route_add_v4: invalid src")
                            return
                        end
                    else
                        kernel.io.println("route_add_v4: unknown param")
                        return
                    end
                
                    cur = n()
                end
            end
            
            if not src and type(via) == "table" then
                kernel.io.println("route_add_v4: src not given nor detected")
                return
            end
            
            ip4routeAdd(ip.ip4parse(net), tonumber(sub), src, via, metric, proto)
        end
    }
}

