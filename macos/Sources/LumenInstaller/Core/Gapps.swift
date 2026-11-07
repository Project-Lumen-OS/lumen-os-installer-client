import Foundation

/// Google services add-on: the one MindTheGapps zip the installer accepts for each projector (lib/*gapps_allow.txt,
/// hashes only — no Google file ships with Lumen OS). The client fetches it from its official URL for the user and
/// checks it before the installer does, so a wrong file is caught before the projector is touched.
struct GappsZip: Hashable {
    let sha: String
    let name: String
    let size: Int64
    let gmsversion: String
    let url: String
}

enum Gapps {
    static func allowed(installerDir: String, rel: String?) -> GappsZip? {
        guard let rel, let text = try? String(contentsOfFile: installerDir.appending(path: rel), encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            if let m = firstMatch(#"^zip=([0-9a-f]{64}) (\S+) size=(\d+) .*?gmsversion=(\S+) url=(\S+)"#, in: String(line)) {
                return GappsZip(sha: m[1], name: m[2], size: Int64(m[3]) ?? 0, gmsversion: m[4], url: m[5])
            }
        }
        return nil
    }

    static func localCopy(_ z: GappsZip) -> String { Paths.google.appending(path: z.name) }

    /// nil when the file is the accepted zip, else the reason it is not.
    static func check(file: String, against z: GappsZip, progress: @escaping (Int64, Int64) -> Void) throws -> String? {
        let size = FileManager.default.size(file)
        if size != z.size { return L("другой размер файла (%@ байт, нужен %@): это не %@", "\(size)", "\(z.size)", "\(z.name)") }
        return try Shell.sha256(file: file, progress: progress) == z.sha ? nil : L("sha256 не совпадает: это не %@", "\(z.name)")
    }
}
