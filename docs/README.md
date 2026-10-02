# Forge — Garmin Connect IQ 项目计划书

**项目代号：** Forge  
**平台：** Garmin Connect IQ  
**首发设备：** Garmin Forerunner 255  
**应用类型：** Watch App  
**开发语言：** Monkey C  
**项目阶段：** V1.0 MVP  
**核心理念：** Manual Start. Manual Stop. Record Everything Necessary.

---

# 1. 项目背景

Forge 是一个运行于 Garmin 手表上的极简记录应用。

用户主动打开应用并开始一次 Session，Forge 负责记录本次 Session 的持续时间以及 Garmin 手表能够提供的相关运动数据；用户主动结束后，Forge 将本次 Session 保存为 FIT Activity。

FIT Activity 随 Garmin 正常同步流程进入 Garmin Connect。

Forge 不尝试判断用户正在做什么，也不进行动作识别。

第一阶段的核心问题只有一个：

> 如何以最简单、最稳定的方式，在 Garmin 手表上记录“一段由用户主动定义开始和结束的活动”。

---

# 2. 产品目标

Forge V1 的目标不是建立独立的健康数据平台，而是充分利用 Garmin 已有的设备、FIT 文件和 Garmin Connect 生态。

完整的数据链路为：

```text
Forge
  │
  │ Start
  ▼
ActivityRecording Session
  │
  │ Recording
  ▼
Garmin Sensors / Activity Data
  │
  │ Stop + Save
  ▼
FIT Activity
  │
  │ Garmin Sync
  ▼
Garmin Connect
```

Garmin Connect IQ 官方的 `ActivityRecording` API 本身就提供 Session 创建、开始、停止以及保存 FIT 文件的能力，因此 Forge 不需要自行实现运动文件系统。

---

# 3. V1 产品原则

Forge 第一版遵循四个原则。

### 3.1 Manual First

所有记录都必须由用户明确触发。

```text
用户按 START
    ↓
开始

用户按 STOP
    ↓
结束
```

V1 不尝试自动识别行为开始或结束。

### 3.2 Garmin First

Garmin 已经提供的能力尽量直接使用。

例如：

```text
FIT
Heart Rate
Activity Duration
Garmin Connect Sync
Garmin Activity History
```

不重复开发已有基础设施。

### 3.3 Watch First

V1 是一个纯 Garmin Watch App。

不存在：

```text
Android App
iOS App
Web App
Spring Boot Server
账号系统
独立数据库
```

手机 Garmin Connect 仅承担 Garmin 原有的同步角色。

### 3.4 Minimal UI

手表不是手机。

Forge 的核心交互原则：

> 打开以后，两次按钮操作完成一次记录。

```text
OPEN
 ↓
START
 ↓
RECORDING
 ↓
STOP
 ↓
SAVE
```

---

# 4. V1 功能范围

## 4.1 首页

用户进入 Forge 后展示：

```text
        FORGE


        00:00


        START
```

状态：

```text
READY
```

START / ENTER 按钮开始记录。

---

# 5. Recording 页面

开始后进入：

```text
        FORGE

        06:32

      ♥  98 bpm


        STOP
```

核心显示两个指标：

```text
Duration
Heart Rate
```

其中 Duration 是整个页面的视觉中心。

Heart Rate 为辅助信息。

---

# 6. Session 生命周期

内部状态定义：

```text
READY
  │
  │ START
  ▼
RECORDING
  │
  │ STOP
  ▼
SUMMARY
  │
  │ SAVE
  ▼
DONE
```

对应状态机：

```text
┌──────────┐
│  READY   │
└────┬─────┘
     │ START
     ▼
┌──────────┐
│RECORDING │
└────┬─────┘
     │ STOP
     ▼
┌──────────┐
│ SUMMARY  │
└────┬─────┘
     │ SAVE
     ▼
┌──────────┐
│   DONE   │
└──────────┘
```

V1 不支持 Pause。

原因是 Forge 的核心语义是：

```text
一次 Start
+
一次 Stop
=
一次 Session
```

如果以后确实出现暂停需求，再增加：

```text
PAUSED
```

状态。

---

# 7. Activity Recording 技术方案

开始 Session 时：

