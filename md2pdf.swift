import AppKit
import Foundation

// ─────────────────────────────────────────────────────────────
// Markdown → PDF, rein programmatisch (nur macOS-Bordmittel).
// Aufruf: md2pdf <input.md> <output.pdf>
//
// Baut einen NSAttributedString von Hand (volle Kontrolle über
// Bullets, Einrückungen, Code-Stil) und druckt ihn über
// NSPrintOperation (.save) zu einem paginierten A4-PDF.
// Code-Blöcke bekommen über einen eigenen NSLayoutManager eine
// durchgehende Hintergrundfläche in voller Breite.
// ─────────────────────────────────────────────────────────────

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("Usage: md2pdf <input.md> <output.pdf>\n".data(using: .utf8)!)
    exit(1)
}
let inPath = args[1]
let outPath = args[2]

guard let md = try? String(contentsOfFile: inPath, encoding: .utf8) else {
    FileHandle.standardError.write("Kann \(inPath) nicht lesen\n".data(using: .utf8)!)
    exit(1)
}

extension NSAttributedString.Key {
    static let codeBlock = NSAttributedString.Key("md2pdfCodeBlock")
    static let callout   = NSAttributedString.Key("md2pdfCallout")   // Wert: [tint, accent]
}

// ── Farben & Fonts ───────────────────────────────────────────
let textColor   = NSColor(calibratedWhite: 0.12, alpha: 1)
let h2Color     = NSColor(srgbRed: 0.71, green: 0.28, blue: 0.12, alpha: 1)
let codeColor   = NSColor(calibratedWhite: 0.15, alpha: 1)
let inlineBg    = NSColor(calibratedWhite: 0.93, alpha: 1)
let codeBlockBg = NSColor(calibratedWhite: 0.965, alpha: 1)
let codeBorder  = NSColor(calibratedWhite: 0.88, alpha: 1)
let linkColor   = NSColor(srgbRed: 0.0, green: 0.42, blue: 0.85, alpha: 1)

let body  = NSFont.systemFont(ofSize: 11)
let bold  = NSFont.boldSystemFont(ofSize: 11)
let italic = NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask)
let mono  = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
let codeMono = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
let h1Font = NSFont.boldSystemFont(ofSize: 22)
let h2Font = NSFont.boldSystemFont(ofSize: 15)
let h3Font = NSFont.boldSystemFont(ofSize: 12.5)

// ── Bilder: ![alt](pfad) → NSTextAttachment (auf Breite skaliert) ─
let imgInputDir = (inPath as NSString).deletingLastPathComponent
let maxContentW: CGFloat = 495   // A4-Breite 595 - 2×50 Rand

func makeImageAttachment(_ path: String) -> NSAttributedString? {
    let raw = path.hasPrefix("/")
        ? path
        : (imgInputDir as NSString).appendingPathComponent(path)
    let full = (raw as NSString).standardizingPath   // löst ../ auf
    guard let img = NSImage(contentsOfFile: full) else { return nil }
    var sz = img.size
    if sz.width > maxContentW {                 // proportional verkleinern
        let s = maxContentW / sz.width
        sz = NSSize(width: maxContentW, height: sz.height * s)
    }
    let att = NSTextAttachment()
    att.image = img
    att.bounds = NSRect(origin: .zero, size: sz)
    return NSAttributedString(attachment: att)
}

