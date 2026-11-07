import Foundation

struct Device: Identifiable, Hashable {
    enum Transport: String { case usb, wifi, fastboot }
    var id: String { "\(transport.rawValue):\(serial)" }
    var serial: String          // what adb/fastboot calls it (ip:port over Wi-Fi)
    var hwSerial: String?       // ro.serialno
    var transport: Transport
    var state: String           // device | unauthorized | offline | fastboot
    var props: [String: String] = [:]
    var match: Match?
    var system: String?
    var lumen = false
    var firmware: String?
    var firmwareOk: Bool?
    var android: String?
    var fbProduct: String?
}

/// Finds connected projectors over adb (cable or network) and in fastboot mode. Read-only: getprop and getvar.
final class Detector {
    let pt: PlatformTools
    private var cache: [String: (props: [String: String], at: Date)] = [:]
    private let lock = NSLock()   // scans run off the main thread; the cache is shared between them
    init(pt: PlatformTools) { self.pt = pt }

    func clearCache() { lock.withLock { cache.removeAll() } }
    private func cached(_ serial: String) -> (props: [String: String], at: Date)? { lock.withLock { cache[serial] } }
    private func store(_ serial: String, _ c: (props: [String: String], at: Date)) { lock.withLock { cache[serial] = c } }

    static func parseGetprop(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            if let m = firstMatch(#"^\[([^\]]+)\]: \[(.*)\]$"#, in: line.trimmingCharacters(in: .whitespaces)) { out[m[1]] = m[2] }
        }
        return out
    }

    func scan(profiles: [Profile]) async throws -> [Device] {
        var found: [Device] = []
        let a = await pt.adb(["devices", "-l"], timeout: 10)
        if a.code != 0 && a.stdout.isEmpty { throw AppError(a.stderr.isEmpty ? L("adb не запускается") : a.stderr) }
        for line in a.stdout.split(whereSeparator: \.isNewline).dropFirst() {
            guard let m = firstMatch(#"^(\S+)\s+(device|unauthorized|offline|recovery|sideload|no permissions)\b"#,
                                     in: line.trimmingCharacters(in: .whitespaces)) else { continue }
            let serial = m[1], state = m[2]
            let wifi = firstMatch(#"^\d+\.\d+\.\d+\.\d+:\d+$"#, in: serial) != nil || serial.contains("._adb")
            var d = Device(serial: serial, transport: wifi ? .wifi : .usb, state: state)
            if state == "device" {
                var c = cached(serial)
                if c == nil || Date().timeIntervalSince(c!.at) > 15 {
                    let r = await pt.adb(["-s", serial, "shell", "getprop"], timeout: 10)
                    c = (Self.parseGetprop(r.stdout), Date())
                    store(serial, c!)
                }
                let props = c!.props
                d.props = props
                d.hwSerial = props["ro.serialno"] ?? (wifi ? nil : serial)
                d.match = Profiles.identify(profiles, props: props, serial: d.hwSerial)
                let lumen = props["ro.z9x.version"] ?? props["ro.lumen.version"]
                let fw = props["ro.vendor.build.version.incremental"]
                d.lumen = lumen != nil
                d.system = lumen.map { "Lumen OS \($0)" } ?? (fw != nil ? L("родная система XGIMI") : nil)
                d.firmware = fw
                d.android = props["ro.build.version.release"]
                if let fw, let p = profiles.first(where: { $0.id == d.match?.id }) { d.firmwareOk = p.firmware.contains(fw.lowercased()) }
            }
            found.append(d)
        }
        let f = await pt.fastboot(["devices"], timeout: 8)
        for line in f.stdout.split(whereSeparator: \.isNewline) {
            guard let m = firstMatch(#"^(\S+)\s+fastboot"#, in: line.trimmingCharacters(in: .whitespaces)) else { continue }
            let g = await pt.fastboot(["-s", m[1], "getvar", "product"], timeout: 8)
            var d = Device(serial: m[1], hwSerial: m[1], transport: .fastboot, state: "fastboot")
            d.fbProduct = firstMatch(#"product:\s*(\S+)"#, in: g.all)?[1]
            d.match = Profiles.identify(profiles, fbProduct: d.fbProduct, serial: m[1])
            d.system = L("режим fastboot")
            found.append(d)
        }
        return found
    }

    func connect(_ addr: String) async -> (ok: Bool, text: String) {
        let target = firstMatch(#":\d+$"#, in: addr) != nil ? addr : "\(addr):5555"
        let r = await pt.adb(["connect", target], timeout: 15)
        let text = r.all.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text.contains("connected to") && !text.lowercased().contains("failed"), text)
    }

    func mdns() async -> [(name: String, addr: String)] {
        let r = await pt.adb(["mdns", "services"], timeout: 10)
        return r.stdout.split(whereSeparator: \.isNewline).compactMap { l in
            firstMatch(#"^(\S+)\s+_adb[\w.-]*\s+(\d+\.\d+\.\d+\.\d+:\d+)"#, in: l.trimmingCharacters(in: .whitespaces)).map { ($0[1], $0[2]) }
        }
    }
}
