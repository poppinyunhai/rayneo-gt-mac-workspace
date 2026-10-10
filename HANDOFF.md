# RayNeo Workspace 当前交接

更新：2026-10-10。工作目录：`/Users/shironghai/code/RayNeoWorkspace-v0.8-source`。

## 版本与保护

- 已创建独立本地 Git 仓库。
- `main` / 标签 `v0.8` / 提交 `e962868` 是用户验证可用的原始基线。
- 当前开发分支：`improve/v0.9-lifecycle-icon`；版本 `0.9.0`，未实机验收，不是稳定发布。
- 原版应用 ZIP、源码 ZIP 和校验清单位于 `releases/v0.8/`，全部纳入 Git，校验通过。
- 未配置远程，未推送或发布。回退说明见 `BASELINE.md`。
- 原完整交接已保存在 `docs/HANDOFF-v0.8.md`，先读当前交接，再按需读原文的协议与历史。

## 产品不可回归约束

设备是 M2 MacBook Air 和雷鸟 GT。用户要三个能放真实应用窗口的 macOS 桌面，通过转头查看。必须保留原生鼠标跨屏、键盘、滚动与拖拽，不能重新引入鼠标模式切换、黄点、鼠标事件映射或强制移动光标。

GT 使用跟随模式；屏幕排列为 Mac → Left → Center → Right → GT 输出屏。当前仅发送运行时 IMU 开关，不刷固件、不写永久配置、不保存录屏、不上传内容。

## 本轮实现

`Sources/WorkspaceDemo.swift`：

1. 保存启动任务；停止时递增 generation，取消启动并等待其结束，避免 stopCapture 与尚未完成的 startCapture 交错。
2. 同一时刻只运行一次停止任务，停止和退出期间拒绝新启动。
3. 停止按顺序执行：屏蔽旧回调 → 等待启动 → 停止全部捕获 → 恢复 GT 位置 → 关闭测试窗口 → 释放虚拟屏 → 清空纹理。
4. 每次异步捕获启动后检查会话有效性。捕获错误回调带 generation 校验，当前会话的错误会触发完整清理；旧会话不能覆盖新状态。
5. `applicationShouldTerminate` 返回 terminateLater，等待清理、关闭 IMU、停止计时器后回复系统。`applicationWillTerminate` 只执行同步兜底。
6. 捕获停止错误会显示在状态中，不再静默忽略。

`build.sh`：默认生成 `build/dev/RayNeoWorkspace-Dev.app`，bundle ID `local.rayneo.workspace.dev`，与原版应用分离。支持 `BUILD_DIR` 和 `SIGNING_IDENTITY`；默认仍为 ad hoc 签名，尚未解决稳定签名身份配置。开发版需独立授权，原应用的权限不迁移。

图标：原创三屏空间图形。`Assets/AppIcon.png` 是预览，`Assets/AppIcon.icns` 是应用资源；生成源码和脚本位于 `scripts/`。正常构建直接使用已保存的 ICNS，不依赖图标生成工具运行。

## 验证与下一步

已通过编译、生命周期测试替身检查、签名完整性和 Info.plist 检查。图标已目视检查。实机步骤和边界见 `docs/TESTING.md`。

**尚未启动新应用实机验证**。下一步先在 GT 上验收 v0.9.0，尤其是快速启动/停止、停止中退出、连续会话、GT 布局恢复及原生输入。不要把编译和测试替身通过描述成真实设备验证通过。

已知余项：系统异步调用不返回时没有超时兜底；恢复 GT 布局失败仍未充分报告；完整热拔插/睡眠唤醒恢复、稳定签名、设置持久化、工程拆分、纹理性能和长期漂移均未完成。原型仍使用私有 CGVirtualDisplay 接口。强制退出不保证正常清理。

默认状态文件仍在 `build/dev/runtime-status.json`，未来应迁入合适的用户数据目录。

## 新对话启动指令

> 请先读取 HANDOFF.md、README.md 和 docs/TESTING.md。项目已有可回退 v0.8 标签（e962868），当前工作在 improve/v0.9-lifecycle-icon，v0.9.0 开发版增加了顺序清理、等待退出、旧会话回调隔离和三屏应用图标。编译与生命周期测试通过，但尚未完成 GT 实机验收。先检查 git status/log，再按验收文档继续，不能覆盖原 v0.8 应用或标记未经验证的稳定发布。保留原生鼠标跨屏、键盘和窗口拖拽；不引入鼠标模式、黄点或事件映射。需要协议/历史信息时读取 docs/HANDOFF-v0.8.md。设备是 M2 MacBook Air + 雷鸟 GT，使用跟随模式。未授权刷固件、上传内容、推送远程或发布应用。
