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
    hidden var _imgCycles = null;
    hidden var _imgCurrentCadence = null;
    hidden var _imgAverageCadence = null;
    hidden var _imgMotionWaiting = null;
    hidden var _imgMotionActive = null;
    hidden var _imgMotionStale = null;
    hidden var _imgMotionUnsupported = null;
    hidden var _imgMotionError = null;


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
        _imgCycles = WatchUi.loadResource(Rez.Drawables.LabelCycles);
        _imgCurrentCadence = WatchUi.loadResource(Rez.Drawables.LabelCurrentCadence);
        _imgAverageCadence = WatchUi.loadResource(Rez.Drawables.LabelAverageCadence);
        _imgMotionWaiting = WatchUi.loadResource(Rez.Drawables.LabelMotionWaiting);
        _imgMotionActive = WatchUi.loadResource(Rez.Drawables.LabelMotionActive);
        _imgMotionStale = WatchUi.loadResource(Rez.Drawables.LabelMotionStale);
        _imgMotionUnsupported = WatchUi.loadResource(Rez.Drawables.LabelMotionUnsupported);
        _imgMotionError = WatchUi.loadResource(Rez.Drawables.LabelMotionError);

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
                if (app.getMetricsPage() == 1) { drawMotion(dc, cx, false); }
                else { drawRecording(dc, cx); }
                break;
            case ForgeState.UI_SUMMARY:
                if (app.getMetricsPage() == 1) { drawMotion(dc, cx, true); }
                else { drawSummary(dc, cx); }
                break;
            case ForgeState.UI_SAVED:
                drawSaved(dc, cx);
                break;
            case ForgeState.UI_CONFIRM:
                drawConfirm(dc, cx);
                break;
        }

        if (app.getUiState() == ForgeState.UI_RECORDING || app.getUiState() == ForgeState.UI_SUMMARY) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(234, 129, Graphics.FONT_XTINY, (app.getMetricsPage() + 1).format("%d") + "/2",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // 保留完整的个人调试信息；FR255 的 XTINY 行高为 24px。
        // 两行独占顶部区域，正文从 y=73 开始，避免覆盖标题。
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 18, Graphics.FONT_XTINY, app.getDbgLine(),
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, 46, Graphics.FONT_XTINY, app.getDbgStage() + " " + app.getSession().getMotionAccelDebug(),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! 居中绘制文案位图
    hidden function drawLabelCenter(dc, cx, y, bitmap) {
        dc.drawBitmap(cx - bitmap.getWidth() / 2, y - bitmap.getHeight() / 2, bitmap);
    }

    //! 绘制 FORGE 标题 (品牌名保持拉丁字母)
    hidden function drawTitle(dc, cx) {
        var errImg = errorBitmapFor((Application.getApp() as ForgeApp).getErrorId());
        if (errImg != null) {
            // 错误占用标题位置，避免挤压计时、心率和操作文案。
            drawLabelCenter(dc, cx, 90, errImg);
            return;
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 90, Graphics.FONT_TINY, "FORGE",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! READY 页面 (docs/README.md §4.1)
    //!     FORGE
    //!     00:00
    //!     开始
    hidden function drawReady(dc, cx) {
        drawTitle(dc, cx);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 149, Graphics.FONT_NUMBER_HOT,
            ForgeUtils.formatDuration(0),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        drawLabelCenter(dc, cx, 214, _imgStart);
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
        dc.drawText(cx, 140, Graphics.FONT_NUMBER_MEDIUM,
            ForgeUtils.formatDuration(session.getDuration()),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // 心率 — null 时显示 -- bpm (docs/README.md §24)
        var hr = session.getCurrentHeartRate();
        var hrText = (hr != null) ? hr.format("%d") + " bpm" : "-- bpm";
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 189, Graphics.FONT_TINY, hrText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        drawLabelCenter(dc, cx, 226, _imgStop);
    }

    //! SUMMARY 页面 (docs/README.md §10)
    //!     完成
    //!      08:42
    //!   平均心率 98
    //!   最大心率 121
    //!      保存
    hidden function drawSummary(dc, cx) {
        var session = (Application.getApp() as ForgeApp).getSession();

        var errImg = errorBitmapFor((Application.getApp() as ForgeApp).getErrorId());
        drawLabelCenter(dc, cx, 90, (errImg != null) ? errImg : _imgDone);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 136, Graphics.FONT_NUMBER_MILD,
            ForgeUtils.formatDuration(session.getDuration()),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var avg = session.getAverageHeartRate();
        var max = session.getMaxHeartRate();
        drawStatLine(dc, cx, 177, _imgAvgHr,
            (avg != null) ? avg.format("%d") : "--");
        drawStatLine(dc, cx, 207, _imgMaxHr,
            (max != null) ? max.format("%d") : "--");

        drawLabelCenter(dc, cx, 241, _imgSave);
    }

    //! Motion page uses completed outward-return cycles and nullable frequency.
    hidden function drawMotion(dc, cx, summary) {
        var app = Application.getApp() as ForgeApp;
        var session = app.getSession();
        var errImg = errorBitmapFor(app.getErrorId());
        var heading = summary ? _imgDone : motionStatusBitmap(session.getMotionStatus());
        drawLabelCenter(dc, cx, 90, errImg != null ? errImg : heading);
        drawLabelCenter(dc, cx, 120, _imgCycles);
        var count = session.getMotionCount();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 162, Graphics.FONT_NUMBER_MEDIUM, count != null ? count.format("%d") : "--",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        var cadence = summary ? session.getAverageMotionCadence() : session.getCurrentMotionCadence();
        drawStatLine(dc, cx, 207, summary ? _imgAverageCadence : _imgCurrentCadence,
            cadence != null ? cadence.format("%.1f") + "/min" : "--/min");
        drawLabelCenter(dc, cx, 241, summary ? _imgSave : _imgStop);
    }

    hidden function motionStatusBitmap(status) {
        if (status.equals("active")) { return _imgMotionActive; }
        if (status.equals("stale")) { return _imgMotionStale; }
        if (status.equals("unsupported")) { return _imgMotionUnsupported; }
        if (status.equals("error")) { return _imgMotionError; }
        return _imgMotionWaiting;
    }

    //! 统计行: [中文标签] + 数值 (默认字体)
    hidden function drawStatLine(dc, cx, y, labelImg, valueText) {
        var gap = 8;
        var labelW = labelImg.getWidth();
        var labelH = labelImg.getHeight();
        var valueW = dc.getTextWidthInPixels(valueText, Graphics.FONT_XTINY);
        var total = labelW + gap + valueW;
        var x = cx - total / 2;

        dc.drawBitmap(x, y - labelH / 2, labelImg);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + labelW + gap, y, Graphics.FONT_XTINY, valueText,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! SAVED 页面 (docs/README.md §10: 短暂展示后退出)
    hidden function drawSaved(dc, cx) {
        var session = (Application.getApp() as ForgeApp).getSession();

        drawLabelCenter(dc, cx, 112, _imgSaved);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 173, Graphics.FONT_NUMBER_MEDIUM,
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
        drawLabelCenter(dc, cx, 95,
            (action == ForgeState.CONFIRM_EXIT) ? _imgRecording : _imgDiscardAsk);

        if (action == ForgeState.CONFIRM_EXIT) {
            // 停止并保存 / 放弃 / 取消
            drawConfirmOption(dc, cx, 141, _imgStopSave, selection == 0);
            drawConfirmOption(dc, cx, 179, _imgDiscard, selection == 1);
            drawConfirmOption(dc, cx, 217, _imgCancel, selection == 2);
        } else {
            // 放弃 / 取消
            drawConfirmOption(dc, cx, 152, _imgDiscard, selection == 0);
            drawConfirmOption(dc, cx, 193, _imgCancel, selection == 1);
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