```text
ActivityRecording.createSession(...)
```

建议第一版：

```text
name     = "Forge"
sport    = SPORT_GENERIC
subSport = SUB_SPORT_GENERIC
```

然后执行：

```text
session.start()
```

用户结束时：

```text
session.stop()
session.save()
```

Garmin 官方说明 `ActivityRecording.Session` 管理 FIT Recording 状态机，并直接提供 `start()`、`stop()`、`save()`、`discard()` 等方法。

V1 使用：

```text
SPORT_GENERIC
SUB_SPORT_GENERIC
```

而不是伪装成：

```text
Running
Strength
Cardio
```

因为 Garmin 明确指出 Sport 类型可能影响设备针对传感器数据使用的算法，因此 Forge 第一版不应该为了 Garmin Connect 的展示效果随意声明一个不真实的运动类型。

---

# 8. Garmin Connect 中的最终表现

理想结果：

```text
Forge

Oct 2, 2026
21:32

Duration
00:08:42

Heart Rate
Avg 98 bpm
Max 121 bpm
```

具体 Garmin Connect 会展示哪些原生 Activity 字段，应以 FR255 真机产生的 FIT 文件为准。

因此 V1 开发过程中需要有一个明确验证阶段：

```text
Forge
 ↓
FR255 真机运行
 ↓
保存 FIT
 ↓
Garmin Connect 同步
 ↓
检查 Activity 页面
```

模拟器能够验证业务逻辑和 UI，但 **FIT → Garmin Connect 的最终效果必须真机验证**。

---

# 9. 心率策略

V1 UI 需要显示实时 Heart Rate。

获取路径优先使用 Garmin 当前 Activity / Sensor API 能够提供的数据。

UI 层维护：

```text
currentHeartRate
```

同时维护：

```text
heartRateSum
heartRateCount
maxHeartRate
```

可以用于结束页即时展示：

```text
Avg HR
Max HR
```

但这两个值只是 Forge UI 的临时统计。

真正进入 Garmin Connect 的 Activity 数据优先依赖 Garmin 的 FIT Recording 机制。

如果后续发现 Garmin Generic Activity 没有按照预期记录某个需要的数据，再考虑：

```text
FitContributor
```

Garmin 的 FitContributor API 可以向 FIT 文件添加 Developer Fields，并支持 Record / Lap / Session 三类消息；这些自定义字段也可以随 FIT 同步到 Garmin Connect。

因此技术优先级为：

```text
Garmin 原生字段
        ↓
满足需求
        ↓
结束


Garmin 原生字段
        ↓
不满足
        ↓
FitContributor
```

不要一开始就创建自定义 FIT 字段。

---

# 10. Summary 页面

用户 Stop 后进入 Summary：

```text
    FORGE COMPLETE


       08:42


     AVG HR
       98

     MAX HR
       121


       SAVE
```

建议同时支持：

```text
BACK → DISCARD
```

为了避免误删，Discard 需要二次确认：

```text
Discard activity?

    YES
    NO
```

Save 成功：

```text
      SAVED

      08:42
```

停留短暂时间后退出 App。

---

# 11. 意外退出处理

这是 V1 非常重要的工程问题。

需要考虑：

```text
Recording 时误按 BACK
App 被退出
手表异常
Battery Low
用户重新打开 Forge
```

其中至少需要解决「Recording 时用户主动退出」。

原则：

```text
正在 Recording
+
用户请求退出
=
不允许静默退出
```

展示：

```text
Recording in progress

Stop & Save
Discard
Cancel
```

禁止：

```text
按 BACK
↓
直接退出
↓
Session 留在未知状态
```

---

# 12. 本地存储策略

V1 **不建立完整历史数据库**。

Garmin Connect 是 Activity History 的 Source of Truth。

Application.Storage 只保存 App 自身必要状态，例如：

```text
version
settings
lastSession
```

例如：

```text
{
    "lastDuration": 522,
    "lastAvgHr": 98,
    "lastMaxHr": 121
}
```

用途仅限于改善 App 体验，而不是代替 Garmin Connect。

Connect IQ 的 `Application.Storage` 提供应用级持久化存储。

---

# 13. V1 页面结构

