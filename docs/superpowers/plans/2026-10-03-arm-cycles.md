# Forge Arm Cycles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 完成用户确认的完整往返计次、频率、统计页面和 FIT 汇总保存，提供可统一真机验收的安装包。

**Architecture:** ForgeMotionDetector 是接受样本和时间的纯计算类；ForgeMotion 管理传感器监听及有界统计。ForgeSession 编排生命周期及 FIT 字段，ForgeApp / Delegate / View 只管理页面与显示。

**Tech Stack:** Monkey C、Connect IQ SDK 9.2.0、FR255、Run No Evil、Swift 中文位图标签。

---

### Task 1: 检测算法与真实模块测试

Files: `source/ForgeMotionDetector.mc`, `tests/ForgeMotionTests.mc.test`, `tools/run-motion-tests.py`。

- [x] 定义 `addSample(gx, gy, gz, deltaMs)`、`reset()`、`getCount()`、`getCadence()`、`getPhase()`；角速度单位 deg/s，时间为单调递增的样本间隔。
- [x] 先编写并运行静止、半程、完整往返、连续、反向佩戴、抖动、采样缺口、重置和频率场景；缺失算法时测试失败。
- [x] 实现方向投影、角度积分、去程/回程/结束状态和有界最近完成时间；丢失或非法间隔清除未完成候选，保留已完成次数。
- [x] 在 FR255 Run No Evil 中运行真实模块测试，要求所有断言通过且 errors=0。

Task 2 与 Task 3 共享会话和页面接口，由同一实现任务顺序完成，再一起检查范围和代码质量。

### Task 2: 采样与会话集成

Files: `source/ForgeMotion.mc`, `source/ForgeSession.mc`, `manifest.xml`, `resources/fitfields.xml`, `resources/strings/strings.xml`。

- [x] 注册最多 50Hz 同步加速度与角速度监听；检查实际速率与数据缺失，运行时支持时间戳才使用该属性，否则使用批次和名义采样间隔。
- [x] 成功开始录制后启动监听，成功停止/丢弃后取消监听；失败返回与重试保留原生会话语义；新的活动重置动作统计。
- [x] 添加 FitContributor 权限和 SESSION Developer Fields，ID 0 往返次数、ID 1 平均次/分钟；持续更新已取得的有效统计，停止前更新最后值。
- [x] 对采样、字段创建、字段写入、监听取消的失败提供有界调试状态；原生录制与保存继续可用。
- [x] 用可控传感器和录制替身验证生命周期、批次处理、缺失采样、字段数据及失败路径。

### Task 3: 页面与中文资源

Files: `source/ForgeApp.mc`, `source/ForgeDelegate.mc`, `source/ForgeView.mc`, `tools/render_labels.swift`, `resources/drawables/*`。

- [x] RECORDING / SUMMARY 下 UP/DOWN 切换时长心率页与动作页；保留现有 START/STOP/SAVE/BACK 和 CONFIRM 行为。
- [x] 动作页显示次数和次/分钟；录制时显示最近频率，停止后显示固定平均频率；没有有效采样时显示缺失。
- [x] 生成次数、频率与传感器状态中文标签；为顶端调试区和所有正文保留独立空间，避免重叠与圆屏裁切。
- [x] 更新启动版本标记，在模拟器检查正常、缺失、确认、汇总和保存页面。

### Task 4: 最终验证与交付

Files: `docs/TODO.md`, `docs/motion-detection.md`, `bin/forge.prg`。

- [x] 运行检测、集成和现有六项防抖回归；测试报告必须明确 completed verdict，不能仅依赖 monkeydo 的退出码。
- [x] 完成代码及范围检查，修复有证据的问题；只在修改影响相关行为时重跑检查。
- [x] 根据保存的文件哈希确认原项目没有被其他操作改动，再写回变更；清空 bin，重新构建 FR255。
- [x] 更新 TODO，明确实现与模拟器验证已完成，真实识别准确率、最终布局与 Garmin Connect 展示待统一真机验收。
