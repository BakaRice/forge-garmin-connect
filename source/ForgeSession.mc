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
        if (_session != null) {
            // 上一会话尚未关闭: 不允许开始下一会话 (docs/update.md §3.2)
            return false;
        }

        // 心率来源策略 (docs/update.md §5.1): 系统可用心率来源
        // 传感器启用失败不阻塞 Session (docs/README.md §24: Sensor 数据永远是 Optional)
        try {
            Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        } catch (e) {
            // 忽略: 无心率时活动仍可正常记录
        }

        // SDK 9 类型定义中 createSession 返回非空 Session
        _session = ActivityRecording.createSession({
            :name     => "Forge",
            :sport    => Activity.SPORT_GENERIC,     // docs/update.md §4:
            :subSport => Activity.SUB_SPORT_GENERIC  // 不使用已弃用的旧枚举
        });
        _state = ForgeState.SESSION_PREPARED;

        if (!_session.start()) {
            // start 失败: 保留引用并核对实际记录状态, 受控清理 (docs/update.md §4)
            if (_session.isRecording()) {
                // 实际已在记录: 按已开始处理
                _state = ForgeState.SESSION_RECORDING;
                return true;
            }
            _session.discard();
            _session = null;
            _state = ForgeState.SESSION_IDLE;
            return false;
        }

        _state = ForgeState.SESSION_RECORDING;
        return true;
    }

    //! 停止记录 (docs/update.md §4)
    //! 成功: 固定本次汇总快照, 进入 STOPPED
    //! 失败: 不宣称已经停止, 保留引用, 允许重试
    function stop() {
        if (_state != ForgeState.SESSION_RECORDING || _session == null) {
            return false;
        }

        if (!_session.stop()) {
            return false;
        }

        _state = ForgeState.SESSION_STOPPED;

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

        if (!_session.save()) {
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

        if (!_session.discard()) {
            return false;
        }

        _state = ForgeState.SESSION_CLOSED;
        release();
        return true;
    }

    //! 关闭会话后释放引用和传感器资源 (docs/update.md §5.1)
    hidden function release() {
        _session = null;
        try {
            Sensor.setEnabledSensors([]);
        } catch (e) {
            // 释放失败不阻塞
        }
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
}