应用控制在四个 View：

```text
ForgeReadyView

ForgeRecordingView

ForgeSummaryView

ForgeConfirmView
```

职责：

```text
ReadyView
 └─ 等待开始

RecordingView
 └─ 实时记录

SummaryView
 └─ 本次结果

ConfirmView
 └─ Discard / Exit 等危险操作确认
```

不建立复杂导航系统。

---

# 14. 输入设计

Forerunner 255 是非触摸设备。

官方 Device Reference 显示 FR255：

```text
Screen: 260 × 260
Shape: Round
Colors: 64
Touch: No
Buttons:
- Enter
- Up
- Menu
- Down
- Esc
```


因此 Forge 必须是 Button First Design。

建议映射：

| 状态 | ENTER / START | BACK / ESC | UP / DOWN |
|---|---|---|---|
| READY | Start | Exit | 无 |
| RECORDING | Stop | Exit Confirmation | 无 |
| SUMMARY | Save | Discard Confirmation | 无 |
| CONFIRM | Confirm | Cancel | Select |

第一版甚至可以避免 Menu。

---

# 15. UI 设计原则

FR255 使用：

```text
260 × 260
64 色
Memory-In-Pixel
```

因此设计重点不是视觉特效，而是：

```text
高对比
大字体
少元素
快速读取
```

颜色建议：

```text
Background
BLACK

Primary Text
WHITE

Heart Rate
RED / LIGHT RED

Secondary
LIGHT GRAY

Success
GREEN
```

实际开发时应尽量使用 Garmin 支持的安全颜色，而不是追求手机 UI 的复杂色彩。

---

# 16. Forge Logo

V1 Logo 可以非常简单。

视觉概念：

```text
    ⚒
 FORGE
```

或者使用：

```text
Anvil
Hammer
Spark
```

作为抽象元素。

但 Logo 不是 MVP 阻塞项。

FR255 Launcher Icon 官方尺寸为：

```text
40 × 40
```


---

# 17. 工程结构

建议工程：

```text
forge/
│
├── manifest.xml
│
├── monkey.jungle
│
│
├── source/
│   ├── ForgeApp.mc
│   ├── ForgeView.mc
│   ├── ForgeDelegate.mc
│   ├── ForgeSession.mc
│   ├── ForgeState.mc
│   └── ForgeUtils.mc
│
└── resources/
    ├── layouts/
    ├── strings/
    ├── drawables/
    └── images/
```

职责如下。

### ForgeApp.mc

Connect IQ App 生命周期入口。

负责：

```text
initialize
getInitialView
onStart
onStop
```

---

### ForgeView.mc

页面绘制。

根据：

```text
ForgeState
```

绘制不同状态。

第一版甚至可以只维护一个主 View，通过状态改变画面，而不是创建很多 View。

---

### ForgeDelegate.mc

负责实体按钮输入：

```text
ENTER
BACK
UP
DOWN
```

将用户输入转换成：

```text
startSession()
stopSession()
saveSession()
discardSession()
```

---

### ForgeSession.mc

整个项目最核心的业务类。

职责：

```text
create session

start

stop

save

discard

duration

heart rate statistics
```

对 UI 隐藏 Garmin ActivityRecording 细节。

理想接口：

```text
ForgeSession.start()

ForgeSession.stop()

ForgeSession.save()

ForgeSession.discard()

ForgeSession.getDuration()

ForgeSession.getCurrentHeartRate()

ForgeSession.getAverageHeartRate()

ForgeSession.getMaxHeartRate()
```

---

### ForgeState.mc

定义：

```text
READY
RECORDING
SUMMARY
CONFIRM
```

避免 UI 到处判断 boolean。

不要出现：

```text
isStarted
isStopped
isSaving
isFinished
hasSession
```

这种最后互相组合出十几种非法状态的设计。

---

# 18. manifest 配置

应用类型：

```text
Watch App
```

首个 target：

```text
Forerunner 255
```

开发阶段不追求兼容整个 Garmin 产品线。

FR255 官方 Connect IQ Device Reference 当前标明其 Connect IQ API Level 为 5.2，并支持 Watch App；官方设备信息还给出了 Watch App 对应的设备内存限制。

