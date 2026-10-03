# START 被负数系统计时器拦截

2026-10-03，Forerunner 255 真机。

## 根因与证据

真机英文对照包照片显示 `S2 B0 U0 D0 st0`、`EN DB -1202805866`、`M 13/507K`。
START 已触发两次，停在录制会话创建之前的防抖分支。

原实现初始化 `_lastActionAt = 0`，用 `now - _lastActionAt < 500` 判断快速重复。
当系统计时器为负数时，这个判断总成立，并且不会更新 `_lastActionAt`，因此后续按键也一直被拒绝。

Garmin 文档说明 System.getTimer() 会周期回绕：通常开机约 25 天第一次，之后每约 50 天一次；其起点不保证总为零。
[官方说明](https://developer.garmin.com/connect-iq/api-docs/Toybox/System.html#getTimer-instance_function)

## 修复

- 无上次操作用 null 表示；首次操作直接允许，不假设系统计时器是正数。
- 后续只拦截 `0 <= elapsed < 500` 的重复操作。
- 短时间跨越正负数边界，Monkey C Number 的减法回绕仍得到正确的短间隔。
- 长间隔导致负差值时允许操作，不永久锁住 START/STOP/SAVE。

## 验证

回归测试使用真实 ForgeApp.debounced() 的源码，只在临时构建中替换时间输入并开放该方法访问，不在生产类中增加测试接口，不复制计算逻辑。

| 场景 | 修复前 | 修复后 |
| --- | --- | --- |
| 首次操作使用真机照片负数 | FAIL | PASS |
| 首次操作计时器为 0 | FAIL | PASS |
| 正数 499ms 拦截、500ms 允许 | PASS | PASS |
| 负数起点、快速重复及 500ms 后操作 | FAIL | PASS |
| 有符号边界回绕、短间隔防抖 | PASS | PASS |
| 长间隔负差值不阻止操作 | FAIL | PASS |

完整应用还在模拟器中使用从照片负数开始递增的计时输入回放；按 START 后原生 Session.start() 返回 true，进入 RECORDING。

SDK 9.2.0 的 monkeydo 测试命令即便报告全部通过也返回 1；测试运行器保留此退出码输出，要求显式 `PASSED (passed=6, failed=0, errors=0)` 完整报告才返回成功。

## 真机最后验证

安装新的 bin/forge.prg，启动标记为 FIX1003 READY。短按 START，确认出现停止按钮、时长递增；正常结束后保存或明确丢弃。
保留阶段提示至真机确认，再移除临时诊断计数与详细日志。
