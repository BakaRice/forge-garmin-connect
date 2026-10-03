using Toybox.Application;
using Toybox.System;
using Toybox.Activity;
using Toybox.ActivityRecording;
using Toybox.Sensor;

//! ForgeSession — 整个项目最核心的业务类 (docs/README.md §17)
//!
//! 统一管理: 会话生命周期、数据快照、Garmin API 调用 (docs/update.md §3.3)。
//! UI 只允许调用 ForgeSession, 不允许直接 createSession() (docs/README.md §33/§34)。
//!
//! Phase B: 最小记录闭环 (docs/update.md §8)
//!   - 官方 start / stop / save / discard 均返回 Boolean, 每个返回值都要检查 (§4)
//!   - 心率走 Activity.Info 原生字段, null 安全 (§5.2)
class ForgeSession {

    //! 会话状态 (ForgeState.SESSION_*)
    //! 注意 (docs/update.md §4): isRecording() 只用于判断是否正在记录,
    //! 不能单独用于判断 Session 是否已经保存、丢弃或关闭。
    hidden var _state = ForgeState.SESSION_IDLE;

    //! Garmin ActivityRecording.Session 句柄
    hidden var _session = null;
    hidden var _motion = null;
    hidden var _motionFit = null;

    //! 停止时固定的本次汇总快照 (docs/update.md §5.2: 保存前固定,
    //! 避免保存后 Session 关闭导致界面丢失数据)
    hidden var _durationMs = 0;
    hidden var _avgHr = null;
    hidden var _maxHr = null;

    //! 心率备用统计 (docs/update.md §5.2) — 备用路径,
    //! Phase B 优先使用 Activity.Info 原生值
    hidden var _heartRateSum = 0;
    hidden var _heartRateCount = 0;
    hidden var _maxHeartRate = 0;

    //! 开始一次 Session (docs/update.md §4)
    //! 1. 按官方流程先启用需要记录的传感器, 再创建并开始 Session (§5.1)
    //! 2. createSession + start, 逐一检查返回值
    //! 失败: 保留引用核对状态, 受控清理, 绝不创建第二个 Session
    function start() {
        trace("SESSION_START");
        if (_session != null) {
            trace("HAS_SESSION");
            // 上一会话尚未关闭: 不允许开始下一会话 (docs/update.md §3.2)
            return false;
        }

        // 心率来源策略 (docs/update.md §5.1): 系统可用心率来源
        // 传感器启用失败不阻塞 Session (docs/README.md §24: Sensor 数据永远是 Optional)
        try {
            trace("SENSOR");
            Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        } catch (e) {
            System.println("[FORGE-FIX1003] SENSOR_EXCEPTION " + e.getErrorMessage());
            // 忽略: 无心率时活动仍可正常记录
        }

        // SDK 9 类型定义中 createSession 返回非空 Session,
        // 但真机存在运行时失败路径 (docs/update.md §4: 处理创建选项无效等异常),
        // 统一 try/catch 兜底, 失败显示错误而不是闪退
        var session = null;
        try {
            trace("CREATE");
            session = ActivityRecording.createSession({
                :name     => "Forge",
                :sport    => Activity.SPORT_GENERIC,     // docs/update.md §4:
                :subSport => Activity.SUB_SPORT_GENERIC  // 不使用已弃用的旧枚举
            });
        } catch (e) {
            trace("CREATE_EX");
            System.println("[FORGE-FIX1003] CREATE_EXCEPTION " + e.getErrorMessage());
            session = null;
        }

        if (session == null) {
            if ((Application.getApp() as ForgeApp).getDbgStage() != "CREATE_EX") { trace("CREATE_NULL"); }
            // 创建失败: 不进入 Recording (docs/update.md §4)
            _state = ForgeState.SESSION_IDLE;
            return false;
        }

        _session = session;
        _state = ForgeState.SESSION_PREPARED;

        var startFailure = "START_FALSE";
        var started = false;
        try {
            trace("START");
            started = _session.start();
            System.println("[FORGE-FIX1003] start result=" + started);
        } catch (e) {
            trace("START_EX");
            startFailure = "START_EX";
            System.println("[FORGE-FIX1003] START_EXCEPTION " + e.getErrorMessage());
            started = false;
        }

        if (!started) {
            // start 失败: 保留引用并核对实际记录状态, 受控清理 (docs/update.md §4)
            if (_session.isRecording()) {
                // 实际已在记录: 按已开始处理
                _state = ForgeState.SESSION_RECORDING;
                trace("RECORDING");
                startMotion();
                return true;
            }
            trace("CLEANUP");
            _session.discard();
            _session = null;
            _state = ForgeState.SESSION_IDLE;
            trace(startFailure);
            return false;
        }

        trace("RECORDING");
        _state = ForgeState.SESSION_RECORDING;
        startMotion();
        return true;
    }