因此项目第一阶段策略：

```text
只支持 FR255
       ↓
项目成熟
       ↓
255 Music
255s
265
955
965
...
```

不要一开始为几十种屏幕做适配。

---

# 19. 开发环境

开发机：

```text
Mac
```

IDE：

```text
VS Code
```

开发组件：

```text
Connect IQ SDK Manager
Monkey C Extension
Connect IQ SDK
FR255 Device Definition
```

Garmin 官方开发流程本身就是通过 SDK Manager 管理 SDK 和 Device Library，并在 VS Code 中创建 Connect IQ 项目。

---

# 20. 开发流程

整体开发顺序：

```text
Environment
    ↓
Hello World
    ↓
FR255 Simulator
    ↓
Button Input
    ↓
State Machine
    ↓
Timer
    ↓
ActivityRecording
    ↓
Heart Rate
    ↓
Summary
    ↓
FIT Save
    ↓
FR255 Real Device
    ↓
Garmin Connect
```

必须严格按照这个顺序推进。

不要第一天就研究：

```text
FIT Developer Fields
Cloud
Automatic Detection
Advanced Sensor Logging
```

---

# 21. Phase 0 — 环境初始化

目标：

```text
Mac
 ↓
VS Code
 ↓
Connect IQ SDK
 ↓
FR255 Simulator
 ↓
Hello Forge
```

验收标准：

模拟器成功出现：

```text
FORGE

START
```

---

# 22. Phase 1 — UI + 状态机

实现：

```text
READY
RECORDING
SUMMARY
CONFIRM
```

暂时不记录真实 Activity。

Duration 可以使用普通 Timer 模拟。

验收：

```text
START
 ↓
Timer running
 ↓
STOP
 ↓
Summary
```

UI 完整跑通。

---

# 23. Phase 2 — ActivityRecording

接入：

```text
Toybox.ActivityRecording
```

START：

```text
createSession()
start()
```

STOP：

```text
stop()
```

SAVE：

```text
save()
```

Discard：

```text
discard()
```

验收：

```text
Simulator / Device
能够完整创建并保存 Session
```

---

# 24. Phase 3 — Heart Rate

接入 Garmin Heart Rate 数据。

Recording 页面：

```text
♥ 98 bpm
```

Summary：

```text
AVG HR 98
MAX HR 121
```

异常值：

```text
HR == null
```

显示：

```text
-- bpm
```

不能因为传感器数据缺失导致 Session 失败。

---

# 25. Phase 4 — FR255 真机

将 Forge sideload 到 FR255。

完成一次完整测试：

```text
Open Forge
 ↓
Start
 ↓
持续 2~5 min
 ↓
Stop
 ↓
Save
```

然后退出。

验收：

Garmin 手表 Activity History 能看到对应记录。

---

# 26. Phase 5 — Garmin Connect

等待手表同步。

检查：

```text
Activity Name

Start Time

Duration

Heart Rate

Average HR

Max HR

FIT Activity Type
```

记录实际表现。

如果原生数据已经满足需求：

```text
DONE
```

如果某项无法满足：

```text
分析 FIT
 ↓
判断是否需要 FitContributor
```

---

# 27. 测试 Case

最重要测试矩阵：

| Case | 预期 |
|---|---|
| 打开 App 不开始 | 不创建 Activity |
| Start → Stop → Save | 创建 1 条 FIT |
| Start → Stop → Discard | 不创建 FIT |
| Recording 时 Back | 出现确认 |
| Summary 时 Back | 出现 Discard 确认 |
| HR 不可用 | Activity 仍正常记录 |
| Session 5 秒 | 正常保存 |
| Session 30 分钟 | 正常保存 |
| 多次连续 Session | 每次产生独立 FIT |
| 保存后重新进入 | READY |
| Garmin Connect Sync | Activity 正常出现 |

---

# 28. V1 明确不做

这一部分非常重要。

V1 不做：

```text
自动识别动作

自动判断开始 / 结束

加速度计分析

动作次数统计

频率统计

AI / ML

Android App

iOS App

Spring Boot

数据库

用户账号

Web Dashboard

云同步

社交功能

好友排行

GPS

路线

Calories 自定义算法

复杂历史页面

Connect IQ Store 上架
```

