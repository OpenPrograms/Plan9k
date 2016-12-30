local router = kernel.modules.router
local send4 = router.ip4sendto
local ip = kernel.modules.ip
local ipsum = ip.ipChecksum
local eachThread
local usernet
local tcpMaxWindow = 4096

function sendUDP4(dip, sport, dport, data)
    local frame = string.pack(">HHHxx" ,sport, dport, 8 + #data) .. data
    return send4(dip, 0x11, frame)
end

function ping4(dip, ident, seq, payload)
    local frame = string.pack(">BBxxHH" ,8, 0, ident, seq) .. payload
    frame = frame:sub(1, 2) .. ipsum(frame) .. frame:sub(5)
    return send4(dip, 1, frame)
end

ip.ip4proto[0x11] = function(sip, dip, frame, interface)
    local sprot, dport, length = string.unpack(">HHH", frame)
    
    local pid = usernet.udpOpen[dport]
    if pid then
        eachThread(function(thread)
            if pid == thread.pid then
                thread.eventQueue[#thread.eventQueue + 1] = {"signal", "udp_message", "\4" .. sip, sprot, dport, frame:sub(9, length)}
            end
        end)
    end
end

---------
-- TCP --

local function badFileDescriptor()
    return nil, "bad file descriptor"
end

local tcpstate = {
    CLOSED = 0,
    LISTEN = 1,
    SYNRCV = 2,
    SYNSENT = 3,
    ESTABLISHED = 4,
    CLOSEWAIT = 5,
    LASTACK = 6,
    FINWAIT1 = 7,
    FINWAIT2 = 8,
    CLOSING = 9,
    TIMEWAIT = 10,
    INVALID = 11
}

local FIN = 0x1
local SYN = 0x2
local RST = 0x4
local PSH = 0x8
local ACK = 0x10

connections = {}
local tcpn = 0
local nextUserPort = math.random(2^14 - 1)
local streamBase = {}

local function connID(to, lport, rport)
    return string.pack(">HHc4", lport, rport, to)
end

local function allocatePort(to, rport)
    if not connections[connID(to, nextUserPort + 49152, rport)] then
        return nextUserPort + 49152
    end
    nextUserPort = (nextUserPort + 1) & (2^14 - 1)
    return allocatePort()
end

local function craftTcp(sport, dport, seq, ackn, flags, window, data)
    return string.pack(">HHI4I4BBHxxxx", sport, dport, seq, ackn, 5 << 4, flags, window) .. data
end

local function tcp4frame(connection, seq, ackn, flags, window, data)
    local frame = craftTcp(connection.sport, connection.dport, seq, ackn, flags, window, data)
    
    local sum = ipsum(string.pack(">c4c4xBH", connection.src, connection.peer, 0x6, #frame) .. frame)
    
    frame = frame:sub(1, 16) .. sum .. frame:sub(19)
    
    return frame
end

ip.ip4proto[0x06] = function(sip, dip, frame, interface)
    local sport, dport, seq, ackn, off, flags, wsize, checksum, urgptr = string.unpack(">HHI4I4BBHHH", frame)
    local dataStart = ((off & 0xf0) >>  4) * 4 + 1
    if connections[connID(sip, dport, sport)] then
        local connection = connections[connID(sip, dport, sport)]
        
        if connection.state == tcpstate.SYNSENT then --After initial SYN
            if flags & ACK > 0 then
                if ackn ~= connection.seq then
                    return
                end
                connection.ack = ackn
            end
            if flags & RST > 0 then
                connection.state = tcpstate.CLOSED
                eachThread(function(thread)
                    if connection.pid == thread.pid then
                        thread.eventQueue[#thread.eventQueue + 1] = {"signal", "tcp_closed", connection.uid}
                    end
                end)
                connections[connID(sip, dport, sport)] = nil
                return
            end
            if flags & SYN > 0 then
                --connection.rseq = seq
                connection.rack = seq + 1
                send4(sip, 0x06, tcp4frame(connection, connection.seq, connection.rack, ACK, tcpMaxWindow, ""))
            end
            
            if connection.ack == connection.seq then
                connection.state = tcpstate.ESTABLISHED
                eachThread(function(thread)
                    if connection.pid == thread.pid then
                        thread.eventQueue[#thread.eventQueue + 1] = {"signal", "tcp_connected", connection.uid}
                    end
                end)
            end
        elseif connection.state == tcpstate.ESTABLISHED then --Connection in progress
            if flags & ACK > 0 then
                if ackn <= connection.seq and ackn > connection.ack then
                    connection.ack = ackn
                end
            end
            if flags & FIN > 0 then
                connection.state = tcpstate.LASTACK
                connection.rack = seq + 1
                send4(sip, 0x06, tcp4frame(connection, connection.seq, connection.rack, ACK | FIN, tcpMaxWindow, ""))
                connection.seq = connection.seq + 1
            end
            
            local data = frame:sub(dataStart)
            
            connection.inBuf:write(data)
            --connection.rseq = seq + #data - 1
            connection.rack = seq + #data
            if #data > 0 then
                send4(sip, 0x06, tcp4frame(connection, connection.seq, connection.rack, ACK, tcpMaxWindow, ""))
                
                eachThread(function(thread)
                    if connection.pid == thread.pid then
                        thread.eventQueue[#thread.eventQueue + 1] = {"signal", "tcp_ready", connection.uid} --todo: only when buf ready = 0
                    end
                end)
            end
        elseif connection.state == tcpstate.LASTACK then --Waiting for last ACK for FIN
            if flags & ACK > 0 then
                if ackn <= connection.seq and ackn >= connection.ack then
                    connection.state = tcpstate.CLOSED
                    eachThread(function(thread)
                        if connection.pid == thread.pid then
                            thread.eventQueue[#thread.eventQueue + 1] = {"signal", "tcp_closed", connection.uid}
                        end
                    end)
                    connections[connID(sip, dport, sport)] = nil
                end
            end
        elseif connection.state == tcpstate.FINWAIT1 then --Waiting for peer to notify about closure of his side
            if flags & ACK > 0 then
                if ackn <= connection.seq and ackn >= connection.ack then
                    
                end
            end
            if flags & FIN > 0 then
                connection.rack = connection.rack + 1
                connection.state = tcpstate.CLOSED
                connections[connID(sip, dport, sport)] = nil
                send4(sip, 0x06, tcp4frame(connection, connection.seq, connection.rack, ACK, tcpMaxWindow, ""))
            end
        end
        
        
    end
end

function connect4(dip, port)
    local connection = {
        peer = dip,
        src = router.ip4src(dip),
        dport = port,
        sport = allocatePort(dip, port),
        state = tcpstate.SYNSENT,
        
        seq = math.random(1, 2^32 - 1), --top byte sent to peer
        ack = 0, --top byte acknowledged by peer
        
        rack = -1, --top byte acked TO peer
        --rseq = -1, --top byte recieved FROM peer
        
        pid = kernel.modules.threading.currentThread,
        uid = tcpn,
        
        inBuf = kernel.modules.ringbuffer.create(tcpMaxWindow),
        outBuf = kernel.modules.ringbuffer.create(tcpMaxWindow),
    }
    
    tcpn = tcpn + 1
    
    if not connection.src then
        return nil, "No route to host"
    end
    connections[connID(dip, connection.sport, port)] = connection
    
    local s, err = send4(dip, 0x06, tcp4frame(connection, connection.seq, 0, SYN, tcpMaxWindow, ""))
    connection.seq = connection.seq + 1
    
    if not s then
        connections[connID(dip, connection.sport, port)] = nil
        return nil, err
    end
    
    return setmetatable(connection, {__index = streamBase})
end

function streamBase:write(data)
    if self.state ~= tcpstate.ESTABLISHED then
        return nil, "Connection is not ESTABLISHED"
    end
    local s, err = send4(self.peer, 0x06, tcp4frame(self, self.seq, self.rack, ACK, tcpMaxWindow, data))
    self.seq = self.seq + #data
end

function streamBase:read(n)
    if self.state ~= tcpstate.ESTABLISHED then
        return nil, "Connection is not ESTABLISHED"
    end
    return self.inBuf:read(n)
end

function streamBase:close()
    if self.state ~= tcpstate.ESTABLISHED then
        return nil, "Connection is not ESTABLISHED"
    end
    local s, err = send4(self.peer, 0x06, tcp4frame(self, self.seq, self.rack, ACK | FIN, tcpMaxWindow, ""))
    self.seq = self.seq + 1
    eachThread(function(thread)
        if self.pid == thread.pid then
            thread.eventQueue[#thread.eventQueue + 1] = {"signal", "tcp_closed", self.uid}
        end
    end)
    self.state = tcpstate.FINWAIT1
    return true
end

streamBase.seek = badFileDescriptor

---------

function start()
    eachThread = kernel.modules.threading.eachThread
    usernet = kernel.modules.network
end