// ── Inline-Formatierung: **fett**, `code`, *kursiv*, Links, Bilder ─
func appendInline(_ s: String, to out: NSMutableAttributedString,
                  base: NSFont, color: NSColor, ps: NSParagraphStyle) {
    let chars = Array(s)
    var i = 0
    var plain = ""
    func flush() {
        guard !plain.isEmpty else { return }
        out.append(NSAttributedString(string: plain,
            attributes: [.font: base, .foregroundColor: color, .paragraphStyle: ps]))
        plain = ""
    }
    func close(_ from: Int, _ marker: [Character]) -> Int? {
        guard marker.count > 0, from <= chars.count - marker.count else { return nil }
        var j = from
        while j <= chars.count - marker.count {
            if Array(chars[j..<j + marker.count]) == marker { return j }
            j += 1
        }
        return nil
    }
    while i < chars.count {
        // ![alt](pfad) – Inline-Bild
        if chars[i] == "!", i + 1 < chars.count, chars[i + 1] == "[",
           let rb = close(i + 2, ["]"]), rb + 1 < chars.count, chars[rb + 1] == "(",
           let rp = close(rb + 2, [")"]) {
            flush()
            if let img = makeImageAttachment(String(chars[(rb + 2)..<rp])) {
                out.append(img)
            }
            i = rp + 1; continue
        }
        // [[Wikilink]] bzw. [[Ziel|Alias]] – gestylter Text ohne Klammern
        if chars[i] == "[", i + 1 < chars.count, chars[i + 1] == "[",
           let rb = close(i + 2, ["]", "]"]) {
            flush()
            let inner = String(chars[(i + 2)..<rb])
            let name = inner.components(separatedBy: "|").last ?? inner
            out.append(NSAttributedString(string: name,
                attributes: [.font: NSFont.boldSystemFont(ofSize: base.pointSize),
                             .foregroundColor: linkColor, .paragraphStyle: ps]))
            i = rb + 2; continue
        }
        // [text](url) – Link
        if chars[i] == "[", let rb = close(i + 1, ["]"]),
           rb + 1 < chars.count, chars[rb + 1] == "(", let rp = close(rb + 2, [")"]) {
            flush()
            var a: [NSAttributedString.Key: Any] = [
                .font: base, .foregroundColor: linkColor, .paragraphStyle: ps,
                .underlineStyle: NSUnderlineStyle.single.rawValue]
            if let u = URL(string: String(chars[(rb + 2)..<rp])) { a[.link] = u }
            out.append(NSAttributedString(string: String(chars[(i + 1)..<rb]), attributes: a))
            i = rp + 1; continue
        }
        // **fett** – rekursiv, damit `code` und *kursiv* darin funktionieren
        if i + 1 < chars.count, chars[i] == "*", chars[i + 1] == "*",
           let c = close(i + 2, ["*", "*"]) {
            flush()
            appendInline(String(chars[(i + 2)..<c]), to: out,
                         base: NSFont.boldSystemFont(ofSize: base.pointSize),
                         color: color, ps: ps)
            i = c + 2; continue
        }
        // `code`
        if chars[i] == "`", let c = close(i + 1, ["`"]) {
            flush()
            out.append(NSAttributedString(string: String(chars[(i + 1)..<c]),
                attributes: [.font: mono, .foregroundColor: codeColor,
                             .backgroundColor: inlineBg, .paragraphStyle: ps]))
            i = c + 1; continue
        }
        // *kursiv* – rekursiv wie **fett**
        if chars[i] == "*", let c = close(i + 1, ["*"]) {
            flush()
            let it = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
            appendInline(String(chars[(i + 1)..<c]), to: out, base: it, color: color, ps: ps)
            i = c + 1; continue
        }
        plain.append(chars[i]); i += 1
    }
    flush()
}

// ── Absatzstile ──────────────────────────────────────────────
func ps(spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 6,
        firstIndent: CGFloat = 0, headIndent: CGFloat = 0,
        lineSpacing: CGFloat = 1, tab: CGFloat? = nil) -> NSParagraphStyle {
    let p = NSMutableParagraphStyle()
    p.paragraphSpacingBefore = spacingBefore
    p.paragraphSpacing = spacingAfter
    p.firstLineHeadIndent = firstIndent
    p.headIndent = headIndent
    p.lineSpacing = lineSpacing
    if let t = tab { p.tabStops = [NSTextTab(textAlignment: .left, location: t)] }
    return p
}

// ── Markdown-Block-Parser → NSAttributedString ───────────────
let out = NSMutableAttributedString()
let lines = md.components(separatedBy: "\n")
func isBlank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespaces).isEmpty }
func isOrdered(_ t: String) -> Bool { t.range(of: "^[0-9]+\\. ", options: .regularExpression) != nil }
func isIndentedCont(_ l: String) -> Bool { !isBlank(l) && (l.first == " " || l.first == "\t") }

func newline(_ p: NSParagraphStyle) {
    out.append(NSAttributedString(string: "\n", attributes: [.font: body, .paragraphStyle: p, .foregroundColor: textColor]))
}

