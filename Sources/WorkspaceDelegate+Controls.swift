import AppKit
import SceneKit

extension WorkspaceDelegate {
    func createControls() {
        let menu = NSMenu(), appMenu = NSMenu()
        let controlsItem = NSMenuItem(title:"显示控制面板",action:#selector(showControls),keyEquivalent:"0")
        controlsItem.target=self;appMenu.addItem(controlsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:"退出 RayNeo Workspace",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let item=NSMenuItem();item.submenu=appMenu;menu.addItem(item);NSApp.mainMenu=menu
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusItem.button?.title="GT 三屏"
        let statusMenu=NSMenu()
        for (title,action) in [("显示控制面板",#selector(showControls)),("停止三屏",#selector(stopDesktops)),("恢复布局",#selector(restoreLayout))] {
            let item=NSMenuItem(title:title,action:action,keyEquivalent:"");item.target=self;statusMenu.addItem(item)
        }
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle:"退出",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        statusItem.menu=statusMenu
        controlWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:660),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        controlWindow.isReleasedWhenClosed=false;controlWindow.title="RayNeo Workspace Dev · 三屏工作区"
        let content=controlWindow.contentView!
        func label(_ text:String,_ frame:NSRect,_ size:CGFloat=13) -> NSTextField {
            let field=NSTextField(wrappingLabelWithString:text);field.frame=frame;field.font = .systemFont(ofSize:size)
            content.addSubview(field);return field
        }
        _ = label("把三个独立 Mac 桌面放进 GT",NSRect(x:24,y:600,width:712,height:35),23)
        _ = label("GT 使用跟随模式。鼠标从 Mac 右边缘进入左 / 中 / 右屏，直接输入和拖拽。未连接眼镜时可先调整设置；连接后启动。",NSRect(x:24,y:535,width:712,height:50))
        for (index,name) in ["移到左屏 ⌘⌥1","移到中屏 ⌘⌥2","移到右屏 ⌘⌥3","移回 Mac ⌘⌥0"].enumerated() {
            let button=NSButton(title:name,target:self,action:#selector(moveWindowButton(_:)));button.tag=index
            button.frame=NSRect(x:24+index*180,y:485,width:172,height:34);content.addSubview(button)
        }
        for (index,spec) in [("scale","屏幕大小",0.65,1.25),("distance","观看距离",2.0,5.0),("spacing","屏幕间距",35.0,65.0)].enumerated() {
            let x=CGFloat(24+index*240)
            settingsControls[spec.0+"Label"]=label(spec.1,NSRect(x:x,y:443,width:220,height:23))
            let slider=NSSlider(value:spec.2,minValue:spec.2,maxValue:spec.3,target:self,action:#selector(changeLayout(_:)))
            slider.identifier=NSUserInterfaceItemIdentifier(spec.0);slider.isContinuous=false
            slider.frame=NSRect(x:x,y:409,width:220,height:25);content.addSubview(slider);settingsControls[spec.0]=slider
        }
        _ = label("性能模式（下次启动生效）",NSRect(x:24,y:365,width:300,height:20))
        let quality=NSPopUpButton(frame:NSRect(x:24,y:329,width:290,height:30),pullsDown:false)
        quality.addItems(withTitles:["节能 · 捕获15 / 场景30 fps","均衡 · 捕获30 / 场景60 fps","流畅 · 捕获60 / 场景60 fps"])
        quality.target=self;quality.action=#selector(changeQuality(_:));content.addSubview(quality);settingsControls["quality"]=quality
        _ = label("纹理路径（下次启动生效）",NSRect(x:380,y:365,width:300,height:20))
        let texture=NSPopUpButton(frame:NSRect(x:380,y:329,width:340,height:30),pullsDown:false)
        texture.addItems(withTitles:["Metal 纹理 · 降低转换开销","兼容模式 · Core Image"])
        texture.target=self;texture.action=#selector(changeTexture(_:));content.addSubview(texture);settingsControls["texture"]=texture
        _ = label("转头轴 / 方向",NSRect(x:24,y:287,width:260,height:20))
        let axis=NSPopUpButton(frame:NSRect(x:24,y:252,width:120,height:30),pullsDown:false)
        axis.addItems(withTitles:["Yaw X","Yaw Y","Yaw Z"]);axis.target=self;axis.action=#selector(changeAxis(_:));content.addSubview(axis);settingsControls["axis"]=axis
        let direction=NSButton(checkboxWithTitle:"反转方向",target:self,action:#selector(changeDirection(_:)))
        direction.frame=NSRect(x:166,y:252,width:160,height:30);content.addSubview(direction);settingsControls["direction"]=direction
        for (i,spec) in [("recovery","重连 / 唤醒后自动恢复"),("bias","静止时缓慢修正零偏"),("testWindows","启动时显示测试窗口")].enumerated() {
            let button=NSButton(checkboxWithTitle:spec.1,target:self,action:#selector(changeOption(_:)))
            button.identifier=NSUserInterfaceItemIdentifier(spec.0);button.frame=NSRect(x:380,y:252-i*35,width:350,height:30)
            content.addSubview(button);settingsControls[spec.0]=button
        }
        let reset=NSButton(title:"恢复默认设置",target:self,action:#selector(resetSettings));reset.frame=NSRect(x:24,y:206,width:150,height:30);content.addSubview(reset)
        let files=NSButton(title:"打开诊断文件夹",target:self,action:#selector(openDiagnostics));files.frame=NSRect(x:184,y:206,width:150,height:30);content.addSubview(files)
        controlStatus=label(desktopStatus,NSRect(x:24,y:86,width:712,height:85))
        let specs:[(String,Selector)]=[("启动三屏",#selector(startDesktops)),("回中",#selector(recenter)),("重新校准",#selector(recalibrate)),("停止三屏",#selector(stopDesktops)),("恢复布局",#selector(restoreLayout)),("性能测试",#selector(toggleBenchmark)),("退出",#selector(quit))]
        for (i,spec) in specs.enumerated() {
            let button=NSButton(title:spec.0,target:self,action:spec.1);button.bezelStyle = .rounded
            button.frame=NSRect(x:24+i*102,y:28,width:94,height:34);content.addSubview(button)
        }
        syncSettingsControls()
        if let screen=NSScreen.screens.first(where:{ screen in displayID(screen).map { CGDisplayIsBuiltin($0) != 0 } ?? false }) {
            controlWindow.setFrameOrigin(NSPoint(x:screen.visibleFrame.midX-380,y:screen.visibleFrame.midY-330))
        } else { controlWindow.center() }
        showControls()
    }
    func persistSettings() {
        settings.yawAxis=yawAxis;settings.direction=direction;settings.scale=Double(panelScale)
        settings=settings.validated()
        do { try settingsStore.save(settings) }
        catch { desktopStatus="设置保存失败：\(error.localizedDescription)" }
    }
    func syncSettingsControls() {
        (settingsControls["scale"] as? NSSlider)?.doubleValue=settings.scale
        (settingsControls["distance"] as? NSSlider)?.doubleValue=settings.distance
        (settingsControls["spacing"] as? NSSlider)?.doubleValue=settings.spacingDegrees
        (settingsControls["scaleLabel"] as? NSTextField)?.stringValue=String(format:"屏幕大小 · %.0f%%",settings.scale*100)
        (settingsControls["distanceLabel"] as? NSTextField)?.stringValue=String(format:"观看距离 · %.1f",settings.distance)
        (settingsControls["spacingLabel"] as? NSTextField)?.stringValue=String(format:"屏幕间距 · %.0f°",settings.spacingDegrees)
        (settingsControls["quality"] as? NSPopUpButton)?.selectItem(at:settings.captureFPS==15 ? 0 : settings.captureFPS==60 ? 2 : 1)
        (settingsControls["texture"] as? NSPopUpButton)?.selectItem(at:settings.useGPUTextures ? 0 : 1)
        (settingsControls["axis"] as? NSPopUpButton)?.selectItem(at:yawAxis)
        (settingsControls["direction"] as? NSButton)?.state=direction<0 ? .on : .off
        (settingsControls["recovery"] as? NSButton)?.state=settings.automaticRecovery ? .on : .off
        (settingsControls["bias"] as? NSButton)?.state=settings.adaptiveBias ? .on : .off
        (settingsControls["testWindows"] as? NSButton)?.state=settings.showTestWindows ? .on : .off
    }
    @objc func changeLayout(_ sender:NSSlider) {
        switch sender.identifier?.rawValue {
        case "scale":settings.scale=sender.doubleValue;panelScale=Float(settings.scale)
        case "distance":settings.distance=sender.doubleValue
        case "spacing":settings.spacingDegrees=sender.doubleValue
        default:return
        }
        SpatialLayout.apply(panels:panels,settings:settings);persistSettings();syncSettingsControls()
    }
    @objc func changeQuality(_ sender:NSPopUpButton) {
        settings.captureFPS=[15,30,60][sender.indexOfSelectedItem];settings.renderFPS=sender.indexOfSelectedItem==0 ? 30 : 60
        persistSettings();desktopStatus="性能设置已保存，下次启动三屏生效"
    }
    @objc func changeTexture(_ sender:NSPopUpButton) {
        settings.useGPUTextures=sender.indexOfSelectedItem==0;persistSettings();desktopStatus="纹理设置已保存，下次启动三屏生效"
    }
    @objc func changeAxis(_ sender:NSPopUpButton) { yawAxis=sender.indexOfSelectedItem;tracker.recenter();persistSettings() }
    @objc func changeDirection(_ sender:NSButton) { direction=sender.state == .on ? -1 : 1;tracker.recenter();persistSettings() }
    @objc func changeOption(_ sender:NSButton) {
        let enabled=sender.state == .on
        switch sender.identifier?.rawValue {
        case "recovery":settings.automaticRecovery=enabled;recovery.automaticallyRecover=enabled
        case "bias":settings.adaptiveBias=enabled;tracker.integrator.adaptiveBias=enabled
        case "testWindows":settings.showTestWindows=enabled
        default:return
        }
        persistSettings()
    }
    @objc func resetSettings() {
        settings=WorkspaceSettings();yawAxis=settings.yawAxis;direction=settings.direction;panelScale=Float(settings.scale)
        recovery.automaticallyRecover=settings.automaticRecovery;tracker.integrator.adaptiveBias=settings.adaptiveBias
        SpatialLayout.apply(panels:panels,settings:settings);persistSettings();syncSettingsControls()
        desktopStatus="默认设置已恢复；性能与纹理选项下次启动三屏生效"
    }
    @objc func recalibrate() { tracker.recalibrate();desktopStatus="请保持眼镜静止，重新估计零偏" }
    @objc func openDiagnostics() {
        try? FileManager.default.createDirectory(at:dataDirectory,withIntermediateDirectories:true)
        NSWorkspace.shared.open(dataDirectory)
    }
    @objc func toggleBenchmark() {
        guard !starting,stopTask==nil,virtualDisplays.count==3 else { desktopStatus="请先完成三屏启动，再运行性能测试";return }
        if benchmark.running { benchmark.stop();desktopStatus="性能动态内容已停止" }
        else { benchmark.start(displayIDs:virtualDisplays.map { $0.displayID });desktopStatus="三屏动态内容已启动；再次点击性能测试停止" }
    }
}