这些都不能影响 V1 发布。

---

# 29. V1.1 候选功能

V1 稳定后可以增加：

```text
Forge Count

Today
3 sessions

This Week
8 sessions
```

数据来源可以考虑：

```text
Application.Storage
```

仅做简单计数。

还可以增加：

```text
Last Forge
8:42

Today
2
```

作为首页辅助信息。

---

# 30. V1.2 候选功能

增加简单趋势：

```text
7 DAYS

M T W T F S S

1 0 2 1 0 3 1
```

统计：

```text
Session Count

Average Duration

Average Heart Rate

Longest Session
```

这时候 Forge 才开始拥有自己的历史数据层。

---

# 31. V2 候选方向：Sensor Analysis

只有 V1 真正使用一段时间后，再考虑：

```text
Accelerometer

Gyroscope

Motion Frequency

Repetition Detection
```

目标可以是：

```text
手动 Start
      ↓
传感器采样
      ↓
自动统计节奏 / 次数
      ↓
手动 Stop
```

注意：

V2 仍然不需要自动检测开始结束。

这个边界能够让传感器算法简单很多。

---

# 32. V3 候选方向：独立数据平台

如果长期数据确实有分析价值，再考虑：

```text
Garmin
  ↓
Phone
  ↓
Internet
  ↓
Forge API
  ↓
Spring Boot
  ↓
Database
  ↓
Web Dashboard
```

届时可以分析：

```text
Frequency

Duration

Time of day

Day of week

Heart Rate

Long-term trend
```

但这属于完全不同级别的项目。

在 V1 之前不考虑。

---

# 33. 技术风险

### FIT / Garmin Connect 展示行为

风险：

Generic Activity 在 Garmin Connect 中最终展示的字段和 UI 需要真机验证。

处理：

尽早完成一次真实 FIT 上传，而不是等项目全部完成后测试。

---

### Sensor Availability

风险：

Heart Rate 可能暂时：

```text
null
```

处理：

Sensor 数据永远是 Optional。

不能成为 Session 生命周期的依赖。

---

### Session State

风险：

ActivityRecording 同一时间只允许存在一个未关闭的 Session。Garmin 官方说明，如果已有 Session 尚未通过 `save()` 或 `discard()` 关闭，再次调用 `createSession()` 可能返回现有 Session。

因此 `ForgeSession` 必须统一管理 Session 生命周期。

禁止页面自己随意：

```text
createSession()
```

---

### Unexpected Exit

风险：

Recording 尚未结束时退出 App。

处理：

生命周期和 Back 行为必须专项测试。

---

# 34. 代码设计原则

Forge 的代码设计遵循：

```text
UI != Business Logic

View
 ↓
Delegate
 ↓
ForgeSession
 ↓
Garmin API
```

UI 不允许直接：

```text
ActivityRecording.createSession()
```

必须：

```text
ForgeSession.start()
```

这样以后更换实现时 UI 无需修改。

---

# 35. 成功标准

Forge V1 成功，不以代码量、功能数量或 UI 精美程度衡量。

唯一成功标准：

> 我可以戴着 FR255 打开 Forge，按一次 START，结束后按 STOP，然后在 Garmin Connect 里看到这一条完整记录。

对应验收链路：

```text
FR255
 ↓
Forge
 ↓
START
 ↓
ActivityRecording
 ↓
STOP
 ↓
FIT
 ↓
Garmin Sync
 ↓
Garmin Connect
 ↓
Forge Activity
```

链路完整即 V1 完成。

---

# 36. 最终 MVP

最终 V1 应该是一个非常小的产品：

```text
          FORGE

          START
            │
            ▼
     ┌──────────────┐
     │    08:42     │
     │              │
     │   ♥ 98 bpm   │
     │              │
     │     STOP     │
     └──────────────┘
            │
            ▼
     ┌──────────────┐
     │FORGE COMPLETE│
     │              │
     │    08:42     │
     │ Avg HR   98  │
     │ Max HR  121  │
     │              │
     │     SAVE     │
     └──────────────┘
            │
            ▼
           FIT
            │
            ▼
     Garmin Connect
```

这就是 Forge 1.0。