import Foundation

struct LogLine: Identifiable {
    enum Kind { case cmd, info, ok, warn, stop, answer }
    let id = UUID()
    let text: String
    let kind: Kind
}

struct Prompt: Identifiable {
    enum Kind: Equatable { case yesNo, word(String), enter, text }
    let id = UUID()
    let question: String
    let context: [String]
    let kind: Kind
}

struct RunOptions {
    var command: String? = nil
    var device = "z9x"
    var serial: String? = nil
    var ip: String? = nil
    var image: String? = nil
    var gappsZip: String? = nil
    var zip: String? = nil
    var remove = false
    var keepData = false
    var noBlobs = false
    var lang = "ru"

    var args: [String] {
        var a = ["--lang", lang]
        if device != "z9x" { a += ["--device", device] }
        if let ip { a += ["--ip", ip] }
        if let serial { a += ["--serial", serial] }
        if let image { a += ["--image", image] }
        if let gappsZip { a += ["--gapps-zip", gappsZip] }
        if let zip { a += ["--zip", zip] }
        if remove { a.append("--remove") }
        if keepData { a.append("--keep-data") }
        if noBlobs { a.append("--no-blobs") }
        if let command { a.append(command) }
        return a
    }
}

/// Runs lumen-install.sh and turns its terminal dialogue into lines and questions (yes/no, or a word to type such as
/// ERASE). Answers go to its stdin exactly as typed; the script alone decides what is written to the projector.
final class InstallerRunner {
    var onLine: ((LogLine) -> Void)?
    var onPrompt: ((Prompt) -> Void)?
    var onPromptGone: (() -> Void)?   // the "question" was output that went on (fastboot's progress), not a question
    var onExit: ((Int32) -> Void)?

    private var proc: Process?
    private var stdin: FileHandle?
    private var partial = ""
    private var context: [String] = []
    private var idle: DispatchWorkItem?
    private var asking = false
    private let q = DispatchQueue(label: "runner")

    var running: Bool { proc?.isRunning ?? false }

    func start(installerDir: String, options: RunOptions, env: [String: String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [installerDir.appending(path: "lumen-install.sh")] + options.args
        p.currentDirectoryURL = URL(fileURLWithPath: installerDir)
        p.environment = ProcessInfo.processInfo.environment.merging(env.merging(["LANG": "ru_RU.UTF-8", "LC_ALL": ""]) { $1 }) { $1 }
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardError = out
        p.standardInput = inp
        stdin = inp.fileHandleForWriting
        partial = ""; context = []
        emit(LogLine(text: "$ bash lumen-install.sh " + options.args.joined(separator: " "), kind: .cmd))
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard let self, !d.isEmpty else { return }
            self.q.async { self.feed(String(decoding: d, as: UTF8.self)) }
        }
        p.terminationHandler = { [weak self] p in
            guard let self else { return }
            out.fileHandleForReading.readabilityHandler = nil
            let rest = out.fileHandleForReading.readDataToEndOfFile()
            self.q.async {
                if !rest.isEmpty { self.feed(String(decoding: rest, as: UTF8.self)) }
                self.idle?.cancel()
                if !self.partial.isEmpty { self.line(self.partial); self.partial = "" }
                let code = p.terminationStatus
                DispatchQueue.main.async { self.proc = nil; self.onExit?(code) }
            }
        }
        try p.run()
        proc = p
    }

    private func feed(_ s: String) {
        idle?.cancel()
        if asking { asking = false; DispatchQueue.main.async { self.onPromptGone?() } }
        var parts = (partial + s.replacingOccurrences(of: "\r\n", with: "\n")).components(separatedBy: "\n")
        partial = parts.removeLast()
        parts.forEach(line)
        if !partial.isEmpty {
            let w = DispatchWorkItem { [weak self] in self?.promptNow() }
            idle = w
            q.asyncAfter(deadline: .now() + 0.3, execute: w)
        }
    }

    private func line(_ text: String) {
        let body = text.replacingOccurrences(of: #"^\d\d:\d\d:\d\d\s+"#, with: "", options: .regularExpression)
        var kind = LogLine.Kind.info
        if body.hasPrefix("✓") { kind = .ok } else if body.hasPrefix("! ") { kind = .warn }
        if body.hasPrefix("СТОП:") || body.hasPrefix("STOP:") { kind = .stop }
        if text.trimmingCharacters(in: .whitespaces).isEmpty { context = [] } else { context.append(text) }
        if context.count > 14 { context.removeFirst() }
        emit(LogLine(text: text, kind: kind))
    }

    private func promptNow() {
        guard !partial.isEmpty, running else { return }
        let qtext = partial.trimmingCharacters(in: .whitespaces)
        // only the installer's own questions: [yes/no], "Type ERASE", "press Enter", "Type this serial ...:".
        // Anything else without a newline is output still running (fastboot's "Sending sparse ... 3/4").
        let kind: Prompt.Kind
        if firstMatch(#"\[(yes/no|да/нет)\]\s*:?\s*$"#, in: qtext) != nil { kind = .yesNo }
        else if let m = firstMatch(#"(?:Type|Введите)\s+([A-Z]{3,})\b"#, in: qtext) { kind = .word(m[1]) }
        else if firstMatch(#"(?:press|нажмите) Enter\.?\s*$"#, in: qtext, options: .caseInsensitive) != nil { kind = .enter }
        else if firstMatch(#"(?:Type|Введите)\b.*:\s*$"#, in: qtext) != nil { kind = .text }
        else { return }
        asking = true
        let p = Prompt(question: qtext, context: context, kind: kind)
        DispatchQueue.main.async { self.onPrompt?(p) }
    }

    func answer(_ text: String) {
        q.async {
            let shown = self.partial
            self.partial = ""; self.context = []; self.asking = false
            self.emit(LogLine(text: shown + text, kind: .answer))
            self.stdin?.write((text + "\n").data(using: .utf8)!)
        }
    }

    func stop() {
        guard let p = proc, p.isRunning else { return }
        kill(p.processIdentifier, SIGINT)
    }

    private func emit(_ l: LogLine) { DispatchQueue.main.async { self.onLine?(l) } }

    static func stateFile(device: String, root: String) -> String {
        device == "z9x" ? root.appending(path: "state") : root.appending(path: "\(device)/state")
    }

    static func readState(_ file: String) -> [String: String] {
        guard let s = try? String(contentsOfFile: file, encoding: .utf8) else { return [:] }
        var o: [String: String] = [:]
        for l in s.split(whereSeparator: \.isNewline) {
            if let i = l.firstIndex(of: "=") { o[String(l[..<i])] = String(l[l.index(after: i)...]) }
        }
        return o
    }
}
