import Foundation

struct Asset: Hashable { let name: String; let size: Int64; let url: String }

struct Release: Identifiable, Hashable {
    var id: String { tag }
    let tag: String
    let title: String
    let prerelease: Bool
    let published: Date?
    let device: String
    let version: String
    let installer: Asset?
    let images: [Asset]
    let sums: Asset?
    let sig: Asset?
    var demo = false

    /// The image the client installs: Lumen OS without Google (the services are a separate, optional step).
    var preferredImage: Asset? { images.first { $0.name.contains("nogms") } ?? images.first }
}

/// A release laid out on disk the way the install guide has it: the release files in one folder and the installer
/// in its installer/ subfolder. The client only checks sizes; signature and checksum are the installer's job.
struct Workspace: Hashable {
    let dir: String
    let installerDir: String
    let image: String
    let tag: String
    let device: String
}

enum Releases {
    static let repo = "Project-Lumen-OS/lumen-os"

    static func list() async throws -> [Release] {
        guard let arr = try await Net.json("https://api.github.com/repos/\(repo)/releases?per_page=60") as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        return arr.compactMap { r in
            let assets = (r["assets"] as? [[String: Any]] ?? []).compactMap { a -> Asset? in
                guard let n = a["name"] as? String, let s = a["size"] as? Int, let u = a["browser_download_url"] as? String else { return nil }
                return Asset(name: n, size: Int64(s), url: u)
            }
            guard let inst = assets.first(where: { firstMatch(#"^lumen-os-(?:(play6|hb)-)?(\d[\w.-]*?)-installer\.zip$"#, in: $0.name) != nil }),
                  let m = firstMatch(#"^lumen-os-(?:(play6|hb)-)?(\d[\w.-]*?)-installer\.zip$"#, in: inst.name) else { return nil }
            return Release(tag: r["tag_name"] as? String ?? "?", title: (r["name"] as? String) ?? "",
                           prerelease: r["prerelease"] as? Bool ?? false,
                           published: (r["published_at"] as? String).flatMap { iso.date(from: $0) },
                           device: m[1].isEmpty ? "z9x" : m[1], version: m[2], installer: inst,
                           images: assets.filter { $0.name.hasSuffix("-system.img") },
                           sums: assets.first { $0.name == "SHA256SUMS" }, sig: assets.first { $0.name == "SHA256SUMS.sig" })
        }
    }

    /// Every file of this release is already in ~/Lumen Installer/releases/<tag> with the size GitHub gives, and the
    /// installer is unpacked: nothing to download again (the installer checks signature and sha256 before writing).
    static func isDownloaded(_ rel: Release) -> Bool {
        guard !rel.demo, let img = rel.preferredImage, let inst = rel.installer, let sums = rel.sums, let sig = rel.sig else { return false }
        let dir = Paths.releases.appending(path: rel.tag), fm = FileManager.default
        return [inst, sums, sig, img].allSatisfy { fm.size(dir.appending(path: $0.name)) == $0.size }
            && fm.exists(dir.appending(path: "installer/lumen-install.sh"))
    }

    static func prepare(_ rel: Release, image: Asset, ptZip: String?, progress: @escaping (String, Int64, Int64) -> Void) async throws -> Workspace {
        guard let inst = rel.installer, let sums = rel.sums, let sig = rel.sig else { throw AppError(L("в релизе нет SHA256SUMS / SHA256SUMS.sig")) }
        let dir = Paths.releases.appending(path: rel.tag)
        let files = [inst, sums, sig, image]
        let total = files.reduce(0) { $0 + $1.size }
        var before: Int64 = 0
        for f in files {
            try Task.checkCancellation()
            let b = before
            try await Net.download(f.url, to: dir.appending(path: f.name), size: f.size) { done, _ in progress(f.name, b + done, total) }
            before += f.size
        }
        let r = await Shell.run("/usr/bin/ditto", ["-x", "-k", dir.appending(path: inst.name), dir], timeout: 60)
        guard r.code == 0 else { throw AppError(L("не удалось распаковать установщик: %@", "\(r.stderr)")) }
        let instDir = dir.appending(path: "installer")
        if let ptZip {   // the checked Google zip: the installer checks it again and unpacks it itself
            let tools = instDir.appending(path: "tools")
            try? FileManager.default.createDirectory(atPath: tools, withIntermediateDirectories: true)
            let dst = tools.appending(path: ptZip.lastPath)
            if !FileManager.default.exists(dst) { try? FileManager.default.copyItem(atPath: ptZip, toPath: dst) }
        }
        return Workspace(dir: dir, installerDir: instDir, image: dir.appending(path: image.name), tag: rel.tag, device: rel.device)
    }

    /// An unpacked release the user already has: the installer folder and an image next to it or one level up.
    static func local(_ folder: String) throws -> Workspace {
        let fm = FileManager.default
        guard let inst = [folder, folder.appending(path: "installer")].first(where: { fm.exists($0.appending(path: "lumen-install.sh")) }) else {
            throw AppError(L("в папке нет lumen-install.sh. Выберите распакованный релиз Lumen OS"))
        }
        let imgs = [inst, inst.parentPath].flatMap { d in
            ((try? fm.contentsOfDirectory(atPath: d)) ?? []).filter { $0.hasPrefix("lumen-os-") && $0.hasSuffix("-system.img") }.map { d.appending(path: $0) }
        }
        guard let img = imgs.first else { throw AppError(L("рядом с установщиком нет образа lumen-os-…-system.img")) }
        var device = "z9x"
        if let rc = try? String(contentsOfFile: inst.appending(path: "release.conf"), encoding: .utf8),
           let m = firstMatch(#"(?m)^DEVICE=(\w+)"#, in: rc) { device = m[1] }
        return Workspace(dir: inst.parentPath, installerDir: inst, image: img, tag: folder.lastPath, device: device)
    }
}
