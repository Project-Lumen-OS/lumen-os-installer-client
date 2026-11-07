import SwiftUI
import AppKit

/// `--snapshots DIR`: renders every screen of the demo flow to PNG (for checking the layout without a display).
@MainActor
enum Snapshots {
    static func run(_ base: String) {
        for l in Lang.allCases { Lang.current = l; one(base.appending(path: l.rawValue)) }
    }

    static func one(_ dir: String) {
        let m = AppModel()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func shot(_ name: String, demoPanel: Bool = true, _ content: some View) {
            let v = ZStack {
                SkyBackground()
                HStack(spacing: 0) {
                    SidebarView().frame(width: 248)
                    Divider().overlay(Theme.line)
                    VStack { content.frame(maxWidth: 860).padding(.horizontal, 40).padding(.top, 44); Spacer(minLength: 0) }.frame(maxWidth: .infinity)
                    if demoPanel { Divider().overlay(Theme.line); DemoProjectorPanel().frame(width: 290) }
                }
            }
            .frame(width: 1240, height: 860)
            .environmentObject(m)
            .environment(\.colorScheme, .dark)
            let r = ImageRenderer(content: v)
            r.scale = 1
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir.appending(path: "\(name).png")))
            }
        }
        // welcome
        let w = ImageRenderer(content: ZStack { SkyBackground(); WelcomeView() }.frame(width: 1240, height: 800).environmentObject(m).environment(\.colorScheme, .dark))
        if let t = w.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: t) { try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir.appending(path: "0-welcome.png"))) }

        m.mode = .demo
        m.simStatus = Simulator.Status(cable: true, screen: .stock, lastWrite: nil)
        var d = Device(serial: Simulator.serial, hwSerial: Simulator.serial, transport: .usb, state: "device")
        d.match = Match(id: "z9x", by: .model, detail: "по модели G0082"); d.system = "родная система XGIMI"; d.firmware = "v6.15.58"; d.firmwareOk = true
        m.devices = [d]; m.selectedDeviceID = d.id
        m.serialInput = "XHN2408001"; m.serialMatch = Profiles.identify(m.profiles, serial: "XHN2408001"); m.serialTried = true
        shot("0-prepare", PrepareStepView())
        shot("1-device", DeviceStepView())
        m.releases = [Release(tag: "z9x-1.0.8", title: "", prerelease: false, published: Date(), device: "z9x", version: "1.0.8", installer: nil,
                              images: [Asset(name: "lumen-os-1.0.8-nogms-system.img", size: 989626368, url: "")], sums: nil, sig: nil),
                      Release(tag: "v1.0.7", title: "", prerelease: false, published: Date().addingTimeInterval(-86400 * 9), device: "z9x", version: "1.0.7", installer: nil,
                              images: [Asset(name: "lumen-os-1.0.7-nogms-system.img", size: 989048832, url: "")], sums: nil, sig: nil)]
        m.selectedReleaseTag = "z9x-1.0.8"; m.downloadProgress = 0.62; m.downloadFile = "lumen-os-1.0.8-nogms-system.img"
        shot("2-system", SystemStepView())
        m.downloadProgress = nil
        m.workspace = Workspace(dir: "~/Lumen Installer/releases/z9x-1.0.8", installerDir: "", image: "~/Lumen Installer/releases/z9x-1.0.8/lumen-os-1.0.8-nogms-system.img", tag: "z9x-1.0.8", device: "z9x")
        m.gappsEnabled = true; m.gappsOK = true; m.gappsFile = "/x/MindTheGapps-14.0.0-arm64-ATV-full-20240523_192016.zip"
        m.gappsState = "Файл подходит: MindTheGapps-14.0.0-arm64-ATV-full-20240523_192016.zip, sha256 совпадает."
        shot("3-google", GoogleStepView())
        m.gappsEnabled = false
        shot("4-install-summary", InstallStepView())
        m.devices = []
        shot("4b-install-no-projector", InstallStepView())
        m.devices = [d]
        m.runTitle = L("Установка Lumen OS"); m.running = true; var o = RunOptions(); o.noBlobs = true; m.lastOptions = o
        m.state = ["step_check": "done", "step_backup": "skipped", "step_vbmeta": "done"]
        m.simStatus = Simulator.Status(cable: true, screen: .fastboot, lastWrite: "fastboot flash system lumen-os-1.0.8-nogms-system.img")
        let sample = ["$ bash lumen-install.sh --lang ru --serial ZF62DEMO0042 --no-blobs",
                      "21:41:39   ✓ Platform-Tools 35.0.2 (tools/platform-tools, проверены), свой сервер adb на порту 5038",
                      "21:41:39   ✓ XGIMI Z9X ZF62DEMO0042, прошивка v6.15.58, слот b, система: родная XGIMI",
                      "21:41:39   ! --no-blobs: не будет звука и защищённого видео (например, Кинопоиск HD)",
                      "21:41:39   ✓ подпись SHA256SUMS: ключ Lumen OS",
                      "Введите ERASE, чтобы продолжить: ERASE",
                      "21:41:41 перезагрузка в fastbootd (около 30 секунд)",
                      "21:41:48 записываю system (около 40 секунд)"]
        m.log = sample.enumerated().map { i, t in LogLine(text: t, kind: i == 0 ? .cmd : t.contains("✓") ? .ok : t.contains("! ") ? .warn : t.hasPrefix("Введите") ? .answer : .info) }
        shot("5-install-running", InstallStepView())
        m.running = false; m.exitCode = 0
        m.state = ["step_check": "done", "step_backup": "skipped", "step_vbmeta": "done", "step_flash": "done", "step_verify": "done"]
        m.simStatus = Simulator.Status(cable: true, screen: .lumen, lastWrite: "fastboot reboot")
        shot("6-install-done", InstallStepView())
        m.log.append(LogLine(text: "21:42:30   ✓ записано. Первый запуск 2–4 минуты; на проекторе появится экран настройки.", kind: .ok))
        m.log.append(LogLine(text: "21:46:31 СТОП: проектор не отвечает по adb", kind: .stop))
        m.exitCode = 1; m.chainSkipped = true
        shot("6b-install-written", InstallStepView())
        m.chainSkipped = false
        m.exitCode = 0; m.waitingGapps = "MindTheGapps.zip"
        shot("6c-install-waiting-gapps", InstallStepView())
        m.waitingGapps = nil
        let prompt = PromptSheet(prompt: Prompt(question: "Введите ERASE, чтобы продолжить:", context: [
            "Записываю Lumen OS в слот b, затем СТИРАЮ ВСЕ ДАННЫЕ проектора (приложения, аккаунты,",
            "настройки, файлы). В слоте b УДАЛЯЮТСЯ разделы XGIMI product_b и system_ext_b (части",
            "стоковой системы, Lumen OS их не использует; стоковая система в другом слоте сохраняет свои) и",
            "остатки обновлений *-cow. Калибровка XGIMI, второй слот, vendor и boot не затрагиваются."], kind: .word("ERASE")))
        let pr = ImageRenderer(content: prompt.environmentObject(m).environment(\.colorScheme, .dark))
        if let t = pr.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: t) { try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir.appending(path: "7-prompt-erase.png"))) }
    }
}

