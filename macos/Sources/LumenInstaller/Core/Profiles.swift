import Foundation

/// A projector the client knows. What it IS comes from the installer's own lib/devices.conf (model code, board,
/// fastboot product, firmware); the client adds how the computer reaches it and how its releases are named.
struct Profile: Identifiable, Hashable {
    enum Connection { case usb, wifi }
    let id: String
    let name: String
    let model: String
    let board: String
    let fbProduct: String
    let firmware: [String]
    let connection: Connection
    let gappsAllow: String?
    var guideURL: URL { URL(string: "https://github.com/Project-Lumen-OS/lumen-os/blob/main/docs/install/\(id)/\(Lang.current == .ru ? "ru" : "en").md")! }
}

struct Match: Hashable {
    enum By { case model, board, fastboot, serial, manual }
    let id: String
    let by: By
    let detail: String
    var warn = false
}

enum Profiles {
    /// How the computer reaches each projector: the Z9X over USB, the Play 6 and the Z9X HB over Wi‑Fi.
    private static let connection: [String: Profile.Connection] = ["z9x": .usb, "play6": .wifi, "hb": .wifi]

    // notes stay in Russian here (the translation keys); the views show them through L()
    /// Serial prefixes printed on the label / in ro.serialno. Only what the project has seen: a serial that matches
    /// nothing is not guessed, the user picks the model from the list.
    private static let serialRules: [(prefix: String, id: String, note: String, warn: Bool)] = [
        ("XHN", "play6", "партия с чипом Wi-Fi MediaTek", false),
        ("XHF", "play6", "новая партия (прошивка V1.8.x, чип AIC), пока не поддерживается", true),
    ]

    static func load(installerDir: String) -> [Profile] {
        let file = installerDir.appending(path: "lib/devices.conf")
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return [] }
        var conf: [String: [String: String]] = [:]
        var order: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let m = firstMatch(#"^([a-z0-9]+)\.([A-Z0-9_]+)=(.*)$"#, in: line) else { continue }
            if conf[m[1]] == nil { order.append(m[1]) }
            conf[m[1], default: [:]][m[2]] = m[3]
        }
        return order.compactMap { id in
            guard let c = conf[id], let conn = connection[id] else { return nil }
            let gapps = c["GAPPS_ALLOW"] ?? (id == "z9x" ? "lib/gapps_allow.txt" : id == "play6" ? "lib/play6/gapps_allow.txt" : nil)
            return Profile(id: id, name: c["NAME"] ?? id, model: c["MODEL"] ?? "", board: c["BOARD"] ?? "",
                           fbProduct: c["FB_PRODUCT"] ?? "",
                           firmware: (c["VENDOR_OK"] ?? "").split(separator: " ").map(String.init),
                           connection: conn, gappsAllow: gapps)
        }
    }

    /// Strongest evidence first: XGIMI's model code, the board, the fastboot product, then the serial prefix.
    static func identify(_ profiles: [Profile], props: [String: String] = [:], fbProduct: String? = nil, serial: String? = nil) -> Match? {
        if let m = props["ro.boot.xgimi.modelname"], let p = profiles.first(where: { $0.model == m }) {
            return Match(id: p.id, by: .model, detail: L("по модели %@", m))
        }
        if let b = props["ro.boot.hardware"], let p = profiles.first(where: { $0.board == b }) {
            return Match(id: p.id, by: .board, detail: L("по плате %@", b))
        }
        if let f = fbProduct, let p = profiles.first(where: { $0.fbProduct == f }) {
            return Match(id: p.id, by: .fastboot, detail: L("по fastboot product %@", f))
        }
        return identify(profiles, serial: serial)
    }

    static func identify(_ profiles: [Profile], serial: String?) -> Match? {
        guard let s = serial?.trimmingCharacters(in: .whitespaces).uppercased(), !s.isEmpty,
              let r = serialRules.first(where: { s.hasPrefix($0.prefix) }),
              profiles.contains(where: { $0.id == r.id }) else { return nil }
        return Match(id: r.id, by: .serial, detail: L("по серийному номеру %@…: %@", r.prefix, L(r.note)), warn: r.warn)
    }
}
