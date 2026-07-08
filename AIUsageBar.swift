// AI Usage Bar – macOS-Menüleisten-App für den Claude-Verbrauch
// Erstellt mit Claude Code (https://claude.com/claude-code)
// Lizenz: MIT
import Cocoa

// MARK: - Datenmodell

struct UsageData {
    var sessionPercent: Int        // 5-Stunden-Session-Limit
    var weeklyPercent: Int         // 7-Tage-Wochenlimit
    var sessionReset: Date?
    var weeklyReset: Date?
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    var statusItem: NSStatusItem!
    let menu = NSMenu()
    var timer: Timer?
    var lastFetch = Date.distantPast
    var lastData: UsageData?
    var lastError: String?
    var isRefreshing = false

    let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    let refreshInterval: TimeInterval = 300   // Hintergrund-Refresh alle 5 Min
    let menuThrottle: TimeInterval = 60        // beim Öffnen höchstens 1x/Min neu laden

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.image = gaugeImage(percent: 0, color: .labelColor)
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = 30   // erlaubt dem System, Wakeups zu bündeln (Energie)
    }

    // Menü öffnet sich -> ggf. frische Daten holen
    func menuWillOpen(_ menu: NSMenu) {
        if Date().timeIntervalSince(lastFetch) > menuThrottle {
            refresh()
        }
    }

    // MARK: - Token

    // Liest den OAuth-Token des aktuellen Users: erst aus dem macOS-Keychain,
    // als Fallback aus ~/.claude/.credentials.json. Funktioniert so für jeden
    // Claude-User, der lokal in Claude Code eingeloggt ist.
    func accessToken() -> String? {
        return tokenFromKeychain() ?? tokenFromFile()
    }

    private func extractToken(_ jsonData: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }
        return token
    }

    private func tokenFromKeychain() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        // Erst lesen, dann warten – umgekehrt kann der Prozess bei vollem Pipe-Puffer hängen
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return extractToken(data)
    }

    private func tokenFromFile() -> String? {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/.credentials.json")
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return extractToken(data)
    }

    // MARK: - Netzwerk

    // Wird immer vom Main-Thread aufgerufen (Launch, Timer, Menü, Klick).
    // Token-Suche und Request laufen im Hintergrund, das UI-Update wieder auf Main.
    func refresh() {
        if isRefreshing { return }
        isRefreshing = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            guard let token = self.accessToken() else {
                self.finishRefresh(data: nil, error: "Kein Login gefunden – in Claude Code einloggen", clearData: true)
                return
            }
            var req = URLRequest(url: self.endpoint)
            req.timeoutInterval = 15
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")

            URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
                guard let self = self else { return }
                if let err = err {
                    self.finishRefresh(data: nil, error: err.localizedDescription)
                    return
                }
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                switch status {
                case 200..<300:
                    break
                case 401, 403:
                    self.finishRefresh(data: nil, error: "Token abgelaufen – in Claude Code neu einloggen")
                    return
                case 429:
                    self.finishRefresh(data: nil, error: "Rate-Limit (429) – kurz warten")
                    return
                default:
                    self.finishRefresh(data: nil, error: "Server-Fehler (HTTP \(status))")
                    return
                }
                guard let data = data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.finishRefresh(data: nil, error: "Antwort nicht lesbar")
                    return
                }
                self.finishRefresh(data: self.parse(obj), error: nil)
            }.resume()
        }
    }

    // Sammelt alle Refresh-Ausgänge: bei Fehlern bleiben die letzten Daten sichtbar,
    // der Fehler wird zusätzlich im Menü/Tooltip angezeigt.
    private func finishRefresh(data: UsageData?, error: String?, clearData: Bool = false) {
        DispatchQueue.main.async {
            self.isRefreshing = false
            self.lastFetch = Date()
            if let data = data { self.lastData = data }
            if clearData { self.lastData = nil }
            self.lastError = error
            self.updateUI()
        }
    }

    func parse(_ obj: [String: Any]) -> UsageData {
        func pct(_ section: String) -> Int {
            if let s = obj[section] as? [String: Any], let u = s["utilization"] as? Double {
                return Int(u.rounded())
            }
            return 0
        }
        func reset(_ section: String) -> Date? {
            guard let s = obj[section] as? [String: Any],
                  let str = s["resets_at"] as? String else { return nil }
            return Self.parseDate(str)
        }
        return UsageData(
            sessionPercent: pct("five_hour"),
            weeklyPercent: pct("seven_day"),
            sessionReset: reset("five_hour"),
            weeklyReset: reset("seven_day")
        )
    }

    // Formatter sind teuer in der Erzeugung – einmal anlegen, wiederverwenden
    static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let isoPlain = ISO8601DateFormatter()
    static let resetFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "EEE HH:mm"
        return df
    }()
    static let clockFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()

    static func parseDate(_ s: String) -> Date? {
        return isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    // MARK: - UI

    func color(for percent: Int) -> NSColor {
        switch percent {
        case 100...:   return .systemPurple   // Limit erreicht → lila
        case 90..<100: return .systemRed
        case 70..<90:  return .systemOrange
        default:       return .labelColor
        }
    }

    // Zeichnet den dynamischen Gauge-Ring fürs Menüleisten-Icon.
    // frac 0…1 = Füllgrad, color = aktuelle Ampelfarbe.
    func gaugeImage(percent: Int, color: NSColor) -> NSImage {
        let dim: CGFloat = 18
        let img = NSImage(size: NSSize(width: dim, height: dim), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let lw: CGFloat = 2.4
            let radius = (dim - lw) / 2 - 1
            ctx.setLineWidth(lw)
            ctx.setLineCap(.round)
            // Hintergrund-Track (dezent)
            ctx.setStrokeColor(color.withAlphaComponent(0.25).cgColor)
            ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.strokePath()
            // Gefüllter Arc: oben beginnend, im Uhrzeigersinn
            let frac = max(0.0, min(1.0, Double(percent) / 100.0))
            if frac > 0 {
                ctx.setStrokeColor(color.cgColor)
                ctx.addArc(center: center, radius: radius,
                           startAngle: .pi / 2, endAngle: .pi / 2 - .pi * 2 * frac, clockwise: true)
                ctx.strokePath()
            }
            return true
        }
        img.isTemplate = false   // Farbe (weiß/orange/rot) soll erhalten bleiben
        return img
    }

    func updateUI() {
        guard let btn = statusItem.button else { return }
        btn.imagePosition = .imageOnly
        btn.title = ""
        if let d = lastData {
            // Menüleiste: nur 5-Stunden-Verbrauch als Gauge-Ring
            btn.image = gaugeImage(percent: d.sessionPercent, color: color(for: d.sessionPercent))
            btn.contentTintColor = nil
            var tip = "Session \(d.sessionPercent) %  ·  Woche \(d.weeklyPercent) %"
            if let err = lastError { tip += "  ·  ⚠︎ \(err)" }
            btn.toolTip = tip
        } else {
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            let warn = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                               accessibilityDescription: "Fehler")?.withSymbolConfiguration(cfg)
            warn?.isTemplate = true
            btn.image = warn
            btn.contentTintColor = .systemRed
            btn.toolTip = lastError
        }
        rebuildMenu()
    }

    func resetText(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let abs = Self.resetFormatter.string(from: date)
        let secs = date.timeIntervalSinceNow
        if secs <= 0 { return "Reset jetzt (\(abs))" }
        let h = Int(secs) / 3600
        let m = (Int(secs) % 3600) / 60
        let rel = h > 0 ? "in \(h) Std \(m) Min" : "in \(m) Min"
        return "Reset \(rel) (\(abs))"
    }

    func bar(_ percent: Int) -> String {
        let slots = 10
        let filled = min(slots, Int((Double(percent) / 100.0 * Double(slots)).rounded()))
        return String(repeating: "█", count: filled) + String(repeating: "░", count: slots - filled)
    }

    func rebuildMenu() {
        menu.removeAllItems()

        func header(_ text: String) {
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        func detail(_ text: String, percent: Int? = nil) {
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            if let p = percent {
                item.attributedTitle = NSAttributedString(
                    string: text,
                    attributes: [.foregroundColor: color(for: p),
                                 .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)])
            } else {
                item.attributedTitle = NSAttributedString(
                    string: text,
                    attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                                 .foregroundColor: NSColor.secondaryLabelColor])
            }
            menu.addItem(item)
        }

        if let d = lastData {
            header("Session (5 Std)")
            detail("  \(bar(d.sessionPercent))  \(d.sessionPercent)%", percent: d.sessionPercent)
            let sessionReset = resetText(d.sessionReset)
            if !sessionReset.isEmpty { detail("  " + sessionReset) }
            menu.addItem(.separator())
            header("Woche (7 Tage)")
            detail("  \(bar(d.weeklyPercent))  \(d.weeklyPercent)%", percent: d.weeklyPercent)
            let weeklyReset = resetText(d.weeklyReset)
            if !weeklyReset.isEmpty { detail("  " + weeklyReset) }
            menu.addItem(.separator())
            detail("Aktualisiert: \(Self.clockFormatter.string(from: lastFetch))")
            // Fehler beim letzten Refresh anzeigen, auch wenn noch alte Daten stehen
            if let err = lastError { detail("⚠︎ \(err)") }
        } else {
            header("AI Usage Bar")
            detail("  Fehler: \(lastError ?? "unbekannt")")
        }

        menu.addItem(.separator())
        let refreshItem = NSMenuItem(title: "Jetzt aktualisieren", action: #selector(manualRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        let quitItem = NSMenuItem(title: "Beenden", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc func manualRefresh() { refresh() }
    @objc func quit() { NSApplication.shared.terminate(nil) }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // kein Dock-Icon
app.run()
