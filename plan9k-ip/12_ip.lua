-----------------
-- PREDEF

local eachThread
local routeSend4f
local routeSend4
local matchBits

local ip4send

-----------------
-- IP UTILS

local function ipChecksum(of)
  if #of % 2 ~= 0 then
    of = of .. "\x00"
  end
  local sum = 0 | 0
  local up = string.unpack
  while #of ~= 0 do
    sum = sum + up(">I2", of)
    of = of:sub(3)
  end
  
  while (sum >> 16) ~= 0 do
    sum = (sum & 0xFFFF) + (sum >> 16)
  end
  
  return string.pack(">I2", (~sum & 0xFFFF))
end
_G.ipChecksum = ipChecksum

function ip4string(addr)
    return "" .. addr:byte(1) .. "." .. addr:byte(2) .. "." .. addr:byte(3) .. "." .. addr:byte(4) 
end

function ip4parse(addr)
    local b1, b2, b3, b4, port = addr:match("(%d+).(%d+).(%d+).(%d+):?(%d*)")
    if not b1 then
        return
    end
    return b1 and string.char(tonumber(b1)) .. string.char(tonumber(b2)) .. string.char(tonumber(b3)) .. string.char(tonumber(b4)), port and tonumber(port)
end

-----------------
-- IP4 PROTOCOLS

local function icmp4(sip, dip, frame, interface)
    local ftype = frame:byte(1)
    --print("ICMP TYPE=" .. ftype)
    if ftype == 8 then --Echo request
        local checksum, ident, seq, n = string.unpack(">xxHHH", frame)
        local response = string.pack(">xxxxHH", ident, seq) .. frame:sub(n)
        response = response:sub(1, 2) .. ipChecksum(response) .. response:sub(5)
        routeSend4(sip, 1, response)
    end
    if ftype == 0 then
        local code, checksum, ident, seq, n = string.unpack(">xBHHH", frame)
        eachThread(function(thread)
            if thread.currentHandler == "ping" then
                thread.eventQueue[#thread.eventQueue + 1] = {"ping", {
                    data = frame:sub(n),
                    ident = ident,
                    seq = seq
                    }}
            end
        end)
    end
end

local ip4proto = {
    [0x01] = icmp4
}
_G.ip4proto = ip4proto

-----------------
-- IP4

local V4_FRAME_HEADER = string.packsize(">xxHHHBBHc4c4")

local ip4ident = 0

