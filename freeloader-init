local list={"init.lua","lib/tools/boot.lua","boot/kernel/pipes","system/kernel"}
local OS,scrollingPos,select,selecttext={},0,{1,1},{"[Boot]","[Reboot]","[Shutdown]"}
local gpu=component.proxy(component.list("gpu")())
local set,fill,foreground,background=gpu.set,gpu.fill,gpu.setForeground,gpu.setBackground
local function readfile(fs,file)
 local buffer=""
 local open=fs.open(file,"r")
 repeat local read=fs.read(open,math.huge)
  buffer=buffer..(read or "")
 until not read
 fs.close(open)
 return buffer,"="..file
end
local function printselect(...)
 foreground(0x000000)
 background(0xFFFFFF)
 set(...)
 foreground(0xFFFFFF)
 background(0x000000)
end
local function refresh()
 _G._OSVERSION="FreeLoader"
 gpu.setResolution(50,16)
 fill(1,1,50,16," ")
 set(1,1,_OSVERSION)
 for i=2,15,13 do
  set(1,i,string.rep("-",50))
 end
 set(15,3,"Select what to boot:")
 OS={}
 for i in component.list("filesystem") do
  computer.pushSignal("component_added",i,"filesystem")
 end
end
refresh()
while true do
 local isRefreshed=false
 local signal={computer.pullSignal(0.001)}
 if signal[1]=="component_added" and signal[3]=="filesystem" then
  local fs=component.proxy(signal[2])
  for i=1,#list do
   if fs.exists(list[i]) then
    table.insert(OS,{signal[2],(readfile(fs,list[i]):match("_OSVERSION%s*=%s*\"(.-)\"") or "Unknown"),list[i]})
   end
  end
  isRefreshed=true
 elseif signal[1]=="component_removed" and signal[3]=="filesystem" then
  local check=1
  repeat
   if OS[check][1]==signal[2] then
    table.remove(OS,check)
   else
    check=check+1
   end
  until check>#OS
  isRefreshed=true
 elseif signal[1]=="key_down" then
  isRefreshed=true
  if signal[4]==200 then
   select[1]=select[1]-1
  elseif signal[4]==208 then
   select[1]=select[1]+1
  elseif signal[4]==203 then
   select[2]=select[2]-1
  elseif signal[4]==205 then
   select[2]=select[2]+1
  elseif signal[4]==28 then
   if select[2]==1 then
    if #OS~=0 and select[2]==1 then
     fill(1,1,50,16," ")
     _G.computer.getBootAddress=function() return OS[select[1]][1] end
     local boot,reason=load(readfile(component.proxy(OS[select[1]][1]),OS[select[1]][3]))
     if boot then
      local result={pcall(boot)}
      if result[1] then
       table.unpack(result,2,result.n)
      else
       set(1,7,"Error: "..(result[2] or "Unknown"))
      end
     else
      set(1,7,"Error: "..(reason or "Unknown"))
     end
     set(15,9,"Press any key to continue.")
     repeat local signal={computer.pullSignal()}
     until signal[1]=="key_down"
     refresh()
    end
   elseif select[2]==2 then
    computer.shutdown(true)
   elseif select[2]==3 then
    computer.shutdown()
   end
  end
 end
 local size=11
 if size>#OS then
  size=#OS
 end
 if select[1]<1 then
  select[1]=1
 elseif select[1]>#OS and #OS~=0 then
  select[1]=#OS
 end
 if select[1]<scrollingPos+1 then
  scrollingPos=select[1]-1
 elseif select[1]>scrollingPos+size then
  scrollingPos=select[1]-size
 end
 if select[2]<1 then
  select[2]=3
 elseif select[2]>3 then
  select[2]=1
 end
 if isRefreshed==true then
  fill(1,4,50,11," ")
  if #OS==0 then
   set(15,5,"Error: Nothing to boot!")
  else
   for i=scrollingPos+1,scrollingPos+size do
    if OS[i] then
     text=(tostring(i-1)..". "..OS[i][2]..": "..OS[i][1]:sub(1,3).."/"..OS[i][3])
     if i==select[1] then
      printselect(1,3+i-scrollingPos,text)
     else
      set(1,3+i-scrollingPos,text)
     end
    end
   end
  end
 end
 local t=1
 for i=1,3 do
  if i==select[2] then
   printselect(t,16,selecttext[i])
  else
   set(t,16,selecttext[i])
  end
  t=t+2+#selecttext[i]
 end
end
