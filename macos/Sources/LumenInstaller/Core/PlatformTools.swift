import Foundation

/// adb and fastboot for finding the projector: Google's Platform-Tools in the version and with the sha256 the
/// installer pins (read from the installer script, never typed twice), on the installer's own adb server port
/// 5038 so other adb servers on the computer never get in the way.
final class PlatformTools {
    static let adbPort = "5038"
    private(set) var dir: String?
    private(set) var env: [String: String] = [:]
    private(set) var zipPath: String?
    private var realDir: String?

    struct Pin { let ver, sha, zip, url: String }

    static func pinned() throws -> Pin {
        let sh = try String(contentsOfFile: Paths.bundledInstaller.appending(path: "lumen-install.sh"), encoding: .utf8)
        guard let v = firstMatch(#"(?m)^PT_VER=(\S+)"#, in: sh)?[1],
              let s = firstMatch(#"(?m)^PT_SHA_darwin=([0-9a-f]{64})"#, in: sh)?[1] else { throw AppError(L("в установщике нет версии Platform-Tools")) }
        let zip = "platform-tools_r\(v)-darwin.zip"
        return Pin(ver: v, sha: s, zip: zip, url: "https://dl.google.com/android/repository/\(zip)")
    }

    func useSimulator(bin: String, env: [String: String]) { dir = bin; self.env = env }
    func useReal() { env = [:]; dir = realDir }

    func ensure(progress: @escaping (Int64, Int64) -> Void) async throws {
        let pin = try Self.pinned()
        let base = Paths.support.appending(path: "platform-tools")
        let zip = base.appending(path: pin.zip)
        let out = base.appending(path: "platform-tools")
        let marker = out.appending(path: ".lumen-client")
        let fm = FileManager.default
        if (try? String(contentsOfFile: marker, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) == pin.sha, fm.exists(zip) {
            dir = out; realDir = out; zipPath = zip; return
        }
        if try !fm.exists(zip) || Shell.sha256(file: zip) != pin.sha {
            try await Net.download(pin.url, to: zip, progress: progress)
            let got = try Shell.sha256(file: zip)
            guard got == pin.sha else {
                try? fm.removeItem(atPath: zip)
                throw AppError(L("скачанный %@ не совпадает с файлом Google (sha256 %@…)", "\(pin.zip)", "\(got.prefix(12))"))
            }
        }
        try? fm.removeItem(atPath: out)
        let r = await Shell.run("/usr/bin/ditto", ["-x", "-k", zip, base], timeout: 120)
        guard r.code == 0, fm.exists(out.appending(path: "adb")) else { throw AppError(L("не удалось распаковать Platform-Tools: %@", "\(r.stderr)")) }
        try pin.sha.write(toFile: marker, atomically: true, encoding: .utf8)
        dir = out; realDir = out; zipPath = zip
    }

    func adb(_ args: [String], timeout: TimeInterval = 8) async -> ProcResult {
        guard let dir else { return ProcResult(code: -1, stdout: "", stderr: L("adb ещё не готов")) }
        return await Shell.run(dir.appending(path: "adb"), args, env: env.merging(["ANDROID_ADB_SERVER_PORT": Self.adbPort, "ADB_SERVER_SOCKET": ""]) { $1 }, timeout: timeout)
    }

    func fastboot(_ args: [String], timeout: TimeInterval = 8) async -> ProcResult {
        guard let dir else { return ProcResult(code: -1, stdout: "", stderr: L("fastboot ещё не готов")) }
        return await Shell.run(dir.appending(path: "fastboot"), args, env: env, timeout: timeout)
    }

    func killServer() async { if dir != nil { _ = await adb(["kill-server"], timeout: 5) } }
}
