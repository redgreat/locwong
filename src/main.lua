-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = 'locwong'
VERSION = '1.0.0'

-- 设置日志级别
LOG_LEVEL = log.LOG_INFO
-- log.setLevel(LOG_LEVEL)

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"
_G.sysplus = require("sysplus")
--TCP连接
local libnet = require "libnet"

-- 引入本地库
-- gnss定位
local gnss = require("gnss")
-- 基站定位
local gnbs = require("gnbs")
-- lbs库
local lbs = require("lbs")
-- 陀螺仪
local da267 = requre("da267")
-- 低功耗
local net_wakeup = requre("net_wakeup")
-- gnss的备电 和 gsensor的供电
local vbackup = gpio.setup(24, 1)

-- 录音使用
-- 初始化两个led灯，一个蓝灯，一个红灯
local blueLedPin = 1
local redLedPin = 16
local blueLed = gpio.setup(blueLedPin, 0)   -- 蓝灯亮起代表正在录音
local redLed = gpio.setup(redLedPin, 0)     -- 红灯亮起代表正在播放

local es8311i2cId = 0       -- I2CID
local es8311PowerPin = 2    -- ES8311电源控制引脚
local paPin = 23            -- PA放大器控制引脚

-- 逻辑代码开始
--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

--[[
  da267陀螺仪数据读取示例
]]
--起一个task，读取da267的数据
sys.taskInit(function()
    da267.da267Data()
end)

--[[
    fs 文件操作示例
  ]]

local function fs_test()
    -- 根目录/是可写
    local f = io.open("/boot_time", "rb")
    local c = 0
    if f then
        local data = f:read("*a")
        log.info("fs", "data", data, data:toHex())
        c = tonumber(data)
        f:close()
    end
    log.info("fs", "boot count", c)
    c = c + 1
    f = io.open("/boot_time", "wb")
    --if f ~= nil then
    log.info("fs", "write c to file", c, tostring(c))
    f:write(tostring(c))
    f:close()
    --end

    log.info("io.writeFile", io.writeFile("/abc.txt", "ABCDEFG"))

    log.info("io.readFile", io.readFile("/abc.txt"))
    local f = io.open("/abc.txt", "rb")
    local c = 0
    if f then
        local data = f:read("*a")
        log.info("fs", "data2", data, data:toHex())
        f:close()
    end

    -- seek测试
    local f = io.open("/123.txt", "rb")
    if f then
        local data = f:read("*a")
        log.info("fs", "123.txt data", data, data:toHex())
        f:close()
    end

    local f = io.open("/123.txt", "wb")
    if f then
        f:write("ABCDEFG")
        f:seek("set", 0)  -- 将文件指针移动到文件开头
        f:write("12345")  -- 写入新数据
        f:seek("end", 0)  -- 将文件指针移回到文件结尾
        f:write("hello")  -- 写入新数据
        f:close()  -- 关闭文件
    end

    if fs then
        -- 根目录是可读写的
        log.info("fsstat", fs.fsstat("/"))
        -- /luadb/ 是只读的
        log.info("fsstat", fs.fsstat("/luadb/"))
    end

    local ret, files = io.lsdir("/")
    log.info("fs", "lsdir", json.encode(files))

    ret, files = io.lsdir("/luadb/")
    log.info("fs", "lsdir", json.encode(files))

    -- 读取刷机时加入的文件, 并演示按行读取
    -- 刷机时选取的非lua文件, 均存放在/luadb/目录下, 单层无子文件夹
    f = io.open("/luadb/abc.txt", "rb")
    if f then
        while true do
            local line = f:read("l")
            if not line or #line == 0 then
                break
            end
            log.info("fs", "read line", line)
        end
        f:close()
        log.info("fs", "close f")
    else
        log.info("fs", "pls add abc.txt!!")
    end

    -- 文件夹操作
    sys.wait(3000)
    io.mkdir("/iot/")
    f = io.open("/iot/1.txt", "w+")
    if f then
        f:write("hi, LuatOS " .. os.date())
        f:close()
    else
        log.info("fs", "open file for write failed")
    end
    f = io.open("/iot/1.txt", "r")
    if f then
        local data = f:read("*a")
        f:close()
        log.info("fs", "writed data", data)
    else
        log.info("fs", "open file for read failed")
    end

    -- 2023.6.6 新增 io.readFile支持配置起始位置和长度
    io.writeFile("/test.txt", "0123456789")
    log.info("stream", io.readFile("/test.txt", "rb", 3, 5))
end

sys.taskInit(function()
    -- 为了显示日志,这里特意延迟一秒
    -- 正常使用不需要delay
    sys.wait(1000)
    fs_test()
end)

--[[
socket客户端演示


支持的协议有: TCP/UDP/TLS-TCP/DTLS, 更高层级的协议,如http有单独的库

提示: 
1. socket支持多个连接的, 通常最多支持8个, 可通过不同的taskName进行区分
2. 支持与http/mqtt/websocket/ftp库同时使用, 互不干扰
3. 支持IP和域名, 域名是自动解析的, 但解析域名也需要耗时
4. 加密连接(TLS/SSL)需要更多内存, 这意味着能容纳的连接数会小很多, 同时也更慢

对于多个网络出口的场景, 例如Air780E+W5500组成4G+以太网:
1. 在socket.create函数设置网络适配器的id
2. 请到同级目录查阅更细致的demo

如需使用ipv6, 请查阅 demo/ipv6, 本demo只涉及ipv4
]]

