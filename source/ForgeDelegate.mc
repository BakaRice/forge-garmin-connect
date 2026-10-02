using Toybox.Application;
using Toybox.WatchUi;

//! Forge 输入代理 (docs/README.md §17)
//!
//! 将 FR255 实体按钮映射为 Session 操作 (docs/README.md §14):
//!   ENTER/START  → Start / Stop / Save / 确认
//!   BACK/ESC     → 退出确认 / 丢弃确认 / 取消
//!   UP/DOWN      → 确认框选项选择
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
            case ForgeState.UI_CONFIRM:
                app.confirmSelect();
                break;
            case ForgeState.UI_SAVED:
                // 自动退出中, 忽略按键
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
                // 进入退出确认框; 记录保持继续 (docs/update.md §3.2)
                app.openConfirm(ForgeState.CONFIRM_EXIT, ForgeState.UI_RECORDING);
                return true;
            case ForgeState.UI_SUMMARY:
                // 进入丢弃确认框; 会话保持停止
                app.openConfirm(ForgeState.CONFIRM_DISCARD, ForgeState.UI_SUMMARY);
                return true;
            case ForgeState.UI_CONFIRM:
                // 取消, 返回进入来源
                app.cancelConfirm();
                return true;
            case ForgeState.UI_SAVED:
                // 已保存, 允许退出
                return false;
        }
        return false;
    }

    //! UP — 确认框选项上移
    function onPreviousPage() {
        if (getApp().getUiState() == ForgeState.UI_CONFIRM) {
            getApp().confirmPrev();
            return true;
        }
        return false;
    }

    //! DOWN — 确认框选项下移
    function onNextPage() {
        if (getApp().getUiState() == ForgeState.UI_CONFIRM) {
            getApp().confirmNext();
            return true;
        }
        return false;
    }

    hidden function getApp() {
        return Application.getApp() as ForgeApp;
    }
}
