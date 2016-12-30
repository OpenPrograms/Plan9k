local base = {}

function create(size)
    return setmetatable({data = ("\0"):rep(size), size = size, wb = 0, rb = 0, free = size}, {__index = base})
end

function base:write(data)
    local len = #data
    if len > self.free then
        return false
    end
    local dataleft = math.min(len, self.size - self.wb)
    local dataright = math.max(0, len - dataleft)
    self.data = data:sub(dataleft + 1, dataleft + dataright)
        .. self.data:sub(dataright + 1, self.wb)
        .. data:sub(1, dataleft)
        .. self.data:sub(self.wb + dataleft + 1)
    
    self.wb = self.wb + len
    if self.wb >= self.size then
        self.wb = dataright
    end
    
    self.free = self.free - len
    return true
end

function base:read(n)
    if n <= 0 then
        return ""
    end
    local toread = math.min(n, self.size - self.free)
    local left = math.min(toread, self.size - self.rb)
    local right = toread - left
    
    local res = self.data:sub(self.rb + 1, self.rb + left) .. self.data:sub(1, right)
    
    self.rb = self.rb + toread
    self.free = self.free + toread
    if self.rb >= self.size then
        self.rb = right
    end
    return res
end
