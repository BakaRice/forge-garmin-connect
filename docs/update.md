# Forge V1 计划核验与更新

更新日期：2026-10-02  
对应计划：[Forge — Garmin Connect IQ 项目计划书](README.md)  
文档状态：官方资料核验完成；尚未进行编译、模拟器或 FR255 真机验证。

## 1. 更新结论与适用范围

Forge V1 的核心路线可行：用户手动开始和停止，应用通过 Garmin ActivityRecording 保存 FIT，再由 Garmin 正常同步进入 Garmin Connect。

本文件补充和修订原计划中的工程细节。实施时，本文明确修订的事项优先于原计划对应章节；未涉及的产品目标和 V1 范围保持原计划定义。本文中的实现选择属于项目建议与约定，不代表 Garmin 对真机行为的保证。

V1 继续限定为 FR255 上的独立 Watch App，不增加手机应用、服务器、独立历史数据库、动作识别、暂停或 GPS 功能。

最高优先级为：

1. 正确启用心率传感器，并验证原生 FIT 心率记录。
2. 正确处理 Session 开始、停止、保存和丢弃的失败结果。
3. 提前验证 FR255 → FIT → Garmin Connect 完整链路。

## 2. 已核验的基础事实

| 项目 | 核验结论 | 来源 |
| --- | --- | --- |
| FR255 显示与输入 | 圆屏、260 × 260、64 色、无触摸；输入标识包含 enter、up、menu、down、esc | [1] |
| 启动图标 | 40 × 40 | [1] |
| Watch App 内存上限 | 524,288 字节，即 512 KiB；不应视为全部可供业务分配的空间 | [1] |
| FR255 API Level | 当前官方兼容列表标注为 5.2；应用最低 API 版本应根据实际调用的 API 和目标设备固件确定 | [2] |
| 活动生命周期 | ActivityRecording 提供创建 Session，Session 提供 start、stop、save、discard | [3][4] |
| 未关闭 Session | 已有 Session 尚未通过 save 或 discard 关闭时，createSession 会返回已有对象 | [3] |
| FIT 同步 | 官方记录指南描述了 FIT 通过 Garmin 同步进入 Garmin Connect 的流程 | [5] |
| 少量本地状态 | Application.Storage 可用于应用级持久化数据 | [8] |

设备资料和 API 文档确认的是能力与接口，不等于已经验证 Generic Activity 在当前 FR255 固件上的全部行为。

## 3. 产品交互与状态修订

对应原计划第 3、6、10、11、13、17、35 节。

### 3.1 正常流程明确为三次操作

保留显式保存，正常流程为：

```text
READY → START → RECORDING → STOP → SUMMARY → SAVE → SAVED → EXIT
```

将“两次按钮操作完成一次记录”修订为“三次按钮操作完成开始、停止和保存”。STOP 只停止记录并进入汇总，不自动保存。

保存成功后短暂展示 SAVED，再退出应用。用户重新打开应用时进入 READY。

### 3.2 分开表达会话状态与界面状态

会话状态建议采用：

| 状态 | 含义 |
| --- | --- |
| IDLE | 没有待处理会话 |
| PREPARED | 已创建 Session，但尚未成功开始；包括开始失败后等待清理的情况 |
| RECORDING | 已成功开始，正在记录 |
| STOPPED | 已停止，尚未成功保存或丢弃 |
| CLOSED | 已成功保存或丢弃 |

界面状态采用 READY、RECORDING、SUMMARY、CONFIRM、SAVED。界面可附带错误信息，但错误提示不能覆盖真实会话状态。

CONFIRM 只表示正在等待用户选择，不表示会话停止。确认框必须保留进入来源和待确认动作：

- Recording 中按 Back：保持记录，展示 Stop & Save、Discard、Cancel。
- 选择 Cancel：返回 Recording，计时与心率统计持续进行。
- 选择 Stop & Save：停止成功后再保存；失败时保留会话并提示。
- 选择 Discard：进入明确的丢弃确认；只有用户确认且丢弃成功后才退出。
- Summary 中按 Back：展示丢弃确认；取消后返回 Summary，会话保持停止。

确认框默认选择 Cancel 或 No。操作执行期间避免重复处理连续按键；上一会话未成功关闭时，不允许开始下一会话。

### 3.3 V1 页面组织

采用一个主 View 根据界面状态绘制 READY、RECORDING、SUMMARY、SAVED，另设确认界面处理退出和丢弃。原计划“四个 View”不再作为强制要求。

View 负责展示，Delegate 负责输入，ForgeSession 统一管理会话、数据快照及 Garmin API 调用。

## 4. Session 生命周期与失败处理

对应原计划第 7、10、17、23、33 节。

官方 start、stop、save、discard 均返回 Boolean，不能仅根据“方法已调用”判断成功。[4]

