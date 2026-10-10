# RayNeo GT Mac Workspace

<img src="Assets/AppIcon.png" width="96" alt="RayNeo GT Mac Workspace icon">

[简体中文](README.zh-CN.md) | English

**Three virtual macOS desktops for RayNeo GT AR glasses, with head tracking and native mouse and keyboard input.**

RayNeo GT Mac Workspace turns an Apple Silicon Mac and a USB-C-connected RayNeo GT into a spatial workspace. Put real macOS app windows on three independent desktops, then turn your head to view the left, center, and right desktop.

Suggested GitHub repository name: **`rayneo-gt-mac-workspace`**.

## Features

- Three independent 1920 × 1080 virtual displays for real macOS applications.
- Gyroscope-based head tracking, recentering, and startup calibration.
- Native mouse movement across desktops, typing, scrolling, and window dragging.
- Adjustable panel size, distance, spacing, tracking axis, and direction.
- Selectable capture/render frame rates and Metal or Core Image texture paths.
- Persistent settings, local diagnostics, and desktop layout recovery.
- Reopen the control panel from the Dock, menu bar, or app menu with **⌘0**.
- Optional shortcuts to move the focused app window: **⌘⌥1 / 2 / 3**, or **⌘⌥0** to return it to the Mac.

## Compatibility and project status

| Requirement | Details |
| --- | --- |
| Mac | Apple Silicon, arm64; M2 tested, M4 not yet tested |
| macOS | 26.0 or later |
| Glasses | RayNeo GT, connected directly by a video-capable USB-C cable |
| Glasses mode | Follow mode |
| Build tools | Xcode Command Line Tools or Xcode with a macOS 26+ SDK and Swift compiler |

The tested setup is **M2 MacBook Air + macOS 26.6.2 + RayNeo GT**. M4 shares the supported arm64 architecture, but its complete hardware combination has not been tested. Other glasses models are not currently verified.

**Current version: 0.10.1 development trial.** The user has confirmed three-screen viewing, head tracking, and Dock reopening after the latest fixes. Long-running sessions, reconnects, and sleep/wake recovery still need broader testing. The original **v0.8** baseline is preserved in Git.

The app uses the private `CGVirtualDisplay` API, so compatibility may change with macOS updates. Head tracking uses gyroscope integration; recentering may be needed during longer sessions.

## Build and run

Download and extract the source, or clone your copy of this repository. Open Terminal in the project folder.

```sh
git clone https://github.com/poppinyunhai/rayneo-gt-mac-workspace.git
cd rayneo-gt-mac-workspace
```

If build tools are not installed:

```sh
xcode-select --install
```

For a first local trial, build with an ad hoc signature:

```sh
SIGNING_IDENTITY=- bash build.sh
open build/dev/RayNeoWorkspace-Dev.app
```

The app is created at `build/dev/RayNeoWorkspace-Dev.app`. The standalone source trial ZIP also includes `构建体验版.command`, a double-click build helper.

For repeated development, configure your own stable signing identity using [the signing guide](docs/SIGNING.md). No original developer certificate or private key is required. Rebuilding or changing the signing identity can require granting screen recording permission again.

## First session

1. Quit other RayNeo Workspace versions. Connect the GT directly to the Mac and select **Follow mode** on the glasses. The tested setup has no other physical external monitor attached.
2. Open the app and click **启动三屏** (Start three displays).
3. Grant **Screen & System Audio Recording** permission in System Settings → Privacy & Security. If macOS requests it, quit and reopen the app, then start again. The app does not capture audio.
4. Keep the glasses still for about **3 seconds**, until the control panel shows **姿态追踪** (Head tracking). Turn your head left and right to view the other desktops. Looking straight ahead normally shows the center desktop.
5. Move the mouse past the Mac screen's right edge to reach the left, center, and right desktops. Use normal typing, scrolling, and dragging.
6. Click **回中** (Recenter) to reset your forward direction. Use **停止三屏** (Stop) to remove the virtual displays and restore the layout; use **退出** (Quit) or **⌘Q** to exit.

The control panel is currently in Chinese. Common labels: **重新校准** = Recalibrate, **恢复布局** = Restore layout, **显示控制面板** = Show controls.

Normal mouse and keyboard input does not need Accessibility permission. The optional window-moving buttons and shortcuts do.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Only the center desktop is visible when turning your head | Wait for calibration, check Follow mode, and check the tracking axis/direction settings. The control panel shows tracking status and angle. |
| Black screen or capture failure | Check screen recording permission, quit/reopen if requested, or choose **兼容模式 · Core Image** (Compatibility mode), stop, and restart the session. |
| Control panel is closed or minimized | Click the Dock icon, use the “GT 三屏” menu bar item, or press ⌘0 while the app is active. |
| Layout remains changed after an abnormal exit | Reopen the app and use **恢复布局** (Restore layout) when the GT is connected. |

## Local data and privacy

Screen content is processed locally for display in the glasses. The app does not save screen recordings, capture audio, or upload screen content. It does not flash firmware or write permanent device calibration.

Local settings and diagnostics are stored in `~/Library/Application Support/RayNeoWorkspace-Dev/`:

- `settings.json`: preferences.
- `pending-layout.json`: original output position for layout recovery.
- `runtime-status.json`: session, capture, head-tracking, CPU, and memory status; no screen images.

## Development

```sh
bash Tests/run-tests.sh
bash Tests/run-texture-test.sh
```

The first command checks core behavior and lifecycle cleanup. The second uses a real Metal device for offscreen texture checks.

Capture local metrics:

```sh
python3 scripts/collect-metrics.py --duration 60
```

Create a standalone source trial ZIP:

```sh
python3 scripts/package-source.py
```

Output: `build/exports/RayNeoWorkspace-v0.10.1-source-trial.zip`.

| Resource | Purpose |
| --- | --- |
| [Friend trial guide](docs/FRIEND_TRIAL.md) | Chinese setup and trial instructions |
| [Architecture](docs/ARCHITECTURE.md) | Implementation and component structure |
| [Testing](docs/TESTING.md) | Checks and hardware acceptance status |
| [Performance](docs/PERFORMANCE.md) | Metrics, frame rates, and drift measurements |
| [Signing](docs/SIGNING.md) | Local signing setup |

Most detailed development documents are currently in Chinese. To report an issue, include your Mac model, macOS version, GT model, steps to reproduce, and control panel status. Remove personal content before attaching screenshots or diagnostics.

This is an independent community project and is not an official RayNeo product.
