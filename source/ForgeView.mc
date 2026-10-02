using Toybox.Application;
using Toybox.Graphics;
using Toybox.WatchUi;

//! Forge 主 View (docs/README.md §17, docs/update.md §3.3)
//!
//! 一个主 View 依据界面状态绘制 READY / RECORDING / SUMMARY / SAVED,
//! 确认界面 (CONFIRM) 单独处理 (Phase D)。
//!
//! 中文化 (2026-10-02):
//!   - 中文文案为预渲染位图 (tools/render_labels.swift 生成),
//!     因 FR255 无矢量字体 API, Garmin 中文字体超出 512KiB 内存上限;
//!   - FORGE 品牌名 / 数字 / bpm 使用默认字体;
//!   - 位图在 initialize() 加载一次并缓存, 不在 onUpdate 每秒加载。
class ForgeView extends WatchUi.View {

    //! 中文文案位图
    hidden var _imgStart = null;
    hidden var _imgStop = null;
    hidden var _imgSave = null;
    hidden var _imgDone = null;
    hidden var _imgSaved = null;
    hidden var _imgAvgHr = null;
    hidden var _imgMaxHr = null;
    hidden var _imgErrStart = null;
    hidden var _imgErrStop = null;
    hidden var _imgErrSave = null;
    hidden var _imgErrDiscard = null;
    hidden var _imgRecording = null;
    hidden var _imgDiscardAsk = null;
    hidden var _imgStopSave = null;
    hidden var _imgDiscard = null;
    hidden var _imgCancel = null;

    function initialize() {
        View.initialize();
        _imgStart = WatchUi.loadResource(Rez.Drawables.LabelStart);
        _imgStop = WatchUi.loadResource(Rez.Drawables.LabelStop);
        _imgSave = WatchUi.loadResource(Rez.Drawables.LabelSave);
        _imgDone = WatchUi.loadResource(Rez.Drawables.LabelDone);
        _imgSaved = WatchUi.loadResource(Rez.Drawables.LabelSaved);
        _imgAvgHr = WatchUi.loadResource(Rez.Drawables.LabelAvgHr);
        _imgMaxHr = WatchUi.loadResource(Rez.Drawables.LabelMaxHr);
        _imgErrStart = WatchUi.loadResource(Rez.Drawables.LabelErrStart);
        _imgErrStop = WatchUi.loadResource(Rez.Drawables.LabelErrStop);
        _imgErrSave = WatchUi.loadResource(Rez.Drawables.LabelErrSave);
        _imgErrDiscard = WatchUi.loadResource(Rez.Drawables.LabelErrDiscard);
        _imgRecording = WatchUi.loadResource(Rez.Drawables.LabelRecording);
        _imgDiscardAsk = WatchUi.loadResource(Rez.Drawables.LabelDiscardAsk);
        _imgStopSave = WatchUi.loadResource(Rez.Drawables.LabelStopSave);
        _imgDiscard = WatchUi.loadResource(Rez.Drawables.LabelDiscard);
        _imgCancel = WatchUi.loadResource(Rez.Drawables.LabelCancel);
    }

    function onUpdate(dc) {
        // 黑底 (docs/README.md §15: 高对比 / 少元素)
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        var cx = width / 2;
        var app = Application.getApp() as ForgeApp;

        switch (app.getUiState()) {
            case ForgeState.UI_READY:
                drawReady(dc, cx);
                break;
            case ForgeState.UI_RECORDING:
                drawRecording(dc, cx);
                break;
            case ForgeState.UI_SUMMARY:
                drawSummary(dc, cx);
                break;
            case ForgeState.UI_SAVED:
                drawSaved(dc, cx);
                break;
            case ForgeState.UI_CONFIRM:
                drawConfirm(dc, cx);
                break;
        }

        // 错误提示 — 附带显示, 不覆盖会话状态 (docs/update.md §3.2)
        var errImg = errorBitmapFor(app.getErrorId());
        if (errImg != null) {
            drawLabelCenter(dc, cx, 240, errImg);
        }
    }

    //! 居中绘制文案位图
    hidden function drawLabelCenter(dc, cx, y, bitmap) {
        dc.drawBitmap(cx - bitmap.getWidth() / 2, y - bitmap.getHeight() / 2, bitmap);
    }

    //! 绘制 FORGE 标题 (品牌名保持拉丁字母)
    hidden function drawTitle(dc, cx) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 50, Graphics.FONT_MEDIUM, "FORGE",
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! READY 页面 (docs/README.md §4.1)
    //!     FORGE
    //!     00:00
    //!     开始
    hidden function drawReady(dc, cx) {
        drawTitle(dc, cx);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 135, Graphics.FONT_NUMBER_HOT,
            ForgeUtils.formatDuration(0),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        drawLabelCenter(dc, cx, 215, _imgStart);
    }

