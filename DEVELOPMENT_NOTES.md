# RayNeo GT macOS workspace prototype

## Current input behavior: version 0.8

Mouse control is native macOS input. The custom event tap, synthetic mouse events, pointer warps, yellow overlay, speed scaling, and mouse-mode toggle have been removed. Capture includes the system cursor. Displays are arranged as Mac → RayNeo Left → Center → Right → physical GT compositor output, so the output display no longer sits between Mac and the three working desktops. The GT render window ignores mouse events and follows screen-layout changes. The app restores the GT output's original session position when stopping. Ordinary clicking, typing, scrolling and window dragging do not require Accessibility permission. Optional window-placement buttons and ⌘⌥1/2/3/0 still require Accessibility. Screen Recording is required for rendering the virtual desktops. Compilation is verified. The user confirmed on 2026-10-10 that native cross-screen window dragging and operation work correctly. The older mouse-mode instructions below describe superseded experiments.

Prototype on 2026-10-10. Version 0.2 creates three independent virtual displays and captures each into the head-tracked scene. Display creation, layout, process-exit cleanup, and three live capture streams are verified locally. User verification of spatial input and working with real application windows remains pending.

## Confirmed locally

- Host: Apple M2, macOS 26.6.2.
- USB product: `RayNeo AR Glasses`; VID/PID `3941:AF50`.
- Current USB interface: 0, HID class 3, two endpoints.
- HID usage page/usage: `FF00:01`.
- Input/output report sizes: 64 bytes; no feature reports advertised.
- Native HID manager opens successfully outside the execution sandbox.
- Ten seconds of passive listening received zero reports. This does not prove IMU is unavailable; runtime streaming may need explicit activation.
- AppKit display enumeration at the time of the probe returned only `LG HDR 4K` (1920x1080). GT video output was not yet confirmed.

## Follow-up verification

- With the external monitor disconnected, AppKit detects the built-in Retina display and `SmartGlasses` at 1920x1080. The user confirms GT video works when the external display is disconnected.
- A reviewed runtime-only IMU ON command (`66 01 00`, zero-padded to 64 bytes) starts data streaming. IMU OFF (`66 02 00`) succeeds after the test.
- A 12-second probe received 5,584 finite decoded IMU samples, approximately 465.3 Hz. The format matches the SDK's 64-byte `99 65` IMU packet layout.
- `Sources/WorkspaceDemo.swift` renders three demo panels on the GT display, integrates gyro data with a locally estimated stationary bias, and uses yaw for camera rotation.
- The user confirms the center panel appears and turning their head reveals both side panels. Long-session drift, latency, pitch/roll and real window interaction remain unverified.

## Launch the demo

Build with `bash build.sh`, then open `build/RayNeoWorkspace.app`.

Version 0.2 adds a control window on the Mac and a `GT 三屏` menu-bar item. Click `启动三屏` and grant screen recording access in macOS Privacy & Security. macOS may require quitting and reopening the app before access takes effect. The app only captures its three virtual displays, does not capture audio, has no network code, and does not save image/video content. `build/runtime-status.json` stores only status, device/sample counters, virtual display IDs, and capture frame counts for diagnostics.

The three 1920x1080@60Hz virtual monitors are `RayNeo Left`, `RayNeo Center`, and `RayNeo Right`; captures target 30fps for this prototype. They are placed side by side to the right of existing screens using a session-scoped display configuration. Each receives an editable test window. Move real application windows onto these screens with normal macOS window dragging.

Version 0.4 adds opt-in spatial mouse control. After starting the three screens, click `控制眼镜鼠标 ⌘⌥M` and grant macOS Accessibility permission. Click again after authorization if needed. Mouse movement controls a yellow pointer in the eye viewport; SceneKit hit testing maps its position to the corresponding virtual display. Clicks, dragging and scrolling are forwarded there. Keyboard input follows the focused app normally; the app does not intercept keyboard events. `⌘⌥M` is a global toggle that stops forwarding and returns the cursor to the Mac control screen. Stopping screens or quitting also stops forwarding and releases held mouse buttons. The source compiles successfully; user verification of actual interaction is pending. Diagnostics now include mouse activation and forwarded-event counts.

