import Foundation
import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Mode { case real, demo }
    enum Step: Int, CaseIterable { case prepare, device, system, google, install }

    // ---------------------------------------------------------------- general
    @Published var mode: Mode?
    @Published var lang: Lang = Lang.current {
        didSet { Lang.current = lang; UserDefaults.standard.set(lang.rawValue, forKey: "lang"); detector.clearCache() }
    }
    @Published var step: Step = .device {
        didSet {   // leaving a finished run: the install step opens on its summary again
            if oldValue == .install, step != .install, !running, waitingGapps == nil { exitCode = nil; log = []; installDone = false }
        }
    }
    @Published var busy: String?          // a blocking message (getting Platform-Tools, preparing the demo)
    @Published var busyProgress: Double?
    @Published var error: String?

    let pt = PlatformTools()
    // LUMEN_DEMO_ROOT: self-tests use their own demo projector, never the one of an open window
    let sim = ProcessInfo.processInfo.environment["LUMEN_DEMO_ROOT"].map { Simulator(root: $0) } ?? Simulator()
    lazy var detector = Detector(pt: pt)
    let runner = InstallerRunner()
    @Published var profiles: [Profile] = Profiles.load(installerDir: Paths.bundledInstaller)

    // ---------------------------------------------------------------- step 1: the projector
    @Published var devices: [Device] = []
    @Published var scanError: String?
    @Published var selectedDeviceID: String?
    @Published var manualProfileID: String?
    @Published var serialInput = ""
    @Published var serialMatch: Match?
    @Published var serialTried = false
    @Published var wifiAddr = ""
    @Published var wifiMessage: String?
    @Published var simStatus: Simulator.Status?
    private var pollTask: Task<Void, Never>?

    var selectedDevice: Device? { devices.first { $0.id == selectedDeviceID } }
    var profile: Profile? {
        let id = selectedDevice?.match?.id ?? manualProfileID
        return profiles.first { $0.id == id }
    }

    // ---------------------------------------------------------------- step 2: the system
    @Published var releases: [Release] = []
    @Published var releasesLoading = false
    @Published var releasesError: String?
    @Published var showBeta = false
    @Published var selectedReleaseTag: String?
    @Published var workspace: Workspace?
    @Published var downloadFile: String?
    @Published var downloadProgress: Double?
    private var downloadTask: Task<Void, Never>?

    var deviceReleases: [Release] { releases.filter { $0.device == profile?.id && (showBeta || !$0.prerelease || $0.demo) } }
    var selectedRelease: Release? { releases.first { $0.tag == selectedReleaseTag } }

    // ---------------------------------------------------------------- step 3: Google
    @Published var gappsEnabled = false
    @Published var gappsFile: String?
    @Published var gappsState: String?
    @Published var gappsOK = false
    @Published var gappsProgress: Double?
    @Published var gappsPhase = ""
    var gappsZip: GappsZip? {
        guard let p = profile else { return nil }
        return workspace.flatMap { Gapps.allowed(installerDir: $0.installerDir, rel: p.gappsAllow) }
            ?? Gapps.allowed(installerDir: Paths.bundledInstaller, rel: p.gappsAllow)
    }

    // ---------------------------------------------------------------- step 4: install
    @Published var log: [LogLine] = []
    @Published var prompt: Prompt?
    @Published var running = false
    @Published var exitCode: Int32?
    @Published var runTitle = ""
    @Published var state: [String: String] = [:]
    @Published var startedSteps: [String] = []
    private var stateTimer: Timer?

    init() {
        runner.onLine = { [weak self] l in self?.log.append(l) }
        runner.onPrompt = { [weak self] p in
            guard let self else { return }
            // the installer's "have you done the vbmeta step?": the client did it in this session, both slots confirmed
            // by fastboot and the result read back; the installer still checks it on its own before writing
            if vbmetaDoneHere, p.kind == .yesNo, p.question.contains("vbmeta") { answer(lang.installer == "ru" ? "да" : "yes"); return }
            prompt = p
        }
        runner.onPromptGone = { [weak self] in self?.prompt = nil }
        runner.onExit = { [weak self] code in
            guard let self else { return }
            running = false; exitCode = code; prompt = nil
            refreshState(); stateTimer?.invalidate()
            detector.clearCache()
            chainSkipped = code != 0 && chainGapps != nil
            if inGappsChain { inGappsChain = false; gappsChainResult = code }
            else if code == 0, let zip = chainGapps {   // step 2 of 2: Google services on the fresh Lumen OS
                // the wipe turned USB debugging off: 'gapps' starts once the projector is back on adb (pollOnce)
                chainGapps = nil
                waitingGapps = zip
                Task { await self.pollOnce() }
            } else { chainGapps = nil }
            // the system is on the projector: the step is green while its result is on screen
            if isInstallRun, waitingGapps == nil, code == 0 || writtenButUnchecked { installDone = true }
        }
    }

    // ---------------------------------------------------------------- mode
    func choose(_ m: Mode) {
        Task {
            do {
                pollTask?.cancel()
                await pt.killServer()
                detector.clearCache()
                devices = []; selectedDeviceID = nil; workspace = nil; releases = []; selectedReleaseTag = nil
                if m == .demo {
                    busy = L("Готовлю демо-проектор…"); busyProgress = nil
                    let ws = try await sim.setup()
                    pt.useSimulator(bin: sim.bin, env: sim.env)
                    profiles = Profiles.load(installerDir: ws.installerDir)
                    releases = [Release(tag: ws.tag, title: L("Lumen OS %@ (демо)", "\(Simulator.version)"), prerelease: false, published: Date(),
                                        device: "z9x", version: Simulator.version, installer: nil,
                                        images: [Asset(name: ws.image.lastPath, size: FileManager.default.size(ws.image), url: "")],
                                        sums: nil, sig: nil, demo: true)]
                    demoWorkspace = ws
                } else {
                    busy = L("Скачиваю Android Platform-Tools (adb и fastboot)…")
                    pt.useReal()
                    try await pt.ensure { [weak self] done, total in
                        Task { @MainActor in self?.busyProgress = total > 0 ? Double(done) / Double(total) : nil }
                    }
                    profiles = Profiles.load(installerDir: Paths.bundledInstaller)
                }
                busy = nil; busyProgress = nil
                mode = m; step = m == .demo ? .device : .prepare
                startPolling()
            } catch {
                busy = nil
                self.error = error.localizedDescription
            }
        }
    }
    private var demoWorkspace: Workspace?

    func leaveMode() {
        pollTask?.cancel()
        runner.stop()
        mode = nil
        log = []; exitCode = nil; state = [:]; gappsEnabled = false; gappsFile = nil; gappsOK = false; gappsState = nil
        manualProfileID = nil; serialInput = ""; serialMatch = nil; serialTried = false
        vbmetaTask?.cancel(); vbmetaState = nil; vbmetaDoneHere = false; installDone = false
    }

    // ---------------------------------------------------------------- polling
    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private var scanning = false

    func pollOnce() async {
        if mode == .demo { simStatus = sim.status() }
        guard !running, !scanning else { return }
        scanning = true
        defer { scanning = false }
        do {
            let found = try await detector.scan(profiles: profiles)
            devices = found
            scanError = nil
            if selectedDeviceID == nil || !found.contains(where: { $0.id == selectedDeviceID }) {
                if let d = found.first(where: { $0.match != nil }) { selectedDeviceID = d.id }
            }
        } catch { scanError = error.localizedDescription }
        if let zip = waitingGapps, let d = selectedDevice, d.state == "device", d.lumen {
            waitingGapps = nil
            startGappsChain(zip)
        }
    }

    func setCable(_ on: Bool) { sim.setCable(on); detector.clearCache(); Task { await pollOnce() } }
    func resetDemoProjector() {
        sim.resetProjector(); detector.clearCache(); log = []; exitCode = nil; state = [:]; vbmetaDoneHere = false
        Task { await pollOnce(); await refreshVbmeta() }
    }

    func connectWifi() {
        let addr = wifiAddr.trimmingCharacters(in: .whitespaces)
        guard !addr.isEmpty else { return }
        wifiMessage = L("Подключаюсь к %@…", "\(addr)")
        Task {
            let r = await detector.connect(addr)
            wifiMessage = r.ok ? L("Подключено. Если на проекторе появился запрос ADB, разрешите его.") : L("Не удалось: %@", "\(r.text)")
            await pollOnce()
        }
    }

    func findOnNetwork() {
        wifiMessage = L("Ищу проекторы в сети…")
        Task {
            let list = await detector.mdns()
            if let first = list.first { wifiAddr = first.addr; wifiMessage = L("Найдено: %@", "\(list.map { $0.addr }.joined(separator: ", "))") }
            else { wifiMessage = L("В сети ничего не найдено. Введите адрес вручную (на проекторе: Настройки → Сеть).") }
        }
    }

    func identifySerial() {
        serialTried = true
        let s = serialInput.trimmingCharacters(in: .whitespaces).uppercased()
        // the serial of a projector that is already connected: that projector
        if let d = devices.first(where: { $0.hwSerial?.uppercased() == s && $0.match != nil }), let id = d.match?.id {
            serialMatch = Match(id: id, by: .serial, detail: L("подключённый проектор"))
            select(d)
            return
        }
        serialMatch = Profiles.identify(profiles, serial: s)
        if let m = serialMatch { manualProfileID = m.id; selectedDeviceID = nil }
    }

    /// A new serial typed: the result shown belongs to the previous one.
    func serialEdited() { serialTried = false; serialMatch = nil }

    func chooseManually(_ id: String) { manualProfileID = id; selectedDeviceID = nil }
    func select(_ d: Device) { selectedDeviceID = d.id; if d.match != nil { manualProfileID = nil } }

    // ---------------------------------------------------------------- releases
    func loadReleases() {
        guard mode == .real, !releasesLoading else { return }
        releasesLoading = true; releasesError = nil
        Task {
            do { releases = try await Releases.list() } catch { releasesError = error.localizedDescription }
            releasesLoading = false
            autoselectRelease()
        }
    }

    func autoselectRelease() {
        if selectedRelease?.device != profile?.id {
            // a release already on disk wins over a newer one that is not, so nothing is downloaded unasked
            selectedReleaseTag = (deviceReleases.first { Releases.isDownloaded($0) } ?? deviceReleases.first)?.tag
            workspace = nil
        }
        if workspace == nil, let r = selectedRelease, isReady(r) { prepareRelease() }
    }

    /// Nothing to download: the demo image, or every file already on disk. Such a release is used at once.
    func isReady(_ r: Release) -> Bool { r.demo || Releases.isDownloaded(r) }

    /// The one button of the step: use (or download) the selected release, then go on to Google services.
    func nextFromSystem() {
        if workspace != nil { step = .google; refreshGappsFile() } else { prepareRelease(advance: true) }
    }

    func selectRelease(_ r: Release) {
        guard downloadProgress == nil, r.tag != selectedReleaseTag || workspace == nil else { return }
        selectedReleaseTag = r.tag; workspace = nil
        if isReady(r) { prepareRelease() }
    }

    func prepareRelease(advance: Bool = false) {
        guard let rel = selectedRelease else { return }
        if rel.demo { workspace = demoWorkspace; if advance { nextFromSystem() }; return }
        guard let img = rel.preferredImage else { return }
        let have = Releases.isDownloaded(rel)   // already on disk: no download, no progress bar
        downloadTask = Task {
            do {
                if !have { downloadProgress = 0 }
                let ws = try await Releases.prepare(rel, image: img, ptZip: pt.zipPath) { [weak self] file, done, total in
                    if !have { Task { @MainActor in self?.downloadFile = file; self?.downloadProgress = Double(done) / Double(max(total, 1)) } }
                }
                workspace = ws
                profiles = Profiles.load(installerDir: ws.installerDir)
                if advance && have { nextFromSystem() }   // a download stays on this step: its result is shown
            } catch { if !(error is CancellationError) { releasesError = error.localizedDescription } }
            downloadProgress = nil; downloadFile = nil
        }
    }
    func cancelDownload() { downloadTask?.cancel(); downloadProgress = nil }

    func pickLocalRelease() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        p.message = L("Выберите папку распакованного релиза Lumen OS")
        guard p.runModal() == .OK, let url = p.url else { return }
        do { workspace = try Releases.local(url.path); selectedReleaseTag = nil } catch { releasesError = error.localizedDescription }
    }

    // ---------------------------------------------------------------- Google services
    func refreshGappsFile() {
        guard let z = gappsZip else { return }
        let local = Gapps.localCopy(z)
        if gappsFile == nil, FileManager.default.size(local) == z.size { verifyGapps(local) }
    }

    func downloadGapps() {
        guard let z = gappsZip else { return }
        Task {
            do {
                gappsPhase = L("Скачиваю %@", "\(z.name)"); gappsProgress = 0
                try await Net.download(z.url, to: Gapps.localCopy(z), size: z.size) { [weak self] d, t in
                    Task { @MainActor in self?.gappsProgress = Double(d) / Double(max(t, 1)) }
                }
                verifyGapps(Gapps.localCopy(z))
            } catch { gappsState = L("Не удалось скачать: %@", "\(error.localizedDescription)"); gappsProgress = nil }
        }
    }

    func pickGapps() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.zip]
        p.message = L("Файл MindTheGapps")
        guard p.runModal() == .OK, let url = p.url else { return }
        verifyGapps(url.path)
    }

    func verifyGapps(_ file: String) {
        guard let z = gappsZip else { return }
        gappsFile = file; gappsOK = false; gappsPhase = L("Проверяю sha256"); gappsProgress = 0
        Task.detached { [weak self] in
            let why: String?
            do {
                why = try Gapps.check(file: file, against: z) { d, t in Task { @MainActor in self?.gappsProgress = Double(d) / Double(max(t, 1)) } }
            } catch { why = error.localizedDescription }
            await MainActor.run {
                guard let self else { return }
                self.gappsProgress = nil
                self.gappsOK = why == nil
                self.gappsState = why ?? L("Файл подходит: %@, sha256 совпадает.", "\(z.name)")
            }
        }
    }

    // ---------------------------------------------------------------- running the installer
    var stateRoot: String { mode == .demo ? sim.env["LUMEN_STATE_DIR"]! : Paths.stateDir }

    func baseOptions() -> RunOptions {
        var o = RunOptions()
        guard let p = profile else { return o }
        o.device = p.id
        if let d = selectedDevice {
            if d.transport == .wifi { o.ip = d.serial } else if p.connection == .usb { o.serial = d.serial }
        } else if p.connection == .wifi, !wifiAddr.isEmpty {
            o.ip = wifiAddr
        }
        if let ws = workspace { o.image = ws.image }
        if mode == .demo { o.noBlobs = true }
        o.lang = lang.installer
        return o
    }

    // ---------------------------------------------------------------- how Google services go on
    /// How the add-on gets onto this projector with this installer:
    /// - onePass: --gapps-zip in the install itself (one data wipe). The Play 6 always can; the Z9X and the Z9X HB
    ///   build the add-on image on this computer and need tools/erofs-utils in the installer (published downloads
    ///   do not have it as of 1.0.8);
    /// - afterInstall: the install, then 'gapps --zip' right after it (the Z9X fills the partition over adb, no erofs);
    /// - unavailable: the Z9X HB without erofs-utils needs them for 'gapps' too.
    enum GappsPlan: Equatable { case onePass, afterInstall, unavailable(String) }

    var erofsAvailable: Bool {
        guard let ws = workspace ?? demoWorkspace else { return false }
        return FileManager.default.exists(ws.installerDir.appending(path: "tools/erofs-utils/darwin/mkfs.erofs"))
    }

    var gappsPlan: GappsPlan {
        switch profile?.id {
        case "play6": return .onePass
        case "hb": return erofsAvailable ? .onePass : .unavailable(L("Для Z9X HB нужен установщик с erofs-utils, в этом его нет. Поставьте Lumen OS без Google."))
        default: return erofsAvailable ? .onePass : .afterInstall
        }
    }

    /// The Google services will go on in this run (demo: never, the demo projector cannot build the add-on).
    var gappsWillInstall: Bool {
        if case .unavailable = gappsPlan { return false }
        return (mode == .real || testGappsInDemo) && gappsEnabled && gappsOK
    }

    /// A projector is connected right now (adb or fastboot), not only chosen by serial or from the list.
    var deviceConnected: Bool {
        guard let d = selectedDevice else { return false }
        return d.state == "device" || d.state == "fastboot"
    }

    var canInstall: Bool {
        guard profile != nil, workspace != nil, !running, deviceConnected else { return false }
        if mode == .real && gappsEnabled { if case .unavailable = gappsPlan { return false }; return gappsOK }
        return true
    }

    var testGappsInDemo = false                 // --selftest-chain only
    @Published var chainGapps: String?          // the zip for 'gapps --zip' after a successful install
    @Published var waitingGapps: String?        // the install is done; 'gapps --zip' waits for Lumen OS on adb
    func skipWaitingGapps() { waitingGapps = nil }
    @Published var inGappsChain = false
    @Published var gappsChainResult: Int32?
    @Published var lastOptions: RunOptions?
    @Published var installDone = false          // the install just finished: green step while its result is on screen
    @Published var chainSkipped = false         // the install stopped, so 'gapps --zip' after it did not run

    /// The install stopped after the system was written: in this run the installer said "written" (its own line), and
    /// only the check after the first start failed. On a fresh Lumen OS that is expected: the wipe turned USB debugging
    /// off until the setup on the projector is done.
    var writtenButUnchecked: Bool {
        guard let c = exitCode, c != 0, isInstallRun, !inGappsChain, gappsChainResult == nil else { return false }
        return log.contains { l in
            guard l.kind == .ok else { return false }
            let b = l.text.replacingOccurrences(of: #"^\d\d:\d\d:\d\d\s+"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            return b.hasPrefix("✓ written") || b.hasPrefix("✓ записано")
        }
    }

    var isInstallRun: Bool { lastOptions != nil && (lastOptions?.command == nil || inGappsChain || gappsChainResult != nil) }

    func startInstall(keepLog: Bool = false) {
        installDone = false
        var o = baseOptions()
        chainGapps = nil; gappsChainResult = nil; inGappsChain = false; waitingGapps = nil
        if gappsWillInstall, let f = gappsFile {
            if gappsPlan == .onePass { o.gappsZip = f } else { chainGapps = f }
        }
        run(o, title: o.gappsZip != nil ? L("Установка Lumen OS с сервисами Google") : chainGapps != nil ? L("Установка Lumen OS и сервисов Google") : L("Установка Lumen OS"), keepLog: keepLog)
    }

    private func startGappsChain(_ zip: String) {
        var o = baseOptions()
        o.command = "gapps"; o.zip = zip
        inGappsChain = true
        log.append(LogLine(text: "", kind: .info))
        log.append(LogLine(text: L("──────── шаг 2 из 2: сервисы Google ────────"), kind: .cmd))
        run(o, title: runTitle, keepLog: true)
    }

    func runCommand(_ cmd: String, title: String, zip: String? = nil, remove: Bool = false) {
        var o = baseOptions()
        o.command = cmd; o.zip = zip; o.remove = remove
        step = .install
        chainGapps = nil; inGappsChain = false; gappsChainResult = nil; waitingGapps = nil
        run(o, title: title)
    }

    private func run(_ o: RunOptions, title: String, keepLog: Bool = false) {
        guard let ws = workspace ?? demoWorkspace, !running else { return }
        if !keepLog { log = []; state = [:] }
        exitCode = nil; prompt = nil; runTitle = title; lastOptions = o
        do {
            try runner.start(installerDir: ws.installerDir, options: o, env: mode == .demo ? sim.env : [:])
            running = true
            stateTimer?.invalidate()
            stateTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in Task { @MainActor in self?.refreshState() } }
            refreshState()
        } catch { self.error = error.localizedDescription }
    }

    func refreshState() {
        guard let p = profile else { return }
        let s = InstallerRunner.readState(InstallerRunner.stateFile(device: p.id, root: stateRoot))
        if s != state { state = s }
    }

    func answer(_ text: String) { prompt = nil; runner.answer(text) }
    func stop() { vbmetaTask?.cancel(); runner.stop() }

    // ---------------------------------------------------------------- the vbmeta step (Z9X, Z9X HB)
    @Published var vbmetaState: Vbmeta.State?
    @Published var vbmetaAsk = false
    @Published var vbmetaRunning = false
    private var vbmetaDoneHere = false
    private var vbmetaTask: Task<Void, Never>?

    var needsVbmeta: Bool { profile?.id == "z9x" || profile?.id == "hb" }

    /// Reads, without writing, whether the running slot still verifies the system (as the installer does).
    func refreshVbmeta() async {
        guard needsVbmeta, let d = selectedDevice, d.state == "device", let p = profile, !running else { vbmetaState = nil; return }
        vbmetaState = await Vbmeta.state(pt: pt, serial: d.serial, device: p.id)
    }

    /// "Start the install": on a projector that still verifies its system the client asks to do the vbmeta step first.
    func beginInstall() {
        if needsVbmeta && vbmetaState == .on { vbmetaAsk = true } else { startInstall() }
    }

    func runVbmeta(thenInstall: Bool) {
        guard let d = selectedDevice, let p = profile, !running else { return }
        log = []; state = [:]; exitCode = nil; prompt = nil; lastOptions = nil
        chainGapps = nil; inGappsChain = false; gappsChainResult = nil; waitingGapps = nil
        runTitle = L("Шаг vbmeta"); running = true; vbmetaRunning = true
        let add: (String, LogLine.Kind) -> Void = { [weak self] t, k in Task { @MainActor in self?.log.append(LogLine(text: t, kind: k)) } }
        let ip = d.transport == .wifi ? d.serial : nil
        vbmetaTask = Task {
            var ok = false
            do {
                let img: String
                if mode == .demo {
                    img = sim.env["LUMEN_STATE_DIR"]!.parentPath.appending(path: "vbmeta.img")
                    FileManager.default.createFile(atPath: img, contents: Data(count: Vbmeta.size))
                    add(L("демо: vbmeta.img не скачивается, демо-проектору он не нужен"), .info)
                } else {
                    img = try await Vbmeta.fetch()
                    add(L("✓ vbmeta.img Google (Android 14 GSI, sha256 %@…)", "\(Vbmeta.sha.prefix(12))"), .ok)
                }
                try await Vbmeta.run(pt: pt, image: img, serial: d.serial, hwSerial: d.hwSerial, ip: ip, device: p.id, log: add)
                ok = true
            } catch is CancellationError {
                add(L("СТОП: шаг vbmeta остановлен"), .stop)
            } catch {
                add(L("СТОП: %@", "\(error.localizedDescription)"), .stop)
            }
            await Task.yield()
            running = false; vbmetaRunning = false
            detector.clearCache()
            await pollOnce()
            if ok {
                vbmetaDoneHere = true; vbmetaState = .off
                if thenInstall {
                    log.append(LogLine(text: "", kind: .info))
                    startInstall(keepLog: true)
                    return
                }
                exitCode = 0
            } else {
                exitCode = 1
                await refreshVbmeta()
            }
        }
    }

    /// Why a step of the pipeline did not run, or nil.
    func skipNote(_ key: String) -> String? {
        // skipped:wiped (installers after 1.0.9): no check after a wipe, USB debugging is off on the fresh system
        if state["step_\(key)"] == "skipped" { return key == "backup" ? L("вы отказались от копии") : L("пропущено") }
        if key == "blobs", lastOptions?.noBlobs == true, state["step_blobs"] == nil {
            return mode == .demo ? L("в демо не нужны (--no-blobs)") : L("без кодеков (--no-blobs)")
        }
        return nil
    }

    /// The pipeline shown for an install: the installer's steps, plus the Google step when it runs after the install.
    var installPipeline: [(key: String, title: String)] {
        pipeline + ((chainGapps != nil || waitingGapps != nil || inGappsChain || gappsChainResult != nil) ? [("gapps", L("Сервисы Google"))] : [])
    }

    /// The installer's own steps for this projector, in order (lumen-install.sh, "Commands").
    var pipeline: [(key: String, title: String)] {
        switch profile?.id {
        case "play6": return [("check", L("Проверка")), ("backup", L("Копия")), ("flash", L("Запись")), ("verify", L("Проверка после запуска"))]
        case "hb": return [("check", L("Проверка")), ("backup", L("Копия")), ("vbmeta", "vbmeta"), ("blobs", L("Кодеки")), ("flash", L("Запись")), ("verify", L("После запуска"))]
        default: return [("check", L("Проверка")), ("backup", L("Копия")), ("blobs", L("Кодеки")), ("vbmeta", "vbmeta"), ("flash", L("Запись")), ("verify", L("После запуска"))]
        }
    }

    func openURL(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }
    func reveal(_ path: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
}
