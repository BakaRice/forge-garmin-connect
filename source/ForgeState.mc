//! Forge 状态定义 (docs/update.md §3.2)
//!
//! 会话状态与界面状态分开表达:
//!   - 会话状态由 ForgeSession 管理, 反映真实 Garmin Session 生命周期
//!   - 界面状态由 ForgeApp 管理, 驱动页面绘制
//!
//! 界面可附带错误信息, 但错误提示不能覆盖真实会话状态。
module ForgeState {

    //! 会话状态 (docs/update.md §3.2)
    enum {
        SESSION_IDLE,      // 没有待处理会话
        SESSION_PREPARED,  // 已创建 Session, 尚未成功开始 (含开始失败后等待清理)
        SESSION_RECORDING, // 已成功开始, 正在记录
        SESSION_STOPPED,   // 已停止, 尚未成功保存或丢弃
        SESSION_CLOSED     // 已成功保存或丢弃
    }

    //! 界面状态 (docs/update.md §3.2)
    enum {
        UI_READY,     // 等待开始
        UI_RECORDING, // 记录中
        UI_SUMMARY,   // 本次结果 (已停止, 未保存)
        UI_CONFIRM,   // 等待用户确认 (退出 / 丢弃; 会话不受影响)
        UI_SAVED      // 保存成功, 短暂展示后退出
    }

    //! 确认框待确认动作 (docs/update.md §3.2) — 必须保留进入来源和待确认动作
    enum {
        CONFIRM_NONE,     // 无待确认动作
        CONFIRM_EXIT,     // Recording 中退出: Stop & Save / Discard / Cancel
        CONFIRM_DISCARD   // Summary 中丢弃: Discard / Cancel
    }

    //! 界面错误标识 (docs/update.md §3.2: 错误提示附带显示, 不覆盖会话状态)
    enum {
        ERROR_NONE,     // 无错误
        ERROR_START,    // 开始失败
        ERROR_STOP,     // 停止失败
        ERROR_SAVE,     // 保存失败
        ERROR_DISCARD   // 放弃失败
    }
}