--TODO: PREFIX FRAMES WITH SIZE FOR GO
ip4send = function(dip, sip, proto, data, interface, routedip, multicast)
    local MAX_FRAME_DATA = interface.mtu - V4_FRAME_HEADER
    MAX_FRAME_DATA = MAX_FRAME_DATA - (MAX_FRAME_DATA % 8)

    local frags = math.ceil(#data / MAX_FRAME_DATA)
    for i = 1, frags do
        local tosend = data:sub(((i-1) * MAX_FRAME_DATA) + 1, i * MAX_FRAME_DATA)
        
        local fragment = ((i-1) * MAX_FRAME_DATA) / 8
        if i ~= frags then
            fragment = fragment | 0x2000
        end
        
        local head = string.pack(">BBHHHBBxxc4c4", 69, 0, 20 + #tosend, ip4ident & 0xffff, fragment, 32, proto, sip, dip)
        local msg = head .. tosend
        
        --print("SEND IP "..proto .. " HL=" .. #head .. " DATA=" .. #data .. " TOSEND=" 
        --    .. #tosend .. "(" .. ((i-1) * MAX_FRAME_DATA) + 1 .. " - " .. i * MAX_FRAME_DATA .. ") FRAME=" .. #msg .. " MF=" .. pb(i ~= frags))
        msg = msg:sub(1, 10) .. ipChecksum(head) .. msg:sub(13)
        local n, err = interface.writeIP(msg, routedip or dip, 4, multicast)
        if n ~= #msg then
            return false, err
        end
    end
    
    ip4ident = ip4ident + 1
end
_G.ip4send = ip4send

function ip4forward(frame, interface, routedip, ttl)
    local MAX_FRAME_DATA = interface.mtu - V4_FRAME_HEADER
    MAX_FRAME_DATA = MAX_FRAME_DATA - (MAX_FRAME_DATA % 8)
    
    interface.writeIP(frame, routedip, 4, false)
end

--------
--------
--------

local buf = {}

local function process4(frame, interface)
    if #frame < V4_FRAME_HEADER then
        return frame, false
    end
    local ihl = ((frame:sub(1,1):byte() | 0x0f) >> 4) * 5
    local length, ident, fragment, ttl, proto, checksum, sip, dip = string.unpack(">xxHHHBBHc4c4", frame)
    
    local df = (fragment & 0x4000) ~= 0
    local mf = (fragment & 0x2000) ~= 0
    local offset = (fragment & 0x1fff) * 8
    local dlen = length - ihl
    

    local hasDest = false
    for k, a in pairs(interface.ip4.addr) do
        if a[1] == dip then
            hasDest = true
            break
        end
    end
    
    if not hasDest then
        hasDest = matchBits(dip, "\224\0\0\0", 4) or dip == "\255\255\255\255"
    end
    
    if not hasDest then
        if interface.ip4.forward then
            if ttl > 0 then
                local packet = string.pack(">c8BBxx", frame:sub(1,8), ttl - 1, proto) .. frame:sub(13)
                packet = packet:sub(1, 10) .. ipChecksum(packet:sub(1, ihl)) .. packet:sub(13)
                routeSend4f(dip, packet)
            end
        end
        return frame:sub(length + 1), true
    end

    if (df or (not mf and offset == 0)) and ip4proto[proto] then
        ip4proto[proto](sip, dip, frame:sub(ihl+1, length), interface)
    elseif ip4proto[proto] then
        if not buf[dip] then
            buf[dip] = {n=0}
        end
        local queue = buf[dip]
        
        if not queue[ident] then
            queue.n = queue.n + 1
            queue[ident] = {[0] = "", n = 1}
        end
        if queue[ident][offset] then --Can attach to previous part
            local temp = queue[ident][offset]
            queue[ident][offset] = nil
            queue[ident][offset + dlen] = temp .. frame:sub(ihl+1, length)
            
            if not mf and #queue[ident][offset + dlen] == offset + dlen then --Packet assembled
                --print("Assembled IP, DATA=" .. #queue[ident][offset + dlen])
                ip4proto[proto](sip, dip, queue[ident][offset + dlen], interface)
                queue[ident] = nil
                queue.n = queue.n - 1
                if queue.n == 0 then
                    buf[dip] = nil
                    queue = nil
                end
            elseif not mf then
                queue[ident].done = true
            end
        else
            queue[ident].n = queue[ident].n + 1
            queue[ident][offset + dlen] = frame:sub(ihl+1, length)
            --TODO: PACKET REASSEMBLY, TESTS
        end
    end
    return frame:sub(length + 1), true
end

kernel.modules.sysfs.data.net.v4 = {
    
}

-----------------
-- IP6

local function process6(frame, interface)
    return "", true
end

-----------------
-- INTERFACE-STRUCT

function initInterface(iface)
    iface.ip4 = {
        addr = {},
        forward = true
    }
end

-----------------
-- INPUT

function accept(interface)
    local continue = true
    while #interface.buf > 0 and continue do
        local ipZero = interface.buf:byte(1)
        local ipVersion = (ipZero & 0xf0) >> 4
        --print("IP version: " .. ipVersion)
        if ipVersion == 4 then
            --TODO: Loop to get all packets out of buf
            interface.buf, continue = process4(interface.buf, interface)
        elseif ipVersion == 6 then
            interface.buf, continue = process6(interface.buf, interface)
        end
    end
end

function start()
    eachThread = kernel.modules.threading.eachThread
    routeSend4f = kernel.modules.router.ip4forward
    routeSend4 = kernel.modules.router.ip4sendto
    matchBits = kernel.modules.router.matchBits
end



