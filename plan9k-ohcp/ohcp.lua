local pipes = require "pipes"

function start()
    print("\x1b[32m>>\x1b[39m Run OHCP client")
    local pid = os.spawn("/bin/ohcpd.lua")
    pipes.joinThread(pid)
end
