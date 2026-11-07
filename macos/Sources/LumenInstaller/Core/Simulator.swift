import Foundation

/// The demo projector: a simulated XGIMI Z9X on the USB cable, so the whole install can be shown without a
/// projector. The REAL lumen-install.sh runs against it unchanged; only adb and fastboot are fakes
/// (client/shared/sim, from the installer's own mock tests) and the image is a tiny test file signed with a
/// throwaway demo key made on this computer. Nothing outside the demo folder is touched.
final class Simulator {
    static let serial = "ZF62DEMO0042"
    static let version = "1.0.8"

    let root: String
    init(root: String = Paths.support.appending(path: "demo")) { self.root = root }
    var fb: String { root.appending(path: "projector") }
    var bin: String { root.appending(path: "bin") }
    var rel: String { root.appending(path: "release") }
    var env: [String: String] {
        ["FB": fb, "FB_SERIAL": Self.serial,
         "LUMEN_STATE_DIR": root.appending(path: "state"), "LUMEN_BACKUP_DIR": root.appending(path: "backup")]
    }

    private static let stock = [
        ("ro.boot.xgimi.modelname", "G0082"), ("ro.boot.hardware", "mt9952"), ("ro.serialno", serial),
        ("ro.product.model", "XGIMI Z9X"), ("ro.product.name", "G0082"), ("ro.product.device", "G0082"),
        ("ro.build.version.release", "11"), ("ro.vendor.build.version.incremental", "v6.15.58"),
        ("ro.boot.slot_suffix", "_b"), ("ro.debuggable", "0"),
    ]
    private static let lumen = [
        ("ro.z9x.version", version), ("ro.z9x.gms", "0"), ("ro.z9x.build_id", "lumen-\(version)-demo"),
        ("ro.z9x.variant", "public"), ("ro.z9x.keys", "release"), ("ro.debuggable", "1"),
        ("ro.build.version.release", "14"), ("init.svc.gmpf_main", "running"), ("sys.z9x.blobs", "none"), ("sys.z9x.gapps", "none"),
    ]
    private static let getvar = [
        "is-userspace:yes", "product:mt5877", "unlocked:yes", "current-slot:b", "snapshot-update-status:none",
        "partition-size:super:0x113400000", "partition-type:cache:raw",
        "partition-size:system_b:0x34000000", "is-logical:system_b:yes",
        "partition-size:vendor_b:0x5A8FC000", "is-logical:vendor_b:yes",
        "partition-size:product_b:0x10000000", "is-logical:product_b:yes",
        "partition-size:system_ext_b:0x8000000", "is-logical:system_ext_b:yes",
        "partition-size:system_b-cow:0x100000",
    ].map { "(bootloader) \($0)" } + ["all: Done"]

    private func kv(_ a: [(String, String)]) -> String { a.map { "\($0.0)=\($0.1)" }.joined(separator: "\n") + "\n" }
    private func w(_ f: String, _ s: String) { try? s.write(toFile: fb.appending(path: f), atomically: true, encoding: .utf8) }

    func setup() async throws -> Workspace {
        let fm = FileManager.default
        try? fm.removeItem(atPath: root)
        for d in [fb, bin, rel, env["LUMEN_STATE_DIR"]!, env["LUMEN_BACKUP_DIR"]!] { try fm.createDirectory(atPath: d, withIntermediateDirectories: true) }
        for f in ["adb", "fastboot", "mke2fs", "make_f2fs"] {
            try fm.copyItem(atPath: Paths.simScripts.appending(path: f), toPath: bin.appending(path: f))
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.appending(path: f))
        }
        resetProjector()

