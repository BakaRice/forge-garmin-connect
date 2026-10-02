using Toybox.Application;
using Toybox.WatchUi;

//! Forge 输入代理 (docs/README.md §17)
//!
//! 将 FR255 实体按钮映射为 Session 操作 (docs/README.md §14):
//!   ENTER/START  → Start / Stop / Save
//!   BACK/ESC     → 退出 / 丢弃
//!   UP/DOWN      → Phase D: 确认框选择
//!
//! 正常流程 (docs/update.md §3.1):
//!   READY → START → RECORDING → STOP → SUMMARY → SAVE → SAVED → EXIT
//! STOP 只停止并进入汇总, 不自动保存。
class ForgeDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    //! ENTER / START
    function onSelect() {
        var app = getApp();
        switch (app.getUiState()) {
            case ForgeState.UI_READY:
                app.startSession();
                break;
            case ForgeState.UI_RECORDING:
                app.stopSession();
                break;
            case ForgeState.UI_SUMMARY:
                app.saveSession();
                break;
            case ForgeState.UI_SAVED:
                // 自动退出中, 忽略按键
                break;
            case ForgeState.UI_CONFIRM:
                // Phase D: 执行当前选择 (默认停在 Cancel / No, docs/update.md §3.2)
                break;
        }
        return true;
    }

    //! BACK / ESC
    function onBack() {
        var app = getApp();
        switch (app.getUiState()) {
            case ForgeState.UI_READY:
                // 允许系统默认行为: 直接退出 App
                return false;
            case ForgeState.UI_RECORDING:
                // Phase D: 进入退出确认框; 记录保持继续 (docs/update.md §3.2)
                // Phase B: 消费 BACK, 不退出
                return true;
            case ForgeState.UI_SUMMARY:
                // Phase D: 改为丢弃确认框 (默认 No)
                // Phase B: 直接丢弃并返回 READY
                app.discardSession();
                return true;
            case ForgeState.UI_CONFIRM:
                // Phase D: Cancel, 返回进入来源
                return true;
            case ForgeState.UI_SAVED:
                // 已保存, 允许退出
                return false;
        }
        return false;
    }

    //! UP — Phase D: 确认框选择
    function onPreviousPage() {
        // Phase D: CONFIRM 状态中切换选项
        return false;
    }

    //! DOWN — Phase D: 确认框选择
    function onNextPage() {
        // Phase D: CONFIRM 状态中切换选项
        return false;
    }

    hidden function getApp() {
        return Application.getApp() as ForgeApp;
    }
}
