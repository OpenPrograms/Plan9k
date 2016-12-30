local fs = kernel.modules.vfs

local iFREE = 0
local iDIR = 1
local iFILE = 2

local SUPERBLOCK = "\60c4BBxBxI8I8I8I8I8I8c16"
local INODE = "\60BHHHxI8I4I8I8I8I8xxxxxxxxxxxx"
local INODE_SIZE = 64
local DPB = "\60I8BBI8I4xx"

assert(INODE_SIZE == string.packsize(INODE))

local function closeall(tab)
    for _, f in pairs(tab) do
        pcall(f.close, f)
    end
end

mrfs = {}

local lbasize = 512

local function readBlock(device, lba) --First LBA is 0
    device:seek("set", lba * lbasize)
    return device:read(lbasize)
end

local function writeBlock(device, lba, data) --First LBA is 0
    device:seek("set", lba * lbasize)
    --To future me: If you ever implement padding here, fix updateSuperblock
    return device:write(data:sub(1, 512))
end

local function writeSuperBlock(block)
    return string.unpack(SUPERBLOCK, 
        block.magic,
        block.lbaSize,
        block.volumeID,
        block.volumes,
        
        block.blocks,
        block.dataTop,
        block.firstFreeLBA,
        
        block.usedBlocks,
        block.inodeAllocations,
        block.firstFreeInode,
        block.volumeGroupID)
end

local function readSuperBlock(block)
    local magic, lbsz, volID, volumes, blocks, dataTop, firstFree, usedBlocks, inodeAllocations, firstFreeInode, vgid = string.unpack(SUPERBLOCK, block)
    return {
        magic = magic,
        lbaSize = lbsz,
        volumeID = volID,
        volumes = volumes,
        
        blocks = blocks,
        dataTop = dataTop,
        firstFreeLBA = firstFree,
        
        usedBlocks = usedBlocks,
        inodeAllocations = inodeAllocations,
        firstFreeInode = firstFreeInode,
        volumeGroupID = vgid
    }
end

local function readInode(data, at) --OK
    local iType, flags, UID, GID, size, allocatedBlocks, p0, p1, singlePtr, triplePtr = string.unpack(INODE, data, at + 1)
    return {
        type = iType,
        flags = flags,
        UserID = UID,
        GroupID = GID,
        
        size = size,
        allocatedBlocks = allocatedBlocks,
        
        p0 = p0,
        p1 = p1,
        singlePtr = singlePtr,
        triplePtr = triplePtr
    }
end

function mrfs:getBlock(volume, lba)
    return readBlock(self.volumes[volume].file, lba)
end

function mrfs:setBlock(volume, lba, data)
    return writeBlock(self.volumes[volume].file, lba, data)
end

function mrfs:zeroBlock(volume, lba)
    self:setBlock(volume, lba, ("\0"):rep(lbasize))
end

