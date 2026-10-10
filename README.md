# RayNeo Workspace

在 M2 MacBook Air 上通过 USB-C 直连雷鸟 GT，将三个独立 macOS 桌面显示在眼镜中，转头查看，并使用原生鼠标、键盘与窗口拖拽。

用户实机验证的稳定基线是 **v0.8**（Git 标签 `v0.8`）。当前分支是 **v0.9.0 开发版**，改进停止/退出生命周期并增加应用图标，尚未完成实机验收。

## 构建开发版

```sh
bash build.sh
open build/dev/RayNeoWorkspace-Dev.app
```

需要 macOS SDK 和 Swift 编译器。产物默认为 `build/dev/`，应用身份为 `local.rayneo.workspace.dev`，与 v0.8 独立。首次使用开发版需要单独授予屏幕录制权限。可选窗口移动功能需要辅助功能权限；普通输入不需要。

默认使用临时签名。配置已有稳定签名身份时可执行：

```sh
SIGNING_IDENTITY='你的签名身份' bash build.sh
```

`BUILD_DIR` 可设置实验输出目录。签名身份尚未配置或验证；临时签名更新仍可能影响开发版权限。不要在授权和实机验证之间重新编译同一应用。

## 使用

1. GT 使用支持视频的 USB-C 线直连 Mac，本次验证环境需要断开其他实体外屏。
2. 眼镜切到“跟随模式”，应用启动后静止约两秒估计 IMU 零偏。
3. 在 Mac 控制面板点击“启动三屏”，按系统要求授权后退出重开。
4. 鼠标从 Mac 右边缘依次进入 Left / Center / Right，原生点击、输入、滚动和拖拽。
5. 使用“回中”和缩放按钮调整观看。“停止三屏”清理会话；清理完成后可再次启动。
6. 使用控制面板、菜单栏或 `⌘Q` 退出；开发版等待捕获清理结束再退出。

控制面板关闭后可通过菜单栏“GT 三屏”重开。可选 `⌘⌥1/2/3/0` 将选中窗口移至左/中/右屏或 Mac；全屏窗口需要先退出全屏。

## 验证与图标

```sh
python3 Tests/lifecycle_tests.py
bash scripts/generate-icons.sh
```

生命周期测试使用生产源码中的清理与退出方法，配合可控异步测试替身。实机验收步骤见 `docs/TESTING.md`。图标为项目原创三屏空间图形，生成源码在 `scripts/generate-icon.swift`；PNG 和 ICNS 已纳入 Git，正常构建无需重新生成。

## 基线与交接

- `HANDOFF.md`：当前状态及新对话启动指令。
- `BASELINE.md`：v0.8 回退说明。
- `docs/HANDOFF-v0.8.md`：原始完整交接，包含协议、设备约束和历史实现说明。
- `releases/v0.8/`：实际验证的应用 ZIP、源码 ZIP 与 SHA-256 清单。

三个虚拟屏为 1920×1080 / 60 Hz，捕获上限 30 fps，SceneKit 目标 60 fps。使用私有虚拟显示器接口；其他系统/设备、热拔插、睡眠唤醒、长时间漂移与性能仍需验证。应用不保存录屏、不捕获音频、不上传内容；状态文件为 `build/dev/runtime-status.json`。