/// `--readme-shots DIR`: the screens of a real install for the README, as the user build shows them (no demo panel),
/// drawn by AppKit in an off-screen window, so system controls (switches, segmented pickers, fields) are in the image.
/// A borderless window that can be key, so switches and buttons are drawn as in the front window.
private final class KeyWindow: NSWindow { override var canBecomeKey: Bool { true } }

@MainActor
enum ReadmeShots {
    static func run(_ base: String) {
        _ = NSApplication.shared
        for l in [Lang.ru, Lang.en] { Lang.current = l; one(base.appending(path: l.rawValue)) }
    }

    static func render(_ v: some View, size: CGSize, to path: String) {
        let host = NSHostingView(rootView: v.environment(\.colorScheme, .dark))
        host.frame = CGRect(origin: .zero, size: size)
        let win = KeyWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        NSApp.setActivationPolicy(.accessory)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)   // an active app draws switches and selections in their colours
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    static func one(_ dir: String) {
        let m = AppModel()
        m.mode = .real
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func shot(_ name: String, _ step: AppModel.Step, _ content: some View) {
            m.step = step
            let v = ZStack {
                SkyBackground()
                HStack(spacing: 0) {
                    SidebarView().frame(width: 248)
                    Divider().overlay(Theme.line)
                    ScrollView { content.frame(maxWidth: 860).padding(.horizontal, 40).padding(.top, 44).padding(.bottom, 30) }.frame(maxWidth: .infinity)
                }
            }
            .environmentObject(m)
            render(v, size: CGSize(width: 1180, height: 780), to: dir.appending(path: "\(name).png"))
        }
        render(ZStack { SkyBackground(); WelcomeView(showDemo: false) }.environmentObject(m), size: CGSize(width: 1180, height: 640), to: dir.appending(path: "welcome.png"))

        var d = Device(serial: "ZF62S153EYMW", hwSerial: "ZF62S153EYMW", transport: .usb, state: "device")
        d.match = Match(id: "z9x", by: .model, detail: L("по модели %@", "G0082")); d.system = L("родная система XGIMI"); d.firmware = "v6.15.58"; d.firmwareOk = true
        m.devices = [d]; m.selectedDeviceID = d.id
        shot("prepare", .prepare, PrepareStepView())
        shot("projector", .device, DeviceStepView())
        m.releases = [Release(tag: "z9x-1.0.9", title: "", prerelease: false, published: Date(), device: "z9x", version: "1.0.9", installer: nil,
                              images: [Asset(name: "lumen-os-1.0.9-nogms-system.img", size: 990035968, url: "")], sums: nil, sig: nil),
                      Release(tag: "z9x-1.0.8", title: "", prerelease: false, published: Date().addingTimeInterval(-86400 * 2), device: "z9x", version: "1.0.8", installer: nil,
                              images: [Asset(name: "lumen-os-1.0.8-nogms-system.img", size: 989626368, url: "")], sums: nil, sig: nil)]
        m.selectedReleaseTag = "z9x-1.0.9"
        // a release installer with erofs-utils, as 1.0.9 has: Google services go on together with the system
        let inst = NSTemporaryDirectory().appending(path: "readme-installer")
        try? FileManager.default.createDirectory(atPath: inst.appending(path: "tools/erofs-utils/darwin"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: inst.appending(path: "tools/erofs-utils/darwin/mkfs.erofs"), contents: Data())
        m.workspace = Workspace(dir: "~/Lumen Installer/releases/z9x-1.0.9", installerDir: inst, image: "~/Lumen Installer/releases/z9x-1.0.9/lumen-os-1.0.9-nogms-system.img", tag: "z9x-1.0.9", device: "z9x")
        shot("system", .system, SystemStepView())
        m.gappsEnabled = true; m.gappsOK = true; m.gappsFile = "/x/MindTheGapps-14.0.0-arm64-ATV-full-20240523_192016.zip"
        m.gappsState = L("Файл подходит: %@, sha256 совпадает.", "MindTheGapps-14.0.0-arm64-ATV-full-20240523_192016.zip")
        shot("google", .google, GoogleStepView())
        shot("install", .install, InstallStepView())
        m.runTitle = L("Установка Lumen OS с сервисами Google"); var o = RunOptions(); o.gappsZip = m.gappsFile; m.lastOptions = o
        m.state = ["step_check": "done", "step_backup": "done", "step_blobs": "done", "step_vbmeta": "done", "step_flash": "done", "step_verify": "skipped:wiped"]
        m.log = [LogLine(text: "$ bash lumen-install.sh --lang \(Lang.current.installer) --serial ZF62S153EYMW --image …/lumen-os-1.0.9-nogms-system.img --gapps-zip …/MindTheGapps-14.0.0-arm64-ATV-full-20240523_192016.zip", kind: .cmd),
                 LogLine(text: "14:02:11   ✓ Platform-Tools 35.0.2", kind: .ok),
                 LogLine(text: "14:02:12   ✓ XGIMI Z9X ZF62S153EYMW, v6.15.58", kind: .ok),
                 LogLine(text: "14:02:12   ✓ SHA256SUMS: Lumen OS", kind: .ok),
                 LogLine(text: "14:04:40   ✓ " + (Lang.current == .ru ? "записано" : "written"), kind: .ok)]
        m.exitCode = 0; m.installDone = true
        shot("done", .install, InstallStepView())
    }
}
