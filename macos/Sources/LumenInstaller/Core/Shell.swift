import Foundation
import CryptoKit

struct ProcResult {
    var code: Int32
    var stdout: String
    var stderr: String
    var all: String { stdout + stderr }
}

enum Shell {
    /// Runs a program with a time limit. Never throws: a program that cannot start returns code -1.
    static func run(_ exe: String, _ args: [String], env: [String: String] = [:], timeout: TimeInterval = 15, cwd: String? = nil) async -> ProcResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                // an empty value removes the variable (ADB_SERVER_SOCKET="" would break adb)
                p.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }.filter { !$0.value.isEmpty }
                if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                p.standardInput = FileHandle.nullDevice
                var outData = Data(), errData = Data()
                let group = DispatchGroup()
                group.enter(); group.enter()
                DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                do { try p.run() } catch {
                    cont.resume(returning: ProcResult(code: -1, stdout: "", stderr: "\(error)"))
                    return
                }
                let timer = DispatchWorkItem { if p.isRunning { p.terminate(); kill(p.processIdentifier, SIGKILL) } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                p.waitUntilExit()
                timer.cancel()
                group.wait()
                cont.resume(returning: ProcResult(code: p.terminationStatus,
                                                  stdout: String(decoding: outData, as: UTF8.self),
                                                  stderr: String(decoding: errData, as: UTF8.self)))
            }
        }
    }

    static func sha256(file: String, progress: ((Int64, Int64) -> Void)? = nil) throws -> String {
        guard let h = FileHandle(forReadingAtPath: file) else { throw AppError(L("не удаётся открыть %@", "\(file)")) }
        defer { try? h.close() }
        let total = (try? FileManager.default.attributesOfItem(atPath: file)[.size] as? Int64) ?? 0
        var hasher = SHA256()
        var seen: Int64 = 0
        while true {
            let chunk = h.readData(ofLength: 4 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            seen += Int64(chunk.count)
            progress?(seen, total)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct AppError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

extension FileManager {
    func exists(_ p: String) -> Bool { fileExists(atPath: p) }
    func size(_ p: String) -> Int64 { (try? attributesOfItem(atPath: p)[.size] as? Int64) ?? -1 }
}

extension String {
    func appending(path p: String) -> String { (self as NSString).appendingPathComponent(p) }
    var lastPath: String { (self as NSString).lastPathComponent }
    var parentPath: String { (self as NSString).deletingLastPathComponent }
}

func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options),
          let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    return (0..<m.numberOfRanges).map { i in
        guard let r = Range(m.range(at: i), in: text) else { return "" }
        return String(text[r])
    }
}
