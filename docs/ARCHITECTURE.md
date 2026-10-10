# v0.10 工程结构

单文件实现已拆分为多文件 Swift 编译，顶层入口在 `Sources/main.swift`。未引入第三方驱动或包依赖。

| 文件 | 职责 |
| --- | --- |
| `main.swift` | AppKit 入口；可选离屏控制面板预览 |
| `WorkspaceDelegate.swift` | 应用会话、启动/停止、设备和睡眠恢复、诊断调度 |
| `WorkspaceDelegate+Controls.swift` | 控制界面、设置保存、性能测试入口 |
| `WorkspaceDelegate+Scene.swift`、`SpatialLayout.swift`、`WorkspaceView.swift` | SceneKit 场景、布局与场景按键 |
| `WorkspaceDelegate+WindowPlacement.swift`、`WindowShortcuts.swift` | 可选辅助功能窗口移动，不处理鼠标事件 |
| `DisplayLayoutManager.swift` | 原 GT 位置持久记录、会话排列与恢复 |
| `DesktopCapture.swift` | 三路 ScreenCaptureKit、Metal 纹理和兼容转换 |
| `LatestFrameMailbox.swift` | 有锁的单帧邮箱，限制主线程积压 |
| `GTTracker.swift` | HID 匹配/移除监听，连接、运行时 IMU 开关 |
| `GyroIntegrator.swift` | 报告解析、零偏估计、梯形积分、静止零偏修正 |
| `WorkspaceSettings.swift` | 设置验证/原子保存，恢复意图和重试策略 |
| `AsyncDeadline.swift` | 系统异步操作有限时等待、取消及迟到完成隔离 |
| `RuntimeDiagnostics.swift`、`BenchmarkController.swift` | 本地 CPU/内存诊断与可重复动态负载 |

## 会话与恢复

所有显示器、UI 和会话变更在 MainActor 上执行。启动任务与停止任务各只保留一个，generation 屏蔽旧异步完成。停止时立即禁用帧/错误回调，再取消启动；正常路径等待启动和捕获停止后释放显示器。枚举/捕获启动上限 8 秒，等待启动取消上限 2 秒，每路停止上限 3 秒。

AsyncDeadline 不使用 task group 等待全部子任务，因为不响应取消的系统调用会让 task group 无法返回。超时后取消后台工作、恢复本地状态；后台若迟到完成，不能再恢复旧会话。捕获类单独处理迟到的 startCapture，移除输出并再次尝试限时停止。该机制不能保证系统内部故障即时恢复，应记录实际超时场景。

恢复意图独立于当前显示器对象。用户启动后保留意图；断开或睡眠不清除它，主动停止和退出会清除。恢复受开关、设备/屏幕就绪、睡眠状态、空闲状态和重试退避约束。失败三次后暂停，用户可手动重试。应用重开不会自动启动工作会话。

GT 输出显示器用 SmartGlasses 名称发现；HID 以原 VID/PID/usage 匹配，移除监听触发清理。输出 ID 变化也会重建会话。GT 原位置按显示器 UUID 写入恢复记录，支持重新连接后恢复，避免把旧 ID 应用到其他实体屏。

## 纹理与内存

ScreenCaptureKit 显式输出 sRGB / BGRA CVPixelBuffer，GPU 纹理使用 bgra8Unorm_srgb 保持灰阶转换一致。Metal 路径用 CVMetalTextureCache 生成 MTLTexture，直接赋给 SceneKit 材质，省去逐帧 CGImage 创建；失败时退回原 Core Image 路径。每块面板保留当前 CapturedFrame（像素缓冲和 CoreVideo 纹理包装），直到下一帧替换或会话停止。

捕获队列与主线程之间只允许一个待交付的最新帧；新帧覆盖未交付帧，计数为 mergedFrames。GPU 缓冲池和 ScreenCaptureKit 本身仍有各自缓冲，不能把单帧邮箱描述成整个渲染系统只有一帧。UI 状态降到 4 Hz 更新，诊断 1 Hz，停止后暂停连续 SceneKit 渲染。

Apple 接口参考：[SceneKit 材质支持 MTLTexture](https://developer.apple.com/documentation/scenekit/scnmaterialproperty/contents)。当前 M2 的离屏合成图像测试已确认 GPU 和 CGImage 路径方向、红蓝和中/暗灰颜色一致；最终桌面阅读体验仍需在眼镜中验证。

## 姿态边界

初始校准需至少 2 秒与 200 样本；明显运动会重启窗口，方差过大不会接受校准。使用主机单调时间和梯形积分，超过 100 ms 的采样间断不补积分，避免睡眠/掉线后跳转。

可选静止修正要求加速度模长稳定、三轴扣偏角速度低于 0.25 度/秒且持续 3 秒，再以 20 秒时间常数缓慢更新零偏。它仍可能把非常慢的有意运动当作静止，因此提供关闭选项。加速度仅用于辅助判定静止，没有宣称提供绝对 yaw 融合；磁力计和绝对航向未实现。

原生跨屏操作、1920×1080 三屏与 GT 输出排列保持原设计。实验测试与用户验收分开记录，不能据自动测试通过覆盖真实 WindowServer、TCC、HID 或眼镜行为。