    //! 停止记录 (docs/update.md §4)
    //! 成功: 固定本次汇总快照, 进入 STOPPED
    //! 失败: 不宣称已经停止, 保留引用, 允许重试
    function stop() {
        if (_state != ForgeState.SESSION_RECORDING || _session == null) {
            return false;
        }

        updateMotionFit();
        var stopped = false;
        try {
            stopped = _session.stop();
        } catch (e) {
            stopped = false;
        }

        if (!stopped) {
            return false;
        }

        _state = ForgeState.SESSION_STOPPED;
        stopMotion();

        // 固定快照 (docs/update.md §5.2: 保存前固定)
        // getActivityInfo() 在 SDK 9 类型定义为非空返回
        var info = Activity.getActivityInfo();
        _durationMs = (info.timerTime != null) ? info.timerTime : 0;
        _avgHr = info.averageHeartRate;
        _maxHr = info.maxHeartRate;
        return true;
    }

    //! 保存为 FIT Activity (docs/update.md §4)
    //! 失败: 保持待处理会话, 不清空引用, 不自动丢弃, 允许重试或明确丢弃
    function save() {
        if (_state != ForgeState.SESSION_STOPPED || _session == null) {
            return false;
        }

        var saved = false;
        try {
            saved = _session.save();
        } catch (e) {
            saved = false;
        }

        if (!saved) {
            return false;
        }

        _state = ForgeState.SESSION_CLOSED;
        release();
        return true;
    }

    //! 放弃本次 Session (docs/update.md §4)
    //! 失败: 保留引用, 不能宣称已丢弃
    function discard() {
        if (_session == null) {
            return false;
        }

        var discarded = false;
        try {
            discarded = _session.discard();
        } catch (e) {
            discarded = false;
        }

        if (!discarded) {
            return false;
        }

        _state = ForgeState.SESSION_CLOSED;
        release();
        return true;
    }

    //! 关闭会话后释放引用和传感器资源 (docs/update.md §5.1)
    hidden function release() {
        stopMotion();
        if (_motionFit != null) { _motionFit.release(); }
        _session = null;
        try {
            Sensor.setEnabledSensors([]);
        } catch (e) {
            // 释放失败不阻塞
        }
    }

    hidden function trace(stage) {
        (Application.getApp() as ForgeApp).setDbgStage(stage);
    }

    //! 当前会话状态
    function getState() {
        return _state;
    }

    //! 记录时长 (毫秒) — Activity.Info.timerTime (docs/update.md §5.2)
    //! 停止前返回实时值; 停止后返回固定快照 (Summary 停留不计入, §5.3)
    function getDuration() {
        if (_state == ForgeState.SESSION_STOPPED || _state == ForgeState.SESSION_CLOSED) {
            return _durationMs;
        }
        var info = Activity.getActivityInfo();
        if (info.timerTime != null) {
            return info.timerTime;
        }
        return 0;
    }

    //! 实时心率 (bpm) — Activity.Info.currentHeartRate, 传感器不可用时为 null
    function getCurrentHeartRate() {
        return Activity.getActivityInfo().currentHeartRate;
    }

    //! 平均心率 (bpm) — Activity.Info.averageHeartRate, 原生值优先 (docs/update.md §5.2)
    function getAverageHeartRate() {
        return _avgHr;
    }

    //! 最大心率 (bpm) — Activity.Info.maxHeartRate, 原生值优先
    function getMaxHeartRate() {
        return _maxHr;
    }
    hidden function startMotion() {
        _durationMs = 0; _avgHr = null; _maxHr = null;
        if (_motion != null) { _motion.stop(); }
        _motion = new ForgeMotion();
        _motionFit = new ForgeMotionFit();
        _motion.start(method(:onMotionUpdate));
    }

    function onMotionUpdate() { updateMotionFit(); }

    hidden function updateMotionFit() {
        if (_state != ForgeState.SESSION_RECORDING || _session == null || _motionFit == null) { return; }
        _motionFit.update(_session, getMotionCount(), getAverageMotionCadence());
    }

    function stopMotion() { if (_motion != null) { _motion.stop(); } }
    function getMotionCount() { return _motion != null ? _motion.getCount() : null; }
    function getCurrentMotionCadence() { return _motion != null ? _motion.getCadence() : null; }
    function getAverageMotionCadence() {
        var count = getMotionCount();
        var duration = getDuration();
        return count != null && duration > 0 ? count * 60000.0 / duration : null;
    }
    function getMotionStatus() { return _motion != null ? _motion.getStatus() : "idle"; }
    function getMotionPhase() { return _motion != null ? _motion.getPhase() : 0; }
    function getMotionAccelStatus() { return _motion != null ? _motion.getAccelStatus() : "waiting"; }
    function getMotionAccelDebug() {
        var status = getMotionAccelStatus();
        if (status.equals("active")) { return "A1"; }
        if (status.equals("missing")) { return "A0"; }
        if (status.equals("unsupported")) { return "A-"; }
        if (status.equals("stale")) { return "Ast"; }
        if (status.equals("error")) { return "A!"; }
        return "A?";
    }
}
