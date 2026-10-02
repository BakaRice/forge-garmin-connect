using Toybox.Application;
using Toybox.System;
using Toybox.Timer;
using Toybox.WatchUi;

//! Forge 应用入口 (docs/README.md §17, docs/update.md §3.3)
//!
//! 职责: 持有界面状态并编排 Session 操作。
//! 会话状态由 ForgeSession 统一管理; 界面错误信息不覆盖真实会话状态 (§3.2)。
class ForgeApp extends Application.AppBase {

    //! 当前界面状态 (ForgeState.UI_*)
    hidden var _uiState = ForgeState.UI_READY;

    //! 确认框进入来源与待确认动作 (Phase D, docs/update.md §3.2)
    hidden var _confirmOrigin = ForgeState.UI_READY;
    hidden var _confirmAction = ForgeState.CONFIRM_NONE;

    //! 界面错误标识 (docs/update.md §3.2: 附带显示, 不覆盖会话状态)
    hidden var _errorId = ForgeState.ERROR_NONE;

    //! 核心业务对象，惰性创建
    hidden var _session = null;

    //! UI 刷新定时器 — 只驱动界面刷新 (docs/update.md §5.3),
    //! 时长以 Activity.Info.timerTime 为准, 不采用"回调加一秒"的累计方式
    hidden var _uiTimer = null;

    function initialize() {
        AppBase.initialize();
    }

    //! 应用启动 / 从后台恢复
    function onStart(state) {
        // Phase D: 从 Application.Storage 恢复必要状态 (docs/README.md §12)
        // lastSession 只用于体验/诊断, 不等于恢复了 Garmin 原生 Session (docs/update.md §7)
    }

    //! 应用切后台 / 退出
    //! 注意 (docs/update.md §7): 官方不保证断电/崩溃时必然执行 onStop,
    //! 这里只做防御性资源清理, 不设计需要用户操作的确认流程。
    function onStop(state) {
        if (_session != null && _session.getState() != ForgeState.SESSION_CLOSED) {
            _session.discard();
        }
    }

    //! 入口 View + Delegate
    function getInitialView() {
        return [ new ForgeView(), new ForgeDelegate() ];
    }

    //! 当前界面状态
    function getUiState() {
        return _uiState;
    }

    //! 切换界面状态并刷新 UI
    function setUiState(state) {
        _uiState = state;
        WatchUi.requestUpdate();
    }

    //! 当前错误标识 (ERROR_NONE 表示无错误)
    function getErrorId() {
        return _errorId;
    }

    hidden function setErrorId(errorId) {
        _errorId = errorId;
        WatchUi.requestUpdate();
    }

    //! Session 唯一入口 (docs/README.md §33: 禁止页面自行 createSession)
    function getSession() {
        if (_session == null) {
            _session = new ForgeSession();
        }
        return _session;
    }

    //! START — 开始记录 (docs/update.md §3.1: 成功才进入下一状态)
    function startSession() {
        _errorId = ForgeState.ERROR_NONE;
        if (getSession().start()) {
            setUiState(ForgeState.UI_RECORDING);
            startUiTimer();
        } else {
            setErrorId(ForgeState.ERROR_START);
        }
    }

    //! STOP — 停止记录, 进入汇总 (不自动保存, docs/update.md §3.1)
    function stopSession() {
        if (getSession().stop()) {
            stopUiTimer();
            setUiState(ForgeState.UI_SUMMARY);
        } else {
            setErrorId(ForgeState.ERROR_STOP);
        }
    }

    //! SAVE — 保存为 FIT Activity (docs/update.md §4: 失败不退出, 可重试)
    function saveSession() {
        if (getSession().save()) {
            setUiState(ForgeState.UI_SAVED);
            exitSoon();
        } else {
            setErrorId(ForgeState.ERROR_SAVE);
        }
    }

    //! DISCARD — 放弃本次 Session
    function discardSession() {
        if (getSession().discard()) {
            setUiState(ForgeState.UI_READY);
        } else {
            setErrorId(ForgeState.ERROR_DISCARD);
        }
    }

    //! 每秒刷新一次界面 (仅 UI, 不改数据)
    hidden function startUiTimer() {
        if (_uiTimer == null) {
            _uiTimer = new Timer.Timer();
        }
        _uiTimer.start(method(:onUiTick), 1000, true);
    }

    hidden function stopUiTimer() {
        if (_uiTimer != null) {
            _uiTimer.stop();
        }
    }

    function onUiTick() as Void {
        WatchUi.requestUpdate();
    }

    //! SAVED 短暂展示后退出应用 (docs/update.md §3.1)
    hidden function exitSoon() {
        var timer = new Timer.Timer();
        timer.start(method(:exitApp), 2500, false);
    }

    function exitApp() as Void {
        System.exit();
    }
}
