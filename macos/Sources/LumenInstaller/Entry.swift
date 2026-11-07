import Foundation

@main
enum Entry {
    static func main() {
        #if LUMEN_DEV   // the developer build: self-tests and screenshots without a window
        if CommandLine.arguments.contains("--selftest") { SelfTest.run(); return }
        if CommandLine.arguments.contains("--selftest-net") { SelfTest.net(); return }
        if CommandLine.arguments.contains("--selftest-chain") { MainActor.assumeIsolated { SelfTest.chain() }; return }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshots"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated { Snapshots.run(CommandLine.arguments[i + 1]) }; return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--readme-shots"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated { ReadmeShots.run(CommandLine.arguments[i + 1]) }; return
        }
        #endif
        LumenInstallerApp.main()
    }
}

/// `--selftest`: the demo install without a window — demo projector, detection, the real lumen-install.sh with
/// the answers a user would give (no backup, vbmeta done, ERASE), after the client's own vbmeta step. Prints everything; exit status 0 on success.
enum SelfTest {
    /// `--selftest-chain`: the app model on the demo projector with Google services planned after the install: the
    /// install must succeed and then 'gapps --zip' must start by itself (a dummy zip, which the installer refuses).
    @MainActor static func chain() {
        let m = AppModel()
        m.choose(.demo)
        func spin(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
        while m.mode == nil { spin(0.1) }
        m.setCable(true)
        while m.selectedDevice == nil { spin(0.2) }
        m.selectedReleaseTag = m.releases.first?.tag; m.prepareRelease()
        let zip = NSTemporaryDirectory().appending(path: "dummy-gapps.zip")
        FileManager.default.createFile(atPath: zip, contents: Data("not google".utf8))
        m.testGappsInDemo = true; m.gappsEnabled = true; m.gappsOK = true; m.gappsFile = zip
        print("plan:", m.gappsPlan, "will:", m.gappsWillInstall)
        var answers = ["нет", "ERASE"]   // the vbmeta question is answered by the client after its own vbmeta step
        var printed = 0
        Task { await m.refreshVbmeta() }
        while m.vbmetaState == nil { spin(0.2) }
        print("vbmeta before:", m.vbmetaState!)
        m.beginInstall()
        guard m.vbmetaAsk else { print("FAIL: no vbmeta question"); exit(1) }
        m.runVbmeta(thenInstall: true)
        while m.vbmetaRunning { spin(0.2) }
        print("vbmeta after:", m.vbmetaState.map { "\($0)" } ?? "nil")
        print("title:", m.runTitle, "chain:", m.chainGapps ?? "-")
        let deadline = Date().addingTimeInterval(240)
        while Date() < deadline {
            spin(0.2)
            if let p = m.prompt { let a = answers.isEmpty ? "нет" : answers.removeFirst(); print("<<", p.question, "->", a); m.answer(a) }
            while printed < m.log.count { let l = m.log[printed]; if l.kind != .info || l.text.contains("gapps") || l.text.contains("zip") { print("[\(l.kind)]", l.text) }; printed += 1 }
            if !m.running && m.exitCode != nil && !m.inGappsChain && m.chainGapps == nil && m.gappsChainResult != nil { break }
        }
        print("pipeline:", m.installPipeline.map { "\($0.key)=\(m.skipNote($0.key) ?? m.state["step_\($0.key)"] ?? "-")" })
        print("chainResult:", m.gappsChainResult.map(String.init) ?? "nil", "exit:", m.exitCode.map(String.init) ?? "nil")
        exit(m.gappsChainResult != nil ? 0 : 1)
    }

    /// `--selftest-net`: the real mode's network side — Google's Platform-Tools (pinned sha256), Google's vbmeta.img
    /// (range fetch, pinned sha256), a real adb scan, the GitHub release list grouped by projector.
    static func net() {
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        Task {
            do {
                let pt = PlatformTools()
                try await pt.ensure { d, t in if d == t { print("platform-tools downloaded", d) } }
                print("platform-tools:", pt.dir ?? "-")
                try? FileManager.default.removeItem(atPath: Vbmeta.file)
                print("vbmeta.img:", try await Vbmeta.fetch(), try Shell.sha256(file: Vbmeta.file).prefix(16))
                try await Tuner.fetch { _, _ in }
                print("SystemUI Tuner:", Tuner.file, Tuner.ready)
                let profiles = Profiles.load(installerDir: Paths.bundledInstaller)
                let devs = try await Detector(pt: pt).scan(profiles: profiles)
                print("real devices:", devs.map { "\($0.serial) \($0.state) \($0.match?.detail ?? "-")" })
                await pt.killServer()
                let rels = try await Releases.list()
                for id in ["z9x", "play6", "hb"] {
                    let r = rels.filter { $0.device == id && !$0.prerelease }
                    print(id, "releases:", r.map(\.tag), "latest image:", r.first?.images.first?.name ?? "-", "on disk:", r.filter(Releases.isDownloaded).map(\.tag))
                }
                let z = Gapps.allowed(installerDir: Paths.bundledInstaller, rel: profiles.first?.gappsAllow)
                print("gapps z9x:", z?.name ?? "-", z?.size ?? 0)
                ok = true
            } catch { print("ERROR", error) }
            sem.signal()
        }
        while sem.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        exit(ok ? 0 : 1)
    }

    static func run() {
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        Task {
            do {
                let sim = Simulator(root: NSTemporaryDirectory().appending(path: "lumen-selftest"))
                let ws = try await sim.setup()
                let pt = PlatformTools(); pt.useSimulator(bin: sim.bin, env: sim.env)
                let profiles = Profiles.load(installerDir: ws.installerDir)
                let det = Detector(pt: pt)
                print("profiles:", profiles.map(\.id))
                print("no cable:", try await det.scan(profiles: profiles).count, "devices")
                sim.setCable(true)
                let devs = try await det.scan(profiles: profiles)
                for d in devs { print("found:", d.serial, d.transport, d.match?.detail ?? "-", d.system ?? "-", d.firmware ?? "-", d.firmwareOk.map(String.init) ?? "-") }
                print("serial XHN123:", Profiles.identify(profiles, serial: "XHN123")?.detail ?? "nil")
                print("serial ABC:", Profiles.identify(profiles, serial: "ABC")?.detail ?? "nil")
                let r = InstallerRunner()
                guard let dev = devs.first else { throw AppError("no device") }
                print("vbmeta before:", await Vbmeta.state(pt: pt, serial: dev.serial, device: "z9x"))
                let img = sim.env["LUMEN_STATE_DIR"]!.parentPath.appending(path: "vbmeta.img")
                FileManager.default.createFile(atPath: img, contents: Data(count: Vbmeta.size))
                try await Vbmeta.run(pt: pt, image: img, serial: dev.serial, hwSerial: dev.hwSerial, ip: nil, device: "z9x") { t, k in print("[\(k)] \(t)") }
                var answers = ["нет", "да", "ERASE"]
                r.onLine = { print("[\($0.kind)] \($0.text)") }
                r.onPrompt = { p in let a = answers.isEmpty ? "нет" : answers.removeFirst(); print("<<\(p.kind) \(p.question) -> \(a)>> context=\(p.context.count)"); r.answer(a) }
                r.onExit = { code in
                    print("EXIT", code, "state:", InstallerRunner.readState(InstallerRunner.stateFile(device: "z9x", root: sim.env["LUMEN_STATE_DIR"]!)))
                    print("sim:", String(describing: sim.status()))
                    ok = code == 0; sem.signal()
                }
                var o = RunOptions(); o.serial = devs.first?.serial; o.image = ws.image; o.noBlobs = true
                try r.start(installerDir: ws.installerDir, options: o, env: sim.env)
            } catch { print("ERROR", error); sem.signal() }
        }
        while sem.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        exit(ok ? 0 : 1)
    }
}