| 操作 | 成功后 | 失败后 |
| --- | --- | --- |
| 创建 | 持有唯一 Session，进入 PREPARED | 展示错误，不进入 Recording |
| 开始 | 进入 RECORDING | 保留引用并核对记录状态；执行受控清理，不创建第二个 Session |
| 停止 | 固定本次汇总数据，进入 STOPPED / SUMMARY | 保留引用，核对实际记录状态，提示重试，不宣称已经停止 |
| 保存 | 进入 CLOSED，释放引用和采集资源，显示 SAVED | 保持待处理会话，提示保存失败，允许重试或明确丢弃 |
| 丢弃 | 进入 CLOSED，释放引用和采集资源，退出 | 保留引用，提示失败，不能直接退出或显示丢弃成功 |

实现时还需处理创建选项无效等异常。isRecording() 只用于判断是否正在记录，不能单独用于判断 Session 是否已经保存、丢弃或关闭。

保存失败不得清空 Session 引用，不得自动丢弃，不得自动开始下一条记录。必要本地状态写入失败也不应改变已确认的 FIT 保存结果。

运动常量使用：

```text
Activity.SPORT_GENERIC
Activity.SUB_SPORT_GENERIC
```

ActivityRecording 命名空间中的旧运动枚举已被标记弃用，新增代码不使用旧枚举。[3]

## 5. 权限、心率与计时

对应原计划第 9、18、24 节。

### 5.1 明确权限和传感器启用

- 使用 ActivityRecording 时声明 Fit 权限。[3]
- 使用 Toybox.Sensor 时声明 Sensor 权限。[6]
- 按官方流程启用需要记录的传感器，再创建并开始 Session。[5]
- 明确心率来源策略：使用系统可用心率来源，或限定腕式心率；FR255 真机上验证选定策略。
- 结束并关闭会话后，解除本应用注册的监听并释放启用的传感器资源。

仅创建 Generic Session 不能作为“心率已经采集并写入 FIT”的验证依据。UI 有心率、FIT 有心率、Connect 能展示心率应分别检查。

### 5.2 原生活动数据优先

优先通过 Activity.getActivityInfo() 读取 Activity.Info 中的字段：[7]

| 内容 | 字段 | 处理要求 |
| --- | --- | --- |
| 当前心率 | currentHeartRate | null 时显示 -- bpm |
| 平均心率 | averageHeartRate | 原生值可用时优先使用 |
| 最大心率 | maxHeartRate | 原生值可用时优先使用 |
| 记录时长 | timerTime | 单位为毫秒；处理 null |

实际可用性和停止后的读取时机必须在模拟器及真机确认。保存前固定本次汇总快照，避免保存后 Session 关闭导致界面丢失数据。

若需要自行统计心率作为备用：

- 只在记录期间处理有效采样，不按 UI 重绘次数累计。
- 缺失数据不按零值参与平均值；没有有效样本时显示 --。
- 明确采样周期与缺失处理；Sensor.enableSensorEvents 文档描述的回调频率为 1 Hz。[6]
- 将结果视为应用采样统计，不承诺与 Garmin Connect 的平均值完全一致。

### 5.3 Timer 只驱动界面刷新

正式记录优先使用 Garmin 活动计时。若需要备用计时，使用明确的经过时间来源，并验证其与 FIT 时长的差异；不采用“每收到一次回调就加一秒”的累计方式。

进入退出确认框期间继续计时；STOP 成功后固定时长，Summary 停留和保存重试时间不计入本次记录时长。

## 6. FIT、Connect 展示与 FitContributor 边界

对应原计划第 8、9、26、28、33 节。

V1 以原生 FIT 字段为基础，真机核验以下内容：

- 活动能否保存并正常同步。
- 开始时间和时长是否符合记录过程。
- 有有效心率采样时，FIT 是否包含心率及相应统计，Connect 如何展示。
- Generic 活动最终显示为何种类型和名称。

name = "Forge" 是传给记录接口的名称，不作为 Connect 最终标题必定为 Forge 的承诺。活动名称和类型需要记录实际结果。[3]

FitContributor 支持 Developer Fields，但“写入 FIT”“随 FIT 同步”和“在 Connect 页面展示”是不同环节。官方指南要求配置展示元数据，并提供 Monkey Graph 预览。[5][10]

Garmin 旧版官方指南明确提到，自定义字段展示需要应用获批并发布。[11] 由于该资料较旧，不能将其直接视为对所有当前分发方式的完整说明；但在完成当前流程验证前，也不能承诺侧载应用的自定义字段可直接展示。

因此，FitContributor 不作为 V1 的无条件兜底：若原生字段无法满足核心需求，应先分析真机 FIT、确认当前展示与分发限制，再决定是否调整 V1 范围。“V1 不上架”的边界继续保留。

## 7. 正常退出与异常中断

对应原计划第 11、33 节。

应用可以处理的 Back 退出必须经过明确交互，不能留下未关闭 Session 后静默退出。

AppBase.onStop() 用于终止前清理，官方文档没有保证断电、崩溃等情况下必然执行。[9] 因此：

- 不把 onStop() 当作必定能够保存活动的兜底。
- 不在 onStop() 中设计需要等待用户操作的确认流程。
- 对正常终止做防御性资源清理；未关闭会话的处理方式需单独实现和验证。
- 强制关机、崩溃、重启后的记录恢复属于待真机验证能力，V1 暂不承诺完整恢复。
- 本地保存的 lastSession 只用于体验或诊断，不等于恢复了 Garmin 原生 Session 或 FIT。

