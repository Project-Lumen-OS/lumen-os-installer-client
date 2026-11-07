import Foundation

/// Where things live. Downloads go to a visible folder of the user's (~/Lumen Installer); the app's helpers
/// (Platform-Tools, the demo projector) to Application Support.
enum Paths {
    static let home = NSHomeDirectory()
    static let workRoot = home.appending(path: "Lumen Installer")
    static let releases = workRoot.appending(path: "releases")
    static let google = workRoot.appending(path: "google")
    static let stateDir = home.appending(path: ".lumen-installer")
    static let support: String = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].path
        return base.appending(path: "Lumen Installer")
    }()

    /// The installer shipped inside the app (Resources/installer), or, run from the source tree, the one
    /// scripts/get_installer.sh fetched (vendor/lumen-os/installer) or $LUMEN_OS_DIR/installer. Releases bring their
    /// own installer; this one gives the device list, the pinned Platform-Tools checksum before anything is
    /// downloaded, and the demo projector's installer.
    static var bundledInstaller: String {
        if let r = Bundle.main.resourcePath, FileManager.default.exists(r.appending(path: "installer/lumen-install.sh")) {
            return r.appending(path: "installer")
        }
        if let d = ProcessInfo.processInfo.environment["LUMEN_OS_DIR"] { return d.appending(path: "installer") }
        return repoRoot.appending(path: "vendor/lumen-os/installer")
    }

    static var logo: String {
        if let r = Bundle.main.resourcePath, FileManager.default.exists(r.appending(path: "lumen_logo.png")) {
            return r.appending(path: "lumen_logo.png")
        }
        return repoRoot.appending(path: "assets/lumen_logo.png")
    }

    static var simScripts: String {
        if let r = Bundle.main.resourcePath, FileManager.default.exists(r.appending(path: "sim/adb")) {
            return r.appending(path: "sim")
        }
        return repoRoot.appending(path: "shared/sim")
    }

    /// macos/Sources/LumenInstaller/Core/Paths.swift -> the repository root
    private static var repoRoot: String {
        var p = #filePath
        for _ in 0..<5 { p = p.parentPath }
        return p
    }
}