        // the release folder: the real installer, a demo certificate instead of the Lumen OS one, a test image
        let inst = rel.appending(path: "installer")
        try fm.copyItem(atPath: Paths.bundledInstaller, toPath: inst)
        try? fm.removeItem(atPath: inst.appending(path: "tools"))
        let key = root.appending(path: "demo-key.pem")
        let cert = inst.appending(path: "certs/ota.x509.pem")
        var r = await Shell.run("/usr/bin/openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert,
                                                    "-subj", "/CN=Lumen OS demo (not a release key)", "-days", "30"], timeout: 30)
        guard r.code == 0 else { throw AppError(L("openssl не создал демо-ключ: %@", "\(r.stderr)")) }
        let img = "lumen-os-\(Self.version)-nogms-system.img"
        let body = Data("LUMEN-DEMO-IMAGE-Z9X \(Self.version)\n".utf8)
        try body.write(to: URL(fileURLWithPath: rel.appending(path: img)))
        try "\(Shell.sha256(data: body))  \(img)\n".write(toFile: rel.appending(path: "SHA256SUMS"), atomically: true, encoding: .utf8)
        r = await Shell.run("/usr/bin/openssl", ["dgst", "-sha256", "-sign", key, "-out", rel.appending(path: "SHA256SUMS.sig"), rel.appending(path: "SHA256SUMS")])
        guard r.code == 0 else { throw AppError(L("openssl не подписал SHA256SUMS: %@", "\(r.stderr)")) }
        try "BLOBS=partition\nVERSION=\(Self.version)\n".write(toFile: inst.appending(path: "release.conf"), atomically: true, encoding: .utf8)

        // the fakes as the installer's own checked tools/platform-tools (the marker a real download leaves)
        let pin = try PlatformTools.pinned()
        let pt = inst.appending(path: "tools/platform-tools")
        try fm.createDirectory(atPath: pt, withIntermediateDirectories: true)
        var marker = ["zip \(pin.sha)"]
        for f in ["adb", "fastboot", "mke2fs", "make_f2fs"] {
            try fm.copyItem(atPath: bin.appending(path: f), toPath: pt.appending(path: f))
            marker.append("\(try Shell.sha256(file: pt.appending(path: f))) \(f)")
        }
        try (marker.joined(separator: "\n") + "\n").write(toFile: pt.appending(path: ".lumen-platform-tools"), atomically: true, encoding: .utf8)
        return Workspace(dir: rel, installerDir: inst, image: rel.appending(path: img), tag: "demo-\(Self.version)", device: "z9x")
    }

    func resetProjector() {
        try? FileManager.default.createDirectory(atPath: fb, withIntermediateDirectories: true)
        w("mode", "android\n"); w("props", kv(Self.stock)); w("props.lumen", kv(Self.lumen))
        w("getvar", Self.getvar.joined(separator: "\n") + "\n")
        w("packages", "com.xgimi.home\ncom.xgimi.projector\n"); w("packages3", "com.netflix.ninja\nru.kinopoisk.tv\n")
        w("adb.log", ""); w("fb.log", ""); w("verity", "")
        for f in ["usb", "flashed", "root", "boot_at", "unexpected", "unauthorized"] { try? FileManager.default.removeItem(atPath: fb.appending(path: f)) }
        try? FileManager.default.removeItem(atPath: env["LUMEN_STATE_DIR"]!)
    }

    func setCable(_ on: Bool) {
        let f = fb.appending(path: "usb")
        if on { FileManager.default.createFile(atPath: f, contents: nil) } else { try? FileManager.default.removeItem(atPath: f) }
    }

    struct Status: Equatable {
        enum Screen { case stock, fastboot, reboot, booting, lumen }
        var cable: Bool
        var screen: Screen
        var lastWrite: String?
    }

    func status() -> Status? {
        func read(_ f: String) -> String { (try? String(contentsOfFile: fb.appending(path: f), encoding: .utf8)) ?? "" }
        let mode = read("mode").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mode.isEmpty else { return nil }
        let lumen = read("props").contains("ro.z9x.version=")
        let bootAt = Double(read("boot_at").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let screen: Status.Screen
        switch mode {
        case "rebooting": screen = .reboot
        case "fastboot": screen = .fastboot
        default: screen = lumen && Date().timeIntervalSince1970 < bootAt ? .booting : (lumen ? .lumen : .stock)
        }
        let writes = read("fb.log").split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.hasPrefix("--version") && !$0.hasPrefix("devices") && !$0.contains(" getvar") }
        return Status(cable: FileManager.default.exists(fb.appending(path: "usb")), screen: screen,
                      lastWrite: writes.last.map { $0.replacingOccurrences(of: "-s \(Self.serial) ", with: "fastboot ") })
    }
}