// ── Tabellen (GitHub-Flavored: | … | mit |---|-Trennzeile) ───
func isTableSeparator(_ s: String) -> Bool {
    let t = s.trimmingCharacters(in: .whitespaces)
    guard t.contains("-"), t.contains("|") else { return false }
    return t.allSatisfy { "|-: ".contains($0) }   // nur |, -, :, Leerzeichen
}
func splitRow(_ s: String) -> [String] {
    var t = s.trimmingCharacters(in: .whitespaces)
    if t.hasPrefix("|") { t.removeFirst() }
    if t.hasSuffix("|") { t.removeLast() }
    return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
}
func appendTable(_ rows: [[String]]) {
    guard !rows.isEmpty else { return }
    let cols = rows.map { $0.count }.max() ?? 1
    let table = NSTextTable()
    table.numberOfColumns = cols
    table.setContentWidth(100, type: .percentageValueType)   // volle Breite
    for (r, row) in rows.enumerated() {
        for c in 0..<cols {
            let cell = c < row.count ? row[c] : ""
            let block = NSTextTableBlock(table: table, startingRow: r, rowSpan: 1,
                                         startingColumn: c, columnSpan: 1)
            block.setBorderColor(codeBorder)
            block.setWidth(0.5, type: .absoluteValueType, for: .border)
            block.setWidth(5, type: .absoluteValueType, for: .padding)
            if r == 0 { block.backgroundColor = inlineBg }   // Kopfzeile hinterlegen
            let cps = NSMutableParagraphStyle()
            cps.textBlocks = [block]
            cps.paragraphSpacing = 0
            let f = r == 0 ? bold : body
            appendInline(cell, to: out, base: f, color: textColor, ps: cps)
            out.append(NSAttributedString(string: "\n",
                attributes: [.font: f, .paragraphStyle: cps, .foregroundColor: textColor]))
        }
    }
    newline(ps(spacingBefore: 2, spacingAfter: 8))           // Abstand nach Tabelle
}

var i = 0

// YAML-Frontmatter (--- … ---) am Dateianfang überspringen
if !lines.isEmpty && lines[0].trimmingCharacters(in: .whitespaces) == "---" {
    var j = 1
    while j < lines.count && lines[j].trimmingCharacters(in: .whitespaces) != "---" { j += 1 }
    if j < lines.count { i = j + 1 }
}

