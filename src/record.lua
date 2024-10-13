

-- 音频事件回调函数，处理不同类型的音频事件
-- @param id 通道id
-- @param event 事件类型，可以是以下之一：
--               0 开始解码文件
--               1 开始输出解码后的音数据
--               2 MORE_DATA: 底层驱动播放播放完一部分数据，需要更多数据
--               3 AUDIO_DONE: 底层驱动播放完全部数据了
--               4 DONE: 音频解码完成
--               5 TTS做完了必要的初始化，用户可以通过audio_play_tts_set_param做个性化配置
--               6 TTS编码完成了。注意不是播放完成
--               7 RECORD_DATA: 录音数据
--               8 RECORD_DONE: 录音完成
-- @param buff 事件相关的数据缓冲区
audio.on(0, function(id, event, buff)
    log.info("audio.on", id, event)
    -- 使用play来播放文件时只有播放完成回调
    if event == audio.RECORD_DATA then -- 录音数据

    elseif event == audio.RECORD_DONE then -- 录音完成
        sys.publish("AUDIO_RECORD_DONE")
    elseif event == audio.DONE or event == audio.MORE_DATA then -- 播放音频的事件
        local succ, stop, file_cnt = audio.getError(0)
        if not succ then
            if stop then
                log.info("用户停止播放")
            else
                log.info("第", file_cnt, "个文件解码失败")
            end
        end
        log.info("播放完成一个音频")
        sys.publish("AUDIO_PLAY_DONE")
    end
end)

-- 初始化音频函数，传入音量和麦克风音量参数
-- @param volume 音量，范围从0到100
-- @param mic_volume 麦克风音量，范围从0到100
function audio_init(volume, mic_volume)
    mcu.altfun(mcu.I2C, es8311i2cId, 13, 2, 0)
    mcu.altfun(mcu.I2C, es8311i2cId, 14, 2, 0)

    i2c.setup(es8311i2cId, i2c.SLOW)
    i2s.setup(0, 0, 16000, 16, i2s.MONO_R, i2s.MODE_LSB, 16)

    audio.config(0, paPin, 1, 3, 100, es8311PowerPin, 1, 100)
    audio.setBus(0, audio.BUS_I2S, {
        chip = "es8311",
        i2cid = es8311i2cId,
        i2sid = 0,
        voltage = audio.VOLTAGE_1800
    }) -- 通道0的硬件输出通道设置为I2S

    audio.vol(0, volume)
    audio.micVol(0, mic_volume)
    audio.pm(0, audio.POWEROFF)

    sys.publish("AUDIO_INIT_DONE")
end

-- 录音文件存放路径
local recordPath = "/record.amr"
sys.taskInit(function()
    audio_init(80, 80)    -- 初始化音频设置，输出音量80，输入音量80

    sys.waitUntil("AUDIO_INIT_DONE")    -- 等待音频初始化成功
    while(true) do
        sys.wait(5000)  -- 初始化成功后延时5s，开始录音

        -- 只读模式, 打开文件
        local fd = io.open(recordPath, "rb")
        -- 开始录音
        log.info("准备开始录音")
        blueLed(1)
        audio.pm(0, audio.RESUME)   -- 工作模式
        local err = audio.record(0, audio.AMR, 5, 7, recordPath)    -- 录制AMR格式，时长为5s的录音数据
        result = sys.waitUntil("AUDIO_RECORD_DONE", 10000)  -- 等待录音结束，并设置10s超时（超时时间要设置的比录制时间长 否则会还没录完就被当做超时强制结束了）
        log.info("录音结束")
        blueLed(0)
        audio.pm(0, audio.POWEROFF) -- 断电模式

        sys.wait(2000)  -- 录音结束后延时2s

        -- 播放录音
        log.info("准备播放录音")
        redLed(1)
        local err = audio.play(0, recordPath)
        result = sys.waitUntil("AUDIO_PLAY_DONE", 10000)    -- 等待录音文件播放结束，并设置10s超时（超时时间要设置的比录制时间长 否则会还没播放完就被当做超时强制结束了）
        log.info("录音播放完成")
        redLed(0)
        audio.pm(0, audio.POWEROFF) -- 断电模式
        -- 执行完操作后,一定要关掉文件
        if fd then
            fd:close()
        end
    end
end)