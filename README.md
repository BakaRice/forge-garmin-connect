# Forge — Garmin Connect IQ Watch App

极简记录应用：Manual Start. Manual Stop. Record Everything Necessary.

完整项目计划书见 [docs/README.md](docs/README.md)。
官方资料核验与修订见 [docs/update.md](docs/update.md)，修订事项优先于原计划对应章节。

## 工程结构

```
forge-garmin-connect/
├── manifest.xml                 # App 声明 (FR255 / watch-app)
├── monkey.jungle                # 构建配置
├── source/
│   ├── ForgeApp.mc              # 生命周期入口
│   ├── ForgeView.mc             # 页面绘制 (按状态绘制)
│   ├── ForgeDelegate.mc         # 按钮输入 → Session 操作
│   ├── ForgeSession.mc          # 核心业务类 (封装 ActivityRecording)
│   ├── ForgeState.mc            # 会话/界面状态定义
│   └── ForgeUtils.mc            # 工具函数
├── resources/
│   ├── strings/strings.xml
│   └── drawables/               # Launcher Icon 40×40
└── docs/README.md               # 项目计划书
```

## 构建

```bash
# 生成 developer key (首次)
monkeyc -g

# 构建 FR255
monkeyc -f monkey.jungle -o bin/forge.prg -y developer_key
```

## 模拟器

```bash
connectiq
# 选择 fr255 → 运行 bin/forge.prg
```
