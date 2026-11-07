import Foundation
import Compression

/// The one vbmeta step of the Z9X and the Z9X HB, done by the client when the user asks for it: exactly the
/// commands of the install guide (docs/install/z9x, "vbmeta"), with Google's unchanged vbmeta.img.
///
/// The file is the vbmeta.img of Google's Android 14 GSI aosp_arm64 UQ1A.231205.015 (developer.android.com,
/// "GSI releases"; the zip's sha256 below is the one Google publishes). Only its 2 KB deflated entry is fetched
/// with an HTTP range and inflated; the result must match the sha256 taken from the verified zip.
/// The installer then proves on its own, read-only, that verification is off (/dev/block/mapper).
enum Vbmeta {
    static let zipURL = "https://dl.google.com/developers/android/udc/images/gsi/aosp_arm64-exp-UQ1A.231205.015-11084887-e291b838.zip"
    static let zipSha = "e291b838f9e2786eb44c952ca25469745c8085cf91611397d7f620136b48c086"
    static let entry: ClosedRange<Int64> = 935_876_542...935_878_815   // vbmeta.img, deflate
    static let size = 4096
    static let sha = "b3281c527ecf2a6a743b37f5b9e118f492d2038e0a82e6777d292d1c5b42601a"
    static var file: String { Paths.support.appending(path: "vbmeta/vbmeta.img") }

    enum State { case off, on, unknown }

    /// Google's vbmeta.img, checked; fetched once.
    static func fetch() async throws -> String {
        let fm = FileManager.default
        if fm.exists(file), try Shell.sha256(file: file) == sha { return file }
        var req = URLRequest(url: URL(string: zipURL)!)
        req.setValue("bytes=\(entry.lowerBound)-\(entry.upperBound)", forHTTPHeaderField: "Range")
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")   // with gzip allowed Google answers a range with 416
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 206, data.count == entry.count else {
            throw AppError(L("не удалось скачать vbmeta.img у Google"))
        }
        let img = try inflate(data, size: size)
        guard Shell.sha256(data: img) == sha else { throw AppError(L("vbmeta.img не совпадает с файлом Google (sha256)")) }
        try fm.createDirectory(atPath: file.parentPath, withIntermediateDirectories: true)
        try img.write(to: URL(fileURLWithPath: file))
        return file
    }

    private static func inflate(_ data: Data, size: Int) throws -> Data {
        var out = Data(count: size)
        let n = out.withUnsafeMutableBytes { o in
            data.withUnsafeBytes { i in
                compression_decode_buffer(o.bindMemory(to: UInt8.self).baseAddress!, size,
                                          i.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n == size else { throw AppError(L("vbmeta.img не совпадает с файлом Google (sha256)")) }
        return out
    }

    /// The installer's own read-only test: with verification off no dm-verity device is set up. The Z9X looks for
    /// system-verity (vbmeta_effective), the Z9X HB for any *-verity (abf_vbmeta_state).
    static func state(pt: PlatformTools, serial: String, device: String) async -> State {
        let r = await pt.adb(["-s", serial, "shell", "ls", "/dev/block/mapper/"], timeout: 10)
        let names = r.stdout.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard r.code == 0, !names.isEmpty else { return .unknown }
        let on = device == "hb" ? names.contains { $0.hasSuffix("-verity") } : names.contains("system-verity")
        return on ? .on : .off
    }

    /// adb reboot fastboot → fastboot --disable-verity --disable-verification --slot=all flash vbmeta → fastboot reboot,
    /// then waits for the stock system and checks the result. Nothing else is written.
    static func run(pt: PlatformTools, image img: String, serial: String, hwSerial: String?, ip: String?, device: String,
                    log: @escaping (String, LogLine.Kind) -> Void) async throws {

        log("$ adb -s \(serial) reboot fastboot", .cmd)
        _ = await pt.adb(["-s", serial, "reboot", "fastboot"], timeout: 20)
        log(L("жду режим fastboot (до 90 с)…"), .info)
        var fb: String?
        for _ in 0..<45 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let list = await pt.fastboot(["devices"], timeout: 8).stdout.split(whereSeparator: \.isNewline)
                .compactMap { firstMatch(#"^(\S+)\s+fastboot"#, in: $0.trimmingCharacters(in: .whitespaces))?[1] }
            if let h = hwSerial, list.contains(h) { fb = h; break }
            if list.count == 1 { fb = list[0]; break }
            if list.count > 1 { throw AppError(L("в режиме fastboot несколько устройств; оставьте подключённым только проектор")) }
        }
        guard let fb else {
            throw AppError(device == "hb"
                ? L("проектор не появился в режиме fastboot. Нужен кабель A–A между USB-портом проектора и компьютером. Ничего не записано.")
                : L("проектор не появился в режиме fastboot. Проверьте кабель и запустите снова. Ничего не записано."))
        }

        let args = ["-s", fb, "--disable-verity", "--disable-verification", "--slot=all", "flash", "vbmeta", img]
        log("$ fastboot " + args.joined(separator: " ").replacingOccurrences(of: img, with: "vbmeta.img"), .cmd)
        let f = await pt.fastboot(args, timeout: 60)
        for l in f.all.split(whereSeparator: \.isNewline) { log(String(l), .info) }
        let both = ["vbmeta_a", "vbmeta_b"].allSatisfy { firstMatch("Writing '\($0)'\\s+OKAY", in: f.all) != nil }

        log("$ fastboot -s \(fb) reboot", .cmd)
        _ = await pt.fastboot(["-s", fb, "reboot"], timeout: 20)
        guard both else {
            throw AppError(L("fastboot не подтвердил запись vbmeta в оба слота (нужны Writing 'vbmeta_a' OKAY и Writing 'vbmeta_b' OKAY). Проектор перезагружается в стоковую систему."))
        }
        log(L("✓ vbmeta записан в оба слота с отключённой проверкой"), .ok)

        log(L("жду загрузку проектора (до 4 мин)…"), .info)
        var back: String?
        for i in 0..<80 {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            if let ip, i % 3 == 0 { _ = await pt.adb(["connect", ip], timeout: 10) }
            let want = ip ?? serial
            let devs = await pt.adb(["devices"], timeout: 8).stdout
            guard devs.split(whereSeparator: \.isNewline).contains(where: { $0.split(whereSeparator: \.isWhitespace).prefix(2) == [Substring(want), "device"] }) else { continue }
            if await pt.adb(["-s", want, "shell", "getprop", "sys.boot_completed"], timeout: 8).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines) == "1" { back = want; break }
        }
        guard let back else {
            throw AppError(L("проектор не вернулся по adb за 4 минуты. vbmeta записан. Когда проектор загрузится, подключите его снова и продолжите установку."))
        }
        switch await state(pt: pt, serial: back, device: device) {
        case .off: log(L("✓ vbmeta: проверка системы выключена, стоковая система загрузилась"), .ok)
        case .on: throw AppError(L("после перезагрузки проверка системы всё ещё включена: vbmeta не применился. Ничего другого не записано."))
        case .unknown: log(L("! не удалось прочитать /dev/block/mapper; установщик проверит vbmeta сам"), .warn)
        }
    }
}