while i < lines.count {
    let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

    if trimmed.isEmpty { i += 1; continue }

    // Blockquote / Obsidian-Callout: > [!typ] Titel  +  > Folgezeilen
    if trimmed.hasPrefix(">") {
        var quote: [String] = []
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix(">") else { break }
            var inner = String(t.dropFirst())
            if inner.hasPrefix(" ") { inner.removeFirst() }
            quote.append(inner); i += 1
        }
        // Typ & Titel aus der ersten Zeile ([!info] Titel); ohne [!…] = normales Zitat
        var accent = NSColor(calibratedWhite: 0.45, alpha: 1)
        var tint   = NSColor(calibratedWhite: 0.955, alpha: 1)
        var title: String? = nil
        var bodyStart = 0
        if let first = quote.first,
           let m = first.range(of: "^\\[!([A-Za-z]+)\\][-+]?\\s*", options: .regularExpression) {
            let typ = first.replacingOccurrences(of: "^\\[!([A-Za-z]+)\\].*$", with: "$1",
                                                 options: .regularExpression).lowercased()
            switch typ {
            case "warning", "caution", "attention", "bug", "danger", "error", "fail", "failure", "missing":
                accent = NSColor(srgbRed: 0.78, green: 0.33, blue: 0.08, alpha: 1)
                tint   = NSColor(srgbRed: 1.00, green: 0.955, blue: 0.91, alpha: 1)
            case "important", "question", "help", "faq":
                accent = NSColor(srgbRed: 0.52, green: 0.28, blue: 0.75, alpha: 1)
                tint   = NSColor(srgbRed: 0.965, green: 0.945, blue: 1.00, alpha: 1)
            case "check", "success", "done", "tip", "hint":
                accent = NSColor(srgbRed: 0.12, green: 0.52, blue: 0.24, alpha: 1)
                tint   = NSColor(srgbRed: 0.93, green: 0.975, blue: 0.93, alpha: 1)
            default:   // info, note, todo, abstract, summary, example, quote …
                accent = NSColor(srgbRed: 0.04, green: 0.40, blue: 0.74, alpha: 1)
                tint   = NSColor(srgbRed: 0.925, green: 0.955, blue: 1.00, alpha: 1)
            }
            let rest = String(first[m.upperBound...]).trimmingCharacters(in: .whitespaces)
            title = rest.isEmpty ? typ.prefix(1).uppercased() + typ.dropFirst() : rest
            bodyStart = 1
        }
        let markStart = out.length
        let padL: CGFloat = 10
        if let title {
            let tp = ps(spacingBefore: 5, spacingAfter: 3, firstIndent: padL, headIndent: padL)
            appendInline(title, to: out, base: bold, color: accent, ps: tp); newline(tp)
        }
        // Innere Zeilen: Mini-Parser für Absätze, Listen und Code-Zeilen
        var k = bodyStart
        var inFence = false
        var paraBuf: [String] = []
        func flushQuotePara() {
            guard !paraBuf.isEmpty else { return }
            let p = ps(spacingAfter: 3, firstIndent: padL, headIndent: padL)
            appendInline(paraBuf.joined(separator: " "), to: out, base: body, color: textColor, ps: p)
            newline(p)
            paraBuf = []
        }
        while k < quote.count {
            let qt = quote[k].trimmingCharacters(in: .whitespaces)
            if qt.hasPrefix("```") { flushQuotePara(); inFence.toggle(); k += 1; continue }
            if inFence {
                let p = ps(spacingAfter: 0, firstIndent: padL + 6, headIndent: padL + 6, lineSpacing: 2)
                out.append(NSAttributedString(string: quote[k] + "\n",
                    attributes: [.font: codeMono, .foregroundColor: codeColor, .paragraphStyle: p]))
                k += 1; continue
            }
            if qt.isEmpty { flushQuotePara(); k += 1; continue }
            if qt.hasPrefix("- ") {
                flushQuotePara()
                let p = ps(spacingAfter: 2, firstIndent: padL + 2, headIndent: padL + 14, tab: padL + 14)
                out.append(NSAttributedString(string: "•\t",
                    attributes: [.font: body, .foregroundColor: textColor, .paragraphStyle: p]))
                appendInline(String(qt.dropFirst(2)), to: out, base: body, color: textColor, ps: p); newline(p)
                k += 1; continue
            }
            if isOrdered(qt) {
                flushQuotePara()
                let num = String(qt.prefix(while: { $0 != " " }))
                let rest = qt.replacingOccurrences(of: "^[0-9]+\\. ", with: "", options: .regularExpression)
                let p = ps(spacingAfter: 2, firstIndent: padL + 2, headIndent: padL + 20, tab: padL + 20)
                out.append(NSAttributedString(string: "\(num)\t",
                    attributes: [.font: bold, .foregroundColor: textColor, .paragraphStyle: p]))
                appendInline(rest, to: out, base: body, color: textColor, ps: p); newline(p)
                k += 1; continue
            }
            paraBuf.append(qt); k += 1
        }
        flushQuotePara()
        out.addAttribute(.callout, value: [tint, accent],
                         range: NSRange(location: markStart, length: out.length - markStart))
        newline(ps(spacingAfter: 9))
        continue
    }

    // Trennlinie: --- / *** / ___ auf eigener Zeile
    if trimmed.range(of: "^(-{3,}|\\*{3,}|_{3,})$", options: .regularExpression) != nil {
        let p = ps(spacingBefore: 5, spacingAfter: 9)
        let ruleFont = NSFont.systemFont(ofSize: 8)
        let dashW = ("─" as NSString).size(withAttributes: [.font: ruleFont]).width
        let count = max(10, Int(maxContentW / dashW) - 1)   // knapp unter Satzbreite → kein Umbruch
        out.append(NSAttributedString(string: String(repeating: "─", count: count) + "\n",
            attributes: [.font: ruleFont, .foregroundColor: codeBorder, .paragraphStyle: p]))
        i += 1; continue
    }

    // Codeblock
    if trimmed.hasPrefix("```") {
        i += 1
        var buf: [String] = []
        while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            buf.append(lines[i]); i += 1
        }
        if i < lines.count { i += 1 }
        let codePS = ps(spacingBefore: 5, spacingAfter: 9, firstIndent: 9, headIndent: 9, lineSpacing: 2)
        // U+2028 (Zeilentrenner) statt \n: Der ganze Block bleibt EIN Absatz,
        // paragraphSpacing fällt also nur einmal am Ende an – keine Leerzeilen
        // zwischen den Code-Zeilen.
        out.append(NSAttributedString(string: buf.joined(separator: "\u{2028}") + "\n",
            attributes: [.font: codeMono, .foregroundColor: codeColor,
                         .paragraphStyle: codePS, .codeBlock: true]))
        continue
    }

    // Bild als eigener Block: ![alt](pfad)
    if trimmed.hasPrefix("!["), let rb = trimmed.range(of: "]("),
       let rp = trimmed.range(of: ")", range: rb.upperBound..<trimmed.endIndex) {
        let path = String(trimmed[rb.upperBound..<rp.lowerBound])
        if let att = makeImageAttachment(path) {
            let p = ps(spacingBefore: 6, spacingAfter: 8)
            let m = NSMutableAttributedString(attributedString: att)
            m.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: m.length))
            out.append(m); newline(p)
        }
        i += 1; continue
    }

    // Tabelle: Zeile mit | und nächste Zeile als Trenn-Zeile (|---|---|)
    if trimmed.contains("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
        var rows: [[String]] = [splitRow(trimmed)]
        i += 2                                   // Kopfzeile + Trenn-Zeile überspringen
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t.contains("|") else { break }
            rows.append(splitRow(t)); i += 1
        }
        appendTable(rows)
        continue
    }

    // Überschriften
    if trimmed.hasPrefix("### ") {
        let p = ps(spacingBefore: 11, spacingAfter: 3)
        appendInline(String(trimmed.dropFirst(4)), to: out, base: h3Font, color: textColor, ps: p); newline(p); i += 1; continue
    }
    if trimmed.hasPrefix("## ") {
        let p = ps(spacingBefore: 16, spacingAfter: 5)
        appendInline(String(trimmed.dropFirst(3)), to: out, base: h2Font, color: h2Color, ps: p); newline(p); i += 1; continue
    }
    if trimmed.hasPrefix("# ") {
        let p = ps(spacingBefore: 0, spacingAfter: 10)
        appendInline(String(trimmed.dropFirst(2)), to: out, base: h1Font, color: textColor, ps: p); newline(p); i += 1; continue
    }

    // Ungeordnete Liste
    if trimmed.hasPrefix("- ") {
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("- ") else { break }
            var item = String(t.dropFirst(2)); i += 1
            while i < lines.count && isIndentedCont(lines[i])
                  && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("- ")
                  && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                item += " " + lines[i].trimmingCharacters(in: .whitespaces); i += 1
            }
            let p = ps(spacingAfter: 3, firstIndent: 2, headIndent: 16, tab: 16)
            out.append(NSAttributedString(string: "•\t",
                attributes: [.font: body, .foregroundColor: textColor, .paragraphStyle: p]))
            appendInline(item, to: out, base: body, color: textColor, ps: p); newline(p)
        }
        continue
    }

    // Geordnete Liste – nutzt die Original-Nummern der Quelle. So bleibt die
    // Zählung korrekt, wenn ein Code-Block die Liste unterbricht (der die
    // Item-Faltung beendet und vom Hauptloop als Block gerendert wird).
    if isOrdered(trimmed) {
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            guard isOrdered(t) else { break }
            let num = String(t.prefix(while: { $0 != " " }))
            var item = t.replacingOccurrences(of: "^[0-9]+\\. ", with: "", options: .regularExpression); i += 1
            while i < lines.count && isIndentedCont(lines[i])
                  && !isOrdered(lines[i].trimmingCharacters(in: .whitespaces))
                  && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                item += " " + lines[i].trimmingCharacters(in: .whitespaces); i += 1
            }
            let p = ps(spacingAfter: 3, firstIndent: 2, headIndent: 20, tab: 20)
            out.append(NSAttributedString(string: "\(num)\t",
                attributes: [.font: bold, .foregroundColor: textColor, .paragraphStyle: p]))
            appendInline(item, to: out, base: body, color: textColor, ps: p); newline(p)
        }
        continue
    }

    // Absatz
    var para: [String] = [trimmed]; i += 1
    while i < lines.count {
        let t = lines[i].trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.hasPrefix("#") || t.hasPrefix("- ") || t.hasPrefix("```")
            || t.hasPrefix("![") || t.hasPrefix(">")
            || t.range(of: "^(-{3,}|\\*{3,}|_{3,})$", options: .regularExpression) != nil
            || (t.contains("|") && i + 1 < lines.count && isTableSeparator(lines[i + 1]))
            || isOrdered(t) { break }
        para.append(t); i += 1
    }
    let p = ps(spacingAfter: 6)
    appendInline(para.joined(separator: " "), to: out, base: body, color: textColor, ps: p); newline(p)
}