function mrfs:readInode(inode)
    local vol = inode & 0xff
    local node = inode >> 8
    local block = self.volumes[vol].superblock.blocks - 1 - math.floor(node / (lbasize / INODE_SIZE))
    local rawblock = self:getBlock(vol, block)
    kernel.io.println("IREAD: " .. (node % (lbasize / INODE_SIZE)) * INODE_SIZE)
    kernel.io.println("IREAD2: " .. #rawblock)
    kernel.io.println("IREAD3: " .. (self.volumes[vol].superblock.blocks - 1 - math.floor(node / (lbasize / INODE_SIZE))))
    return readInode(rawblock, (node % (lbasize / INODE_SIZE)) * INODE_SIZE)
end

function mrfs:readPointer(pointer)
    return self:getBlock(pointer[2], pointer[1])
end

--TODO: openInode


function mrfs:readDirectory(inode)
    if inode.type ~= iDIR then
        return nil, "Not a directory"
    end
    
    local dirents = {}
    local data = self:readAllData(inode)
    
    local at = 1
    
    while at < #data do
        local rnode, name, n = string.unpack("c16s1", data, at)
        at = n
        dirents[name] = readInode(rnode)
    end
    
    return dirents
end

--Path is segment array
--returns inode, success depth
function mrfs:resolveInode(path, dirInode, n)
    if not dirInode then
        dirInode = internal:readInode(0)
        n = 0
    end
    
    if #path == 0 then
        return dirInode, n
    end
    
    local dir, err = self:readDirectory(dirInode)
    if not dir then
        return nil, err
    end
    
    local sub = table.remove(path, 1)
    
    local subNode = dir[sub]
    if not subnode then
        return dirInode, n
    end
    
    return self:resolveInode(path, subNode, n + 1)
end

function mrfs:updateSuperblock(v)
    local volume = self.volumes[v]
    local block = writeSuperBlock(volume.superblock)
    self:setBlock(v, 0, block)
end

function mrfs:allocateBlock()
    for d, vol in pairs(self.volumes) do
        if vol.superblock.blocks < vol.superblock.usedBlocks then
            local free = vol.superblock.firstFreeLBA
            if free >= vol.superblock.dataTop then
                vol.superblock.dataTop = free + 1
                vol.superblock.firstFreeLBA = vol.superblock.dataTop
            else
                local b = self:getBlock(d, free)
                local t, nextLba = string.unpack("\60BI4", b)
                if t ~= 1 then
                    return nil, "Cannot allocate space: Corrupted free space"
                end
                vol.superblock.firstFreeLBA = nextLba
            end
            vol.superblock.usedBlocks = vol.superblock.usedBlocks + 1
            self.updateSuperblock(d)
            return d, free
        end
    end
    
    return nil, "No space left on device"
end

function mrfs:appendData(node, data)
    local size = #data
    --Expand inode
    --Allocate space
    --Write data
end

function mrfs:createDirectory(parentNode, name)
    local volume, lba = self:allocateBlock()
    if not volume then
        return nil, lba
    end
    
    self:zeroBlock(volume, lba)
    local dirNode = string.pack("\60BHHI4HI4B", iDIR, 0xFF80, 0, 0, 0, lba, volume)
    return self:appendData(parentNode, string.pack("c16s1", dirNode, name))
end

function open(...)
    local volumeFiles = {...}
    local volumeHandles = {}
    
    for _, volume in ipairs(volumeFiles) do
        volumeHandles[#volumeHandles + 1] = fs.open(volume, "wb")
    end
    
    local internal = {}
    internal.volumes = {}
    
    local masterSuperblock = readSuperBlock(readBlock(volumeHandles[1], 0))
    
    for _, volume in ipairs(volumeHandles) do
        local superblock = readSuperBlock(readBlock(volume, 0))
        if superblock.magic ~= "\xD4\x99\xC6\xE2" then
            closeall(volumeHandles)
            error("Invalid magic sequence")
        end
        
        if superblock.lbaSize ~= 9 then
            closeall(volumeHandles)
            print("Unsupported LBA size")
        end
        
        if superblock.volumeGroupID ~= masterSuperblock.volumeGroupID then
            closeall(volumeHandles)
            error("Volume group ID aren't matching")
        end
        
        if internal.volumes[superblock.volumeID] then
            closeall(volumeHandles)
            error("Volume with this volID already opened")
        end
        
        internal.volumes[superblock.volumeID] = {
            file = volume,
            superblock = superblock
        }
    end
    
    for i = 1, masterSuperblock.volumes do
        if not internal.volumes[i - 1] then
            closeall(volumeHandles)
            error("Volume not present: " .. (i - 1))
        end
    end
    
    setmetatable(internal, {__index = mrfs})
    
    local rootNode = internal:readInode(0)
    
    if rootNode.type ~= iDIR then
        closeall(volumeHandles)
        error("Root node is not a directory")
    end
    
    proxy = {}

    function proxy.getLabel()
        return "MrFS"
    end
    
    function proxy.isReadOnly()
        return false
    end

    function proxy.open()
        
    end
    
    function proxy.makeDirectory(path)
        local node, n = internal:resolveInode(fs.segments(path), dirInode, n)
        --TODO: Only creates in top dir
        
        if not node then return nil, n end
        local segments = fs.segments(path)
        
        if #segments < 1 then return true end
        
        return internal:createDirectory(node, segments[#segments])
    end
    
    function proxy.isDirectory(path)
        path = fs.segments(path)
        local inode = internal:resolveInode(path)
    end
    
    return proxy
end

function start()
    kernel.modules.mount.filesystems.mrfs = open
end
