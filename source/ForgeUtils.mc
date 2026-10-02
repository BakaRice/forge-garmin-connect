using Toybox.Lang;

//! Forge 通用工具函数 (docs/README.md §17)
module ForgeUtils {

    //! 将毫秒格式化为 "MM:SS"，超过 1 小时为 "H:MM:SS"
    //! 入参单位为毫秒, 与 Activity.Info.timerTime 一致 (docs/update.md §5.2)
    function formatDuration(milliseconds) {
        var seconds = milliseconds / 1000;
        var h = seconds / 3600;
        var m = (seconds % 3600) / 60;
        var s = seconds % 60;

        if (h > 0) {
            return Lang.format("$1$:$2$:$3$", [
                h.format("%d"),
                m.format("%02d"),
                s.format("%02d")
            ]);
        }
        return Lang.format("$1$:$2$", [m.format("%02d"), s.format("%02d")]);
    }
}
