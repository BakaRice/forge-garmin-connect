using Toybox.Application;
using Toybox.System;
using Toybox.Timer;
using Toybox.WatchUi;

//! Forge 应用入口 (docs/README.md §17, docs/update.md §3.3)
//!
//! 职责: 持有界面状态并编排 Session 操作。
//! 确认框保留进入来源和待确认动作, 默认停在 Cancel/No (docs/update.md §3.2)。
//! 会话状态由 ForgeSession 统一管理; 界面错误信息不覆盖真实会话状态。
class ForgeApp extends Application.AppBase {

    //! 按键防抖 (ms) — 快速连按不重复处理同一操作 (docs/update.md §9)
    hidden const DEBOUNCE_MS = 500;

    //! 当前界面状态 (ForgeState.UI_*)
    hidden var _uiState = ForgeState.UI_READY;

    //! 确认框进入来源与待确认动作 (docs/update.md §3.2)
    hidden var _confirmOrigin = ForgeState.UI_READY;
    hidden var _confirmAction = ForgeState.CONFIRM_NONE;
    hidden var _confirmSelection = 0;

    //! 界面错误标识 (docs/update.md §3.2: 附带显示, 不覆盖会话状态)
    hidden var _errorId = ForgeState.ERROR_NONE;

    //! 上次操作时间戳 (防抖)
    hidden var _lastActionAt = 0;

    //! 核心业务对象，惰性创建
    hidden var _session = null;

    //! UI 刷新定时器 — 只驱动界面刷新 (docs/update.md §5.3),
    //! 时长以 Activity.Info.timerTime 为准
    hidden var _uiTimer = null;

    function initialize() {
        AppBase.initialize();
    }

    //! 应用启动 / 从后台恢复
    function onStart(state) {
        // Phase D+: 从 Application.Storage 恢复必要状态 (docs/README.md §12)
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

    //! 防抖: 距上次操作不足 DEBOUNCE_MS 时忽略本次按键 (docs/update.md §9)
    hidden function debounced() {
        var now = System.getTimer();
        if (now - _lastActionAt < DEBOUNCE_MS) {
            return true;
        }
        _lastActionAt = now;
        return false;
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
        if (debounced()) { return; }
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
        if (debounced()) { return; }
        if (getSession().stop()) {
            stopUiTimer();
            setUiState(ForgeState.UI_SUMMARY);
        } else {
            setErrorId(ForgeState.ERROR_STOP);
        }
    }

    //! SAVE — 保存为 FIT Activity (docs/update.md §4: 失败不退出, 可重试)
    function saveSession() {
        if (debounced()) { return; }
        if (getSession().save()) {
            setUiState(ForgeState.UI_SAVED);
            exitSoon();
        } else {
            setErrorId(ForgeState.ERROR_SAVE);
        }
    }

    //! DISCARD — 放弃本次 Session
    function discardSession() {
        if (debounced()) { return; }
        if (getSession().discard()) {
            setUiState(ForgeState.UI_READY);
        } else {
            setErrorId(ForgeState.ERROR_DISCARD);
        }
    }

    //! 停止并保存 (确认框路径, docs/update.md §3.2)
    //! 停止成功后再保存; 任一步失败保留会话并提示
    function stopAndSave() {
        if (debounced()) { return; }
        var session = getSession();
        if (!session.stop()) {
            // stop 失败: 保留会话, 回 RECORDING 提示重试; UI 计时器继续
            setUiState(ForgeState.UI_RECORDING);
            setErrorId(ForgeState.ERROR_STOP);
            return;
        }
        stopUiTimer();
        if (!session.save()) {
            // save 失败: 保持待处理会话 (STOPPED), 允许重试或明确丢弃 (§4)
            setUiState(ForgeState.UI_SUMMARY);
            setErrorId(ForgeState.ERROR_SAVE);
            return;
        }
        setUiState(ForgeState.UI_SAVED);
        exitSoon();
    }

    //! 打开确认框 (docs/update.md §3.2: 保留进入来源和待确认动作)
    function openConfirm(action, origin) {
        _confirmAction = action;
        _confirmOrigin = origin;
        // 默认停在 Cancel/No — 最后一个选项 (docs/update.md §3.2)
        _confirmSelection = confirmOptionCount(action) - 1;
        _errorId = ForgeState.ERROR_NONE;
        setUiState(ForgeState.UI_CONFIRM);
    }

    //! 取消确认, 返回进入来源 (会话状态不受影响, 计时继续)
    function cancelConfirm() {
        setUiState(_confirmOrigin);
        _confirmAction = ForgeState.CONFIRM_NONE;
        WatchUi.requestUpdate();
    }

    //! ENTER: 执行当前选中项
    function confirmSelect() {
        switch (_confirmAction) {
            case ForgeState.CONFIRM_EXIT:
                if (_confirmSelection == 0) {
                    // 停止并保存
                    stopAndSave();
                } else if (_confirmSelection == 1) {
                    // 放弃 → 进入明确的丢弃确认 (docs/update.md §3.2)
                    openConfirm(ForgeState.CONFIRM_DISCARD, _confirmOrigin);
                } else {
                    // 取消
                    cancelConfirm();
                }
                break;
            case ForgeState.CONFIRM_DISCARD:
                if (_confirmSelection == 0) {
                    doDiscardConfirm();
                } else {
                    cancelConfirm();
                }
                break;
        }
    }

    //! 确认丢弃 (docs/update.md §3.2: 只有用户确认且丢弃成功后才退出/返回)
    hidden function doDiscardConfirm() {
        if (debounced()) { return; }
        if (getSession().discard()) {
            _confirmAction = ForgeState.CONFIRM_NONE;
            if (_confirmOrigin == ForgeState.UI_RECORDING) {
                // 来自退出流程: 丢弃成功 → 退出应用
                System.exit();
            } else {
                // 来自 Summary: 丢弃成功 → 返回 READY
                setUiState(ForgeState.UI_READY);
            }
        } else {
            // 丢弃失败: 保留引用, 不能宣称已丢弃 (docs/update.md §4)
            setErrorId(ForgeState.ERROR_DISCARD);
        }
    }

    //! UP — 确认框选项上移
    function confirmPrev() {
        if (_confirmSelection > 0) {
            _confirmSelection--;
            WatchUi.requestUpdate();
        }
    }

    //! DOWN — 确认框选项下移
    function confirmNext() {
        if (_confirmSelection < confirmOptionCount(_confirmAction) - 1) {
            _confirmSelection++;
            WatchUi.requestUpdate();
        }
    }

    hidden function confirmOptionCount(action) {
        return (action == ForgeState.CONFIRM_EXIT) ? 3 : 2;
    }

    //! 确认框状态 (View 绘制用)
    function getConfirmAction() {
        return _confirmAction;
    }

    function getConfirmSelection() {
        return _confirmSelection;
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