The initial 0.2 launch failed during layout. The correction waits for WindowServer registration and skips mirror-disable calls for already independent displays. A separate probe verified all three origin calls and the session commit returned success. After the probe process exited, a fresh enumeration confirmed only the built-in display and SmartGlasses remained.

macOS subsequently rejected capture authorization because the ad-hoc code hash changed on rebuild. A targeted `tccd` log confirmed `Failed to match existing code requirement` with the old/new hashes. Only this app's authorization was reset with `tccutil reset ScreenCapture local.rayneo.workspace.demo`, then the unchanged repair build was reopened for the user to authorize. Do not rebuild/re-sign between authorization and verification. A stable development signing identity is a future development-workflow improvement.

After reauthorization, the running app successfully created independent display IDs 23/24/25 and started three capture streams. Two diagnostic snapshots showed frame counts rising from `[34,35,33]` to `[60,62,59]` while IMU samples rose from 6,505 to 17,294. Static display content may produce fewer complete frames than the configured 30fps maximum. No screen images were saved for this verification.

Use `停止三屏` to remove the virtual displays, or `退出` in the control panel/menu bar to close the app and stop runtime IMU streaming. These controls avoid relying on the eye-display window having keyboard focus. Closing the control panel alone does not quit; reopen it from the menu-bar item.

Virtual displays use the private `CGVirtualDisplay` API; macOS updates may change compatibility. No kernel extension, DisplayLink driver, or hardware dock is needed. A short-lived probe successfully created display IDs 11/12/13, confirmed 1920x1080 and no mirroring via CoreGraphics, then released all three and confirmed only the two original displays remained.

Use the GT's Follow mode to avoid applying built-in anchoring and software tracking simultaneously. Hold the glasses still for the first two seconds for local bias estimation. This calibration only changes program memory, not the glasses.

- `R`: recenter software orientation.
- `C`: repeat local stationary bias estimation.
- `Space`: pause camera updates.
- `F`: reverse yaw direction.
- `X/Y/Z`: select yaw sensor axis (default Y).
- `Esc`: quit and send runtime IMU OFF.

Version 0.3 starts with hidden panels and a waiting status, so an authorization/startup failure cannot be mistaken for functioning independent desktops. After successful startup, the surfaces show the three independent desktops.

The user's full screenshot verified real captured desktop content but also showed the physical GT menu bar above the captured desktop's own menu bar, and a large panel margin. Version 0.3 raises only the eye-display output window above the system status-bar level, uses a panel width of 2.50 at distance 3 and horizontal FOV 46 degrees (approximately 98% view coverage when aligned), adds panel scale controls (65%-125%), and hides diagnostic text after startup. It does not remove the captured virtual desktop's own menu bar, which is needed for normal app operation. User verification of this presentation change is pending.

Use the Mac control panel's `屏幕放大`, `屏幕缩小`, and `显示/隐藏状态文字` buttons. Keyboard `+/-` and `H` do the same when the eye-display window has keyboard focus. The Mac control panel and menu-bar quit entry remain available. The original head-tracked demo was verified by the user; automated visual inspection was unavailable because Computer Use permissions were not granted.

## Safety scope

Version 0.7 adds explicit window placement to avoid dragging through the physical GT output display to reach the virtual desktops. Select a normal app window and press `⌘⌥1`, `⌘⌥2`, or `⌘⌥3` to move it to Left, Center, or Right; `⌘⌥0` returns it to the built-in display. Control-panel buttons target the most recently active external app. These user-triggered actions use Accessibility to move its focused window and reduce its size only as needed to fit the destination. Fullscreen windows are rejected with an instruction to exit fullscreen first. The spatial mouse's forwarded deltas now reflect mapped destination changes, instead of zeroing movement needed by some title-bar drag handlers. Manual dragging from Mac requires switching off spatial mouse with `⌘⌥M`. Compilation is verified; actual third-party window movement needs user testing.

Version 0.6 removes the yellow overlay after the user reported a mismatch with the actual cursor. ScreenCaptureKit now includes the native cursor. Each mapped mouse event synchronizes the system cursor with the same virtual-desktop coordinate using `CGWarpMouseCursorPosition`, then returns the modified original event. Apple's documentation specifies that warping does not generate a mouse event: https://developer.apple.com/documentation/coregraphics/cgwarpmousecursorposition(_:). Actual cursor/click alignment still requires user verification.

