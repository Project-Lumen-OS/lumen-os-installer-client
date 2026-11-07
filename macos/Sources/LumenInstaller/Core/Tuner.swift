import Foundation

/// SystemUI Tuner: turns on USB debugging on a stock XGIMI, whose Developer options menu is hidden (install guides,
/// "Prepare the projector"). The APK of its author's release 362 on GitHub (zacharee/Tweaker), checked against the
/// sha256 below. XGIMI's file manager does not open .apk files, so it goes on the USB stick as .apk1.
enum Tuner {
    static let version = "362"
    static let url = "https://github.com/zacharee/Tweaker/releases/download/362/SystemUITuner_362-release.apk"
    static let source = "https://github.com/zacharee/Tweaker/releases/tag/362"
    static let size: Int64 = 17_952_121
    static let sha = "ac29d665e5da358d1536ba73b866a9b3b66662b80fdac8e67408f4a257af477e"
    static var file: String { Paths.workRoot.appending(path: "tools/SystemUITuner_362-release.apk") }
    static let stickName = "SystemUITuner.apk1"

    static var ready: Bool { FileManager.default.size(file) == size && (try? Shell.sha256(file: file)) == sha }

    static func fetch(progress: @escaping (Int64, Int64) -> Void) async throws {
        try await Net.download(url, to: file, size: size, progress: progress)
        guard try Shell.sha256(file: file) == sha else {
            try? FileManager.default.removeItem(atPath: file)
            throw AppError(L("SystemUI Tuner не совпадает с файлом автора (sha256)"))
        }
    }

    /// Copies the APK into a folder (the USB stick) as SystemUITuner.apk1.
    static func copy(to folder: String) throws -> String {
        let dst = folder.appending(path: stickName)
        try? FileManager.default.removeItem(atPath: dst)
        try FileManager.default.copyItem(atPath: file, toPath: dst)
        return dst
    }
}
