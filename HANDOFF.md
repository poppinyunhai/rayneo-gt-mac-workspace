# RayNeo Workspace 当前交接

更新：2026-10-10。目录：`/Users/shironghai/code/RayNeoWorkspace-v0.8-source`。

## 版本状态

- 稳定基线：`main` / `v0.8` / `e962868`，用户实机验证三屏与原生输入可用。
- 前一轮开发回退：`v0.9.0-dev` / `dca4124`，生命周期与图标，未实机验收。
- 当前分支：`improve/v0.10-recovery-performance`，版本 **0.10.0 开发版**。
- 当前整轮工程改进、构建和自动检查已完成；用户要求完成七项后统一验收，因此 **GT 实机验收仍待进行**。不得把本版标记为用户已验证的稳定发布。
- 原应用/源码 ZIP 和 SHA-256 清单已纳入 Git：`releases/v0.8/`。未推送远程、未发布。


验收冻结应用包：`releases/v0.10.0-dev/RayNeoWorkspace-v0.10.0-dev-app.zip`，校验清单在同目录 manifest.json，源码回退点为 `v0.10.0-dev`。验收期间使用该二进制，避免重新签名。

## 需求与不可回归约束

M2 MacBook Air + 雷鸟 GT，USB-C 直连，GT 跟随模式。三个独立 macOS 虚拟显示器必须能放真实应用窗口，通过转头查看。必须保留原生鼠标跨屏、键盘、滚动和窗口拖拽；不重新引入鼠标模式切换、黄点、事件映射或强制移动光标。

排列仍为 Mac → Left → Center → Right → GT 输出屏。三个工作屏为 1920×1080 / 60 Hz；捕获/场景帧率可配置。GT HID 只发送运行时 IMU 开/关，未刷固件、写永久校准、保存录屏、捕获音频或上传内容。

协议和历史失败原因见 `docs/HANDOFF-v0.8.md`。原工程入口已拆分，不能再寻找 WorkspaceDemo.swift；多文件入口为 `Sources/main.swift`。

## 七项整轮改进的落实

1. **统一验收准备**：自动检查完成，真实设备验收集中在 `docs/TESTING.md`，所有实机结果仍为待测。
2. **拔插/睡眠恢复**：监听 HID 匹配/移除、显示器参数变化和 NSWorkspace 睡眠/唤醒。断开时清理，设备就绪后按用户恢复意图重建；主动停止/退出优先，自动失败重试最多三次。
3. **超时与错误恢复**：枚举/捕获启动 8 秒、等待启动取消 2 秒、每路停止 3 秒上限。旧会话/迟到完成不能写新状态，错误提示可见。GT 原位置以 UUID 和坐标原子保存，正常停止、重连和下次启动可恢复，面板有恢复布局入口。
4. **稳定签名**：原有证书均过期，建立项目专用自签名本地开发证书和独立钥匙串，固定开发版 bundle ID 和叶证书要求。两次构建要求一致、严格验证和元数据篡改检测通过。TCC 更新授权行为待实机验证；没有 Developer ID、公证或公开发布。
5. **设置保存**：大小、距离、间距、轴、方向、性能模式、纹理路径、自动恢复、静止修正和测试窗口选择保存到用户数据目录；范围验证和损坏数据回退已测试。
6. **性能/清晰度工程**：Metal CVPixelBuffer 纹理直连 SceneKit，失败回退 CGImage；单帧邮箱合并待交付帧，降低积压；暂停空闲渲染、UI 4 Hz/诊断 1 Hz；15/30、30/60、60/60 模式、动态负载与 CSV 工具就绪。真实功耗/端到端延迟和阅读效果待测。
7. **姿态与工程拆分**：拆分 HID、解析/积分、捕获、布局、设置、UI、窗口移动和诊断；主入口 main.swift。校准增加方差检查、梯形积分和采样间断抑制，提供可关闭的静止缓慢零偏修正；仅以加速度辅助静止检测，没有绝对航向融合，不宣称消除长期 yaw 漂移。

## 构建、测试与数据

```sh
bash build.sh
bash Tests/run-tests.sh
bash Tests/run-texture-test.sh
open build/dev/RayNeoWorkspace-Dev.app
```

产物与身份：`build/dev/RayNeoWorkspace-Dev.app` / `local.rayneo.workspace.dev`。编译目标明确为 arm64 macOS 26.0，使用 -O。默认拒绝没有稳定身份的构建；独立临时 QA 可用 `SIGNING_IDENTITY=- BUILD_DIR=build/qa bash build.sh`。

本机专用身份名为 RayNeo Workspace Local Development。私有钥匙串、口令和本地指纹配置在 `.signing-config/`、`.signing-identity`，全部忽略，不要加入 Git。用户钥匙串搜索列表新增专用条目，默认钥匙串未改变，证书信任仅 codeSign。详见 `docs/SIGNING.md`。其他机器只克隆仓库没有私钥，需要配置自己的身份。

数据：`~/Library/Application Support/RayNeoWorkspace-Dev/` 下 settings.json、pending-layout.json、runtime-status.json。诊断不包含屏幕图像。`python3 scripts/collect-metrics.py --duration 60` 采集到项目 build 下 CSV，参考 `docs/PERFORMANCE.md`。

已执行：多文件优化编译、核心和生产清理方法测试、真实 Metal 离屏红蓝/灰阶纹理比较、控制面板离屏目视检查、签名稳定性/严格验证/篡改检测、合成诊断 CSV。未启动 GT 工作会话做本轮验收。

## 已知边界与下一步

下一步直接按 `docs/TESTING.md` 与用户统一验收，先验证原生三屏与输入，再测取消/退出/拔插/睡眠/设置，最后做性能和漂移比较。不要在用户授权与验收之间反复重编译同一应用，也不要同时运行原版和开发版。

GPU 路径虽有离屏颜色/方向检查，真实 ScreenCaptureKit / SceneKit / GT 组合仍待测，保留兼容模式。低速有意运动可能被静止修正误判，提供开关并要求慢转头比较。系统调用超时只保证本地等待有上限，不能保证系统服务立即结束。使用私有虚拟显示器接口，兼容性范围仍是原设备/系统。

## 新对话启动指令

> 请读取 HANDOFF.md、README.md、docs/TESTING.md；按需要读取 docs/ARCHITECTURE.md、docs/SIGNING.md 和 docs/PERFORMANCE.md。项目有用户验证的 v0.8 标签（e962868）及前一轮 v0.9.0-dev（dca4124），当前分支 improve/v0.10-recovery-performance 是七项整轮优化后的 0.10.0 开发版，工程检查通过但 GT 实机统一验收尚未完成。先检查 git status/log，接着按验收表与用户测试；不要把开发版当作稳定发布。入口已拆成 Sources/main.swift，默认开发产物 build/dev/RayNeoWorkspace-Dev.app，采用本机项目专用稳定签名。不要覆盖原应用、轮换签名身份、上传签名私钥或同时运行两个版本。必须保留原生鼠标跨屏、键盘和窗口拖拽，不引入鼠标模式或事件映射。设备是 M2 MacBook Air + 雷鸟 GT，跟随模式。协议/历史在 docs/HANDOFF-v0.8.md。未授权刷固件、上传内容、推送远程或发布应用。