-=========================================
-- 初始化GPIO
local blueLedPin = 1
local redLedPin = 16

-- ledTest   两个led灯，一个蓝灯，一个红灯
local blueLed = gpio.setup(blueLedPin, 0)
local redLed = gpio.setup(redLedPin, 0)

--==========================================
--=============================================================
-- 测试网站 https://netlab.luatos.com/ 点击 打开TCP 获取测试端口号
-- 要按实际情况修改
local host = "112.125.89.8" -- 服务器ip或者域名, 都可以的
local port = 43102          -- 服务器端口号
local is_udp = false        -- 如果是UDP, 要改成true, false就是TCP
local is_tls = false        -- 加密与否, 要看服务器的实际情况
--=============================================================
local function LEDSet(s)    -- Led 灯设置   
    if string.find(s, "blue on") then
        blueLed(1)
    elseif string.find(s, "blue off") then
            blueLed(0)
    elseif   string.find(s, "red on") then
        redLed(1)
    elseif   string.find(s, "red off") then
        redLed(0)
    end
    log.info("LEDSet", s)
end

-- 处理未识别的网络消息
local function netCB(msg)
	log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end



-- 演示task
local function sockettest()
    -- 等待联网
    sys.waitUntil("IP_READY")   --会在此处等待，直到IP_READY（注册基站成功）消息过来，才会向下走

    socket.sntp()

    -- 开始正在的逻辑, 发起socket链接,等待数据/上报心跳
    local taskName = "sc"
    local topic = taskName .. "_txrx"
    log.info("topic", topic)
    local txqueue = {}
    sysplus.taskInitEx(sockettask, taskName, netCB, taskName, txqueue, topic)
    while 1 do
        local result, tp, data = sys.waitUntil(topic, 30000)
        log.info("event", result, tp, data)
        if not result then
            -- 等很久了,没数据上传/下发, 发个日期心跳包吧
            table.insert(txqueue, os.date())
            sys_send(taskName, socket.EVENT, 0)
        elseif tp == "uplink" then
            -- 上行数据, 主动上报的数据,那就发送呀
            table.insert(txqueue, data)
            sys_send(taskName, socket.EVENT, 0)
        elseif tp == "downlink" then
            -- 下行数据,接收的数据, 从ipv6task来的
            -- 其他代码可以通过 sys.publish()
            LEDSet(data)
            log.info("socket", "收到下发的数据了", #data)
        end
    end
end



function sockettask(d1Name, txqueue, rxtopic)
    -- 打印准备连接的服务器信息
    log.info("socket", host, port, is_udp and "UDP" or "TCP", is_tls and "TLS" or "RAW")

    -- 准备好所需要的接收缓冲区
    local rx_buff = zbuff.create(1024)
    local netc = socket.create(nil, d1Name)
    socket.config(netc, nil, is_udp, is_tls)
    log.info("任务id", d1Name)

    while true do
        -- 连接服务器, 15秒超时
        log.info("socket", "开始连接服务器")
        sysplus.cleanMsg(d1Name)
        local result = libnet.connect(d1Name, 15000, netc, host, port)
        if result then
			log.info("socket", "服务器连上了")
			libnet.tx(d1Name, 0, netc, "helloworld")
        else
            log.info("socket", "服务器没连上了!!!")
		end
		while result do
            -- 连接成功之后, 先尝试接收
            -- log.info("socket", "调用rx接收数据")
			local succ, param = socket.rx(netc, rx_buff)
			if not succ then
				log.info("服务器断开了", succ, param, ip, port)
				break
			end
            -- 如果服务器有下发数据, used()就必然大于0, 进行处理
			if rx_buff:used() > 0 then
				log.info("socket", "收到服务器数据，长度", rx_buff:used())
                local data = rx_buff:query() -- 获取数据
                sys.publish(rxtopic, "downlink", data)
				rx_buff:del()
			end
            -- log.info("libnet", "调用wait开始等待消息")
            -- 等待事件, 例如: 服务器下发数据, 有数据准备上报, 服务器断开连接
			result, param, param2 = libnet.wait(d1Name, 15000, netc)
            log.info("libnet", "wait", result, param, param2)
			if not result then
                -- 网络异常了, 那就断开了, 执行清理工作
				log.info("socket", "服务器断开了", result, param)
				break
            elseif #txqueue > 0 then
                -- 有待上报的数据,处理之
                while #txqueue > 0 do
                    local data = table.remove(txqueue, 1)
                    if not data then
                        break
                    end
                    result,param = libnet.tx(d1Name, 15000, netc,data)
                    log.info("libnet", "发送数据的结果", result, param)
                    if not result then
                        log.info("socket", "数据发送异常", result, param)
                        break
                    end
                end
            end
            -- 循环尾部, 继续下一轮循环
		end
        -- 能到这里, 要么服务器断开连接, 要么上报(tx)失败, 或者是主动退出
		libnet.close(d1Name, 5000, netc)
		-- log.info(rtos.meminfo("sys"))
		sys.wait(30000) -- 这是重连时长, 自行调整
    end
end

sys.taskInit(sockettest)

-- 演示定时上报数据, 不需要就注释掉
sys.taskInit(function()
    sys.wait(5000)
    while 1 do
        sys.publish("sc_txrx", "uplink", os.date())
        sys.wait(3000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