// ── LayoutManager mit Code-Block-Hintergrund ─────────────────
final class CodeLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let tc = textContainers.first, let ts = textStorage {
            // Callout-Boxen: getönte Fläche + Akzentbalken links
            ts.enumerateAttribute(.callout, in: NSRange(location: 0, length: ts.length), options: []) { value, range, _ in
                guard let colors = value as? [NSColor], colors.count == 2 else { return }
                let gr = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                guard NSIntersectionRange(gr, glyphsToShow).length > 0 else { return }
                var rect = boundingRect(forGlyphRange: gr, in: tc).offsetBy(dx: origin.x, dy: origin.y)
                rect.origin.x = origin.x
                rect.size.width = tc.size.width
                let box = rect.insetBy(dx: 0, dy: -4)
                let path = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)
                colors[0].setFill(); path.fill()
                let bar = NSRect(x: box.minX, y: box.minY, width: 3, height: box.height)
                colors[1].setFill(); NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
            }
            // Über den GESAMTEN Text iterieren, damit pro Code-Block die
            // volle (durchgehende) Range gezeichnet wird – nicht pro Zeile.
            ts.enumerateAttribute(.codeBlock, in: NSRange(location: 0, length: ts.length), options: []) { value, range, _ in
                guard value != nil else { return }
                let gr = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                guard NSIntersectionRange(gr, glyphsToShow).length > 0 else { return }
                var rect = boundingRect(forGlyphRange: gr, in: tc).offsetBy(dx: origin.x, dy: origin.y)
                rect.origin.x = origin.x
                rect.size.width = tc.size.width
                let box = rect.insetBy(dx: 0, dy: -3)
                let path = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)
                codeBlockBg.setFill(); path.fill()
                codeBorder.setStroke(); path.lineWidth = 0.5; path.stroke()
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }
}