## 8. 修订后的开发顺序

替代原计划第 20～26 节的严格串行顺序。

| 阶段 | 工作 | 验收 |
| --- | --- | --- |
| A：环境与最小应用 | SDK、设备定义、构建配置及开发签名配置；显示 FORGE / START | 能为 fr255 编译并在模拟器运行；记录使用的 SDK 与设备定义版本 |
| B：最小记录闭环 | Fit / Sensor 权限、心率启用、开始、停止、保存和丢弃；基本失败处理 | 最小 UI 可以完成会话生命周期，未关闭会话不会重复创建 |
| C：提前真机验证 | FR255 记录 2～5 分钟，保存 FIT 并同步 Connect | 检查时长、心率、名称、类型；保留实际证据和设备固件版本 |
| D：完整交互 | 汇总、退出确认、错误提示、统计缺失处理、按键重复输入防护 | 所有正常与可控异常流程可测试 |
| E：回归与验收 | 模拟器检查、真机长短记录、连续记录、同步验证 | 测试矩阵通过；未验证限制明确记录 |

阶段 C 应在完整界面打磨之前完成。若核心原生字段不满足需求，先解决或重新评估，再进入后续完善阶段。

## 9. 补充测试矩阵

保留原计划第 27 节测试，并增加或细化以下用例：

| 场景 | 预期 |
| --- | --- |
| start 返回失败 | 不显示正在记录；会话受控保留或清理，不创建第二条 |
| stop 返回失败 | 不宣称已经停止；记录状态与提示一致，可重试 |
| save 返回失败 | 不显示 SAVED，不退出、不清空引用、不自动丢弃 |
| discard 返回失败 | 不宣称已丢弃，不开始新会话 |
| 快速连续按 START / STOP / SAVE | 不重复创建或重复处理同一操作；有效活动不重复 |
| Recording 中打开确认框并等待后取消 | 持续记录；返回后时长包含确认期间 |
| Summary 中打开确认框后取消 | 保持停止；汇总不继续增长 |
| Summary 停留后保存 | 停留时间不计入记录计时 |
| 全程无心率 | 活动仍可保存；当前、平均和最大心率显示缺失，而非伪造零值 |
| 心率中途缺失后恢复 | 不崩溃；缺失不按零累计；检查 UI 与 FIT 表现 |
| 丢弃后重新打开并开始 | 新会话独立；上一会话不被错误复用 |
| 保存后重新打开并开始 | READY 状态；每次成功记录产生独立活动 |
| 5 秒记录 | 验证本地保存结果，并单独记录 Connect 是否接受和展示 |
| 30 分钟记录 | 无明显累计计时误差；心率与记录稳定 |
| 蓝牙断开时保存，恢复连接后同步 | 本地保存结果不依赖立即同步；恢复后核对 Connect |
| 强制中断与重新打开 | 记录实测结果和恢复限制；不把未验证恢复能力写成保证 |

失败返回路径可通过记录接口的可控替身进行逻辑测试；硬件记录、FIT 内容和同步效果必须通过真机验证。

丢弃的用户验收定义为“不保留或同步已保存活动”，不要求证明设备在记录过程中从未生成临时文件。

## 10. V1 完成标准

V1 完成需要同时满足：

1. 用户可在 FR255 手动 START、STOP、SAVE，并在 Connect 中找到对应活动。
2. 正常有心率的测试记录，其原生心率数据满足约定展示需求；无心率时仍能保存活动。
3. 保存成功与失败在界面上明确区分，失败不会被误报成功。
4. 正常退出和丢弃不会留下失控的会话，连续记录彼此独立。
5. 真机验收记录包含固件版本、SDK 版本、测试步骤、FIT 检查结果及 Connect 展示结果。

当前仍待验证：FR255 当前固件下 Generic Activity 的原生心率字段、最终活动名称与类型、短活动同步表现，以及异常中断后的恢复行为。

## 11. 官方参考资料

以下资料于 2026-10-02 核验；官方内容可能继续更新。

1. [FR255 Device Reference](https://developer.garmin.com/connect-iq/articles/device-reference/fr255.html)
2. [Compatible Devices](https://developer.garmin.com/connect-iq/compatible-devices/)
3. [Toybox.ActivityRecording](https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityRecording.html)
4. [ActivityRecording.Session](https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityRecording/Session.html)
5. [Activity Recording 官方指南](https://developer.garmin.com/connect-iq/articles/core-topics/Activity_Recording.html)
6. [Toybox.Sensor](https://developer.garmin.com/connect-iq/api-docs/Toybox/Sensor.html)
7. [Activity.Info](https://developer.garmin.com/connect-iq/api-docs/Toybox/Activity/Info.html)
8. [Application.Storage](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html)
9. [Application.AppBase](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AppBase.html)
10. [Toybox.FitContributor](https://developer.garmin.com/connect-iq/api-docs/Toybox/FitContributor.html)
11. [Wearable Programming for the Active Lifestyle，旧版官方指南](https://developer.garmin.com/downloads/connect-iq/wearable-programming-for-the-active-lifestyle.pdf)
