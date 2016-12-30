local fs = require "filesystem"
local args = {...}
 
local dev = args[1] or error("Must specify a file")
 
local device = fs.open(dev, "wb")
 
local sectors = math.floor(device:seek("end", 0)/512)
print(sectors .. " sectors")
device:seek("set", 0)

local magic = string.char(0xD4, 0x99, 0xC6, 0xE2)
local lbs = 9 -- 2 ^ 9 = 512
local volId = 0
local volCount = 1

local blocks = sectors
local dataTop = 1
local firstFree = 1

local usedBlocks = 4
local inodeAllocations = 1
local firstFreeInode = 1
local VGID = math.random(1000000000000000)

local superBlock = string.pack("\60c4BBxBxI8I8I8I8I8I8c16", magic, lbs, volId, volCount, blocks, dataTop, firstFree, usedBlocks, inodeAllocations, firstFreeInode, VGID) .. ("\0"):rep(188)
local rootNodeBolck = string.pack("\60BHHHxI8I4I8I8I8I8xxxxxx", 1, 0xFF80, 0, 0, 0, 0, 0, 0, 0, 0)
local rootDps = string.pack("\60I8BBI8I4xx", 0, 0, 0, 0, 0)

print("Boot record size: " .. #superBlock)
device:write((superBlock .. ("\0"):rep(512)):sub(1, 512))

print("Inode 0 start: " .. tostring(device:seek("set", (blocks - 1) * 512)))
device:write((rootNodeBolck .. ("\0"):rep(512)):sub(1, 512))