// ── Layout & Druck ───────────────────────────────────────────
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let pageW: CGFloat = 595, pageH: CGFloat = 842, margin: CGFloat = 50
let contentW = pageW - 2 * margin

let textStorage = NSTextStorage(attributedString: out)
let layoutManager = CodeLayoutManager()
textStorage.addLayoutManager(layoutManager)
let container = NSTextContainer(size: NSSize(width: contentW, height: .greatestFiniteMagnitude))
container.lineFragmentPadding = 0
layoutManager.addTextContainer(container)

let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentW, height: 100), textContainer: container)
textView.isVerticallyResizable = true
textView.isHorizontallyResizable = false
textView.drawsBackground = false
layoutManager.ensureLayout(for: container)
let used = layoutManager.usedRect(for: container)
textView.frame = NSRect(x: 0, y: 0, width: contentW, height: ceil(used.height) + 4)

let info = NSPrintInfo(dictionary: [
    .jobDisposition: NSPrintInfo.JobDisposition.save,
    .jobSavingURL: URL(fileURLWithPath: outPath)
])
info.paperSize = NSSize(width: pageW, height: pageH)
info.topMargin = margin; info.bottomMargin = margin
info.leftMargin = margin; info.rightMargin = margin
info.horizontalPagination = .fit
info.verticalPagination = .automatic
// Inhalt nicht zentrieren – sonst rutscht eine halbleere letzte Seite optisch in die Mitte.
info.isHorizontallyCentered = false
info.isVerticallyCentered = false

let op = NSPrintOperation(view: textView, printInfo: info)
op.showsPrintPanel = false
op.showsProgressPanel = false
op.run()

FileHandle.standardError.write("PDF geschrieben: \(outPath)\n".data(using: .utf8)!)