Version 0.5 addresses the user's report of pointer movement while both mouse and head were stationary. The event tap returns a modified original event instead of reposting it into its own stream, ignores program-generated motion, rejects zero-delta movement, and limits large input deltas. The pointer is anchored to a virtual-desktop coordinate and projected into the current camera view; head motion alone does not change its click destination. Mouse gain defaults to 40% and can be cycled through 25/40/60/80% in the control panel. When its desktop leaves the view, the pointer hides; the next hardware move starts in the new view's center. User verification is pending.

`probes/passive_probe.swift` only enumerates displays and receives HID input. It has no output reports, control transfers, firmware operations, calibration writes, device resets, or exclusive opens. It filters HID devices to the GT VID/PID. `probes/imu_probe.swift` and the demo additionally send strictly whitelisted runtime IMU ON/OFF commands. They cannot send arbitrary device commands and do not change firmware or permanent configuration.

## Build and run

```sh
xcrun swiftc -sdk "$(xcrun --show-sdk-path)" -module-cache-path /private/tmp/rayneo-swift-cache probes/passive_probe.swift -o probes/passive_probe
./probes/passive_probe
```

The Codex execution sandbox blocked HID access and screen enumeration; an approved sandbox-external run succeeded. No system driver was installed.

## Next checks

1. Verify visible independent desktop contents and real window content updates with the user.
2. Verify focus/input behavior, text clarity and long-session drift.
3. Improve window placement, pointer ergonomics and rendering efficiency based on observed behavior.

## References

- https://github.com/peterradzisz/Air4-Pro-Gyro-PC/blob/main/config.py
- https://github.com/verncat/RayNeo-Air-3S-Pro-OpenVR
- https://github.com/verncat/RayNeo-Air-3S-Pro-OpenVR/blob/main/src/RayneoApi.cpp
- https://github.com/Fuzzy-Team/virtual-monitor-helper/blob/main/CGVirtualDisplayPrivate.h
- https://github.com/enfp-dev-studio/node-mac-virtual-display/blob/main/src/virtual_display.mm

## 2026-10-10：独立 Git 基线与 v0.9.0 开发优化

保存 v0.8 到 main 和带注释标签 v0.8（e962868），原发布 ZIP 与校验清单一起纳入 Git。开发工作在 improve/v0.9-lifecycle-icon；独立开发应用身份和 build/dev 输出路径避免覆盖基线。

新增启动任务取消与等待、停止任务去重、捕获停止后再释放显示器、旧错误回调会话校验、系统等待清理后退出，以及原创三屏图标。构建和生命周期测试通过；真实设备验收仍待完成，步骤见 docs/TESTING.md。当前接续工作以 HANDOFF.md 为准，原交接位于 docs/HANDOFF-v0.8.md。

## 2026-10-10：v0.10.0 七项整轮优化

用户要求七项一起完成后统一验收。建立 improve/v0.10-recovery-performance，先保存 v0.9.0-dev 回退标签。工程已拆分，入口改为 Sources/main.swift。

实现热拔插/睡眠恢复与有限自动重试、有限时清理和持久布局恢复、专用本地稳定签名、设置保存和新面板、Metal 纹理/最新帧合并/动态负载与诊断 CSV，以及校准方差、梯形积分、采样间断与可关闭的静止零偏修正。原生输入和运行时 IMU 指令白名单保留。

本机现有签名身份在沙箱外可见，但证书已过期，因此没有复用；新专用钥匙串加入用户搜索列表，保留其他条目，不更改默认钥匙串。签名配置和私钥排除在 Git 外。Metal 在沙箱内不可用，沙箱外离屏合成纹理测试通过；该差异不能用于推断产品必须提权。

自动检查、离屏 UI/GPU 检查、签名与 CSV 工具检查通过。真实 GT 三屏、更新后授权、拔插/唤醒、功耗/端到端延迟、漂移与阅读效果全部留到统一验收。当前文档以 HANDOFF.md 和 docs/TESTING.md 为准。

最终离屏纹理检查加入中灰/暗灰后发现 plain BGRA Metal 纹理与 CGImage 的颜色空间不同；改用 bgra8Unorm_srgb，并显式指定捕获 sRGB，红蓝/灰阶及方向重新比较通过。不能仅测试饱和红蓝来证明文字灰阶正确。