    //! RECORDING 页面 (docs/README.md §5)
    //!     FORGE
    //!     06:32
    //!     98 bpm
    //!     停止
    hidden function drawRecording(dc, cx) {
        var session = (Application.getApp() as ForgeApp).getSession();

        drawTitle(dc, cx);

        // Duration — 页面视觉中心, 数据源 timerTime (docs/update.md §5.2)
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 120, Graphics.FONT_NUMBER_HOT,
            ForgeUtils.formatDuration(session.getDuration()),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // 心率 — null 时显示 -- bpm (docs/README.md §24)
        var hr = session.getCurrentHeartRate();
        var hrText = (hr != null) ? hr.format("%d") + " bpm" : "-- bpm";
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 178, Graphics.FONT_MEDIUM, hrText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        drawLabelCenter(dc, cx, 222, _imgStop);
    }

    //! SUMMARY 页面 (docs/README.md §10)
    //!     FORGE 完成
    //!      08:42
    //!   平均心率 98
    //!   最大心率 121
    //!      保存
    hidden function drawSummary(dc, cx) {
        var session = (Application.getApp() as ForgeApp).getSession();

        drawTitle(dc, cx);
        drawLabelCenter(dc, cx, 82, _imgDone);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 122, Graphics.FONT_NUMBER_HOT,
            ForgeUtils.formatDuration(session.getDuration()),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var avg = session.getAverageHeartRate();
        var max = session.getMaxHeartRate();
        drawStatLine(dc, cx, 172, _imgAvgHr,
            (avg != null) ? avg.format("%d") : "--");
        drawStatLine(dc, cx, 200, _imgMaxHr,
            (max != null) ? max.format("%d") : "--");

        drawLabelCenter(dc, cx, 232, _imgSave);
    }

    //! 统计行: [中文标签] + 数值 (默认字体)
    hidden function drawStatLine(dc, cx, y, labelImg, valueText) {
        var gap = 8;
        var labelW = labelImg.getWidth();
        var labelH = labelImg.getHeight();
        var valueW = dc.getTextWidthInPixels(valueText, Graphics.FONT_SMALL);
        var total = labelW + gap + valueW;
        var x = cx - total / 2;

        dc.drawBitmap(x, y - labelH / 2, labelImg);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + labelW + gap, y, Graphics.FONT_SMALL, valueText,
            Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! SAVED 页面 (docs/README.md §10: 短暂展示后退出)
    hidden function drawSaved(dc, cx) {
        var session = (Application.getApp() as ForgeApp).getSession();

        drawLabelCenter(dc, cx, 105, _imgSaved);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 160, Graphics.FONT_NUMBER_HOT,
            ForgeUtils.formatDuration(session.getDuration()),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! CONFIRM 页面 (docs/README.md §11, docs/update.md §3.2)
    //! 确认框保留进入来源和待确认动作; 默认停在 Cancel/No;
    //! 确认框期间会话不受影响 (计时继续 / 汇总保持停止)
    hidden function drawConfirm(dc, cx) {
        var app = Application.getApp() as ForgeApp;
        var action = app.getConfirmAction();
        var selection = app.getConfirmSelection();

        // 标题
        drawLabelCenter(dc, cx, 60,
            (action == ForgeState.CONFIRM_EXIT) ? _imgRecording : _imgDiscardAsk);

        if (action == ForgeState.CONFIRM_EXIT) {
            // 停止并保存 / 放弃 / 取消
            drawConfirmOption(dc, cx, 125, _imgStopSave, selection == 0);
            drawConfirmOption(dc, cx, 160, _imgDiscard, selection == 1);
            drawConfirmOption(dc, cx, 195, _imgCancel, selection == 2);
        } else {
            // 放弃 / 取消
            drawConfirmOption(dc, cx, 140, _imgDiscard, selection == 0);
            drawConfirmOption(dc, cx, 175, _imgCancel, selection == 1);
        }
    }

    //! 确认框选项: 选中项带三角指示 (纯绘制, 不依赖字体字形)
    hidden function drawConfirmOption(dc, cx, y, bitmap, selected) {
        var w = bitmap.getWidth();
        var h = bitmap.getHeight();
        var x = cx - w / 2;
        dc.drawBitmap(x, y - h / 2, bitmap);
        if (selected) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([
                [x - 16, y - 7],
                [x - 16, y + 7],
                [x - 4,  y]
            ]);
        }
    }

    //! 错误标识 → 文案位图
    hidden function errorBitmapFor(errorId) {
        switch (errorId) {
            case ForgeState.ERROR_START:   return _imgErrStart;
            case ForgeState.ERROR_STOP:    return _imgErrStop;
            case ForgeState.ERROR_SAVE:    return _imgErrSave;
            case ForgeState.ERROR_DISCARD: return _imgErrDiscard;
        }
        return null;
    }
}
