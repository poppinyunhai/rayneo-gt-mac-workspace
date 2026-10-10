# RayNeo Workspace

在 M2 MacBook Air 上用 USB-C 直连雷鸟 GT，显示三个可放真实应用窗口的 macOS 桌面，转头查看，并保留原生鼠标、键盘、滚动和窗口拖拽。

用户已验证的稳定基线是 **v0.8**（标签 `v0.8`）。当前为 **v0.10.0 开发版**，整合恢复、清理、签名、设置、性能与姿态改进，工程检查已通过，等待统一 GT 实机验收。前一轮开发回退点为 `v0.9.0-dev`。

## 构建与启动

```sh
bash build.sh
open build/dev/RayNeoWorkspace-Dev.app
```

需要 Apple Silicon Mac、macOS 26.0 以上以及 macOS SDK / Swift 编译器。默认输出到 `build/dev/`，应用身份为 `local.rayneo.workspace.dev`，不会覆盖原 v0.8 应用。当前工具链目标与最低系统版本已显式设定；仍仅在原验证设备/系统上进行后续验收。

本机已经配置项目专用本地开发证书。其他机器需要配置签名，详见 `docs/SIGNING.md`。构建不会悄悄回退到临时签名；临时检查构建可明确使用 `SIGNING_IDENTITY=- BUILD_DIR=build/qa bash build.sh`。

首次运行稳定签名的开发版，需要单独授予屏幕录制权限；可选窗口移动需要辅助功能权限。普通跨屏输入不需要辅助功能授权。不要在授权后重新切换签名身份。


验收冻结应用包：`releases/v0.10.0-dev/RayNeoWorkspace-v0.10.0-dev-app.zip`，校验清单在同目录 manifest.json，源码回退点为 `v0.10.0-dev`。验收期间使用该二进制，避免重新签名。

## 使用与设置

1. 退出原 v0.8；GT 用支持视频的 USB-C 线直连 Mac，并使用“跟随模式”。原环境需要断开占用输出能力的其他实体外屏。
2. 可先打开应用调整设置，未连接眼镜时控制面板仍可使用。
3. 点击“启动三屏”，按系统要求授权、退出重开，再启动。静止约两秒完成初始零偏估计。
4. 鼠标从 Mac 右边缘依次进入 Left / Center / Right，正常输入和拖拽。可选 `⌘⌥1/2/3/0` 把选中窗口移动到左/中/右屏或 Mac。
5. “回中”调整朝向，“重新校准”重新估计零偏。屏幕大小、观看距离（场景单位）、间距、转头轴和方向会保存。
6. 性能模式提供捕获/渲染 15/30、30/60、60/60 fps；Metal 纹理和 Core Image 兼容模式可切换，下次启动三屏生效。GPU 纹理创建失败时自动使用兼容路径。
7. 开启自动恢复时，断开和睡眠会清理会话，重连/唤醒后恢复之前用户启动的会话。主动点击停止会取消恢复意图。启动失败最多自动尝试三次，之后需要点击启动重试。
8. “恢复布局”重试恢复 GT 原位置；“性能测试”在三屏显示可重复动态内容，再次点击停止动态内容；“打开诊断文件夹”访问本地设置和状态。
9. 用控制面板、菜单栏或 `⌘Q` 退出，应用等待有限时清理后退出。正常清理先停捕获，再恢复布局和释放虚拟屏；超时会提示并执行本地释放。

控制面板关闭后可通过菜单栏“GT 三屏”重开。原场景按键仍依赖输出窗口焦点，不能当作全局操作。

## 本地数据与测量

数据目录：`~/Library/Application Support/RayNeoWorkspace-Dev/`。

- `settings.json`：用户设置。
- `pending-layout.json`：待恢复的 GT 原位置；成功恢复后删除，可在异常退出后恢复原布局。
- `runtime-status.json`：每秒更新的会话、捕获、IMU、CPU 和内存诊断，不含屏幕图像。

采集 60 秒诊断 CSV：

```sh
python3 scripts/collect-metrics.py --duration 60
```

CSV 默认保存到项目 `build/`。动态场景、不同纹理路径和性能模式的比较方法见 `docs/PERFORMANCE.md`；帧交付时间不等于输入到眼镜显示的端到端延迟。

## 验证与文档

```sh
bash Tests/run-tests.sh
bash Tests/run-texture-test.sh
```

第一项测试设置、恢复策略、帧合并、IMU 与生命周期；第二项使用真实 Metal 设备做合成图像离屏测试，不连接 GT、不捕获桌面。受限执行沙箱可能无法访问 Metal 或钥匙串，应区分环境限制与产品错误。

- `HANDOFF.md`：新对话入口与当前工作状态。
- `docs/TESTING.md`：整轮验收清单。
- `docs/ARCHITECTURE.md`：工程结构和关键设计。
- `docs/SIGNING.md`：本地稳定签名。
- `docs/PERFORMANCE.md`：性能与漂移测量。
- `BASELINE.md`、`docs/HANDOFF-v0.8.md`：原基线、回退和协议历史。

图标资源位于 `Assets/`，可用 `bash scripts/generate-icons.sh` 重新生成。

仍使用私有 CGVirtualDisplay 接口。姿态以 yaw 为主，静止零偏修正不能提供绝对航向，也不能保证消除长时间漂移。超时兜底不能保证已卡住的系统服务立即停止，强制退出也不执行正常清理。应用不刷固件、不写永久设备配置、不保存录屏、不捕获音频、不上传内容。
