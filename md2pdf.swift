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
        // **fett**
        if i + 1 < chars.count, chars[i] == "*", chars[i + 1] == "*",
           let c = close(i + 2, ["*", "*"]) {
            flush()
            out.append(NSAttributedString(string: String(chars[(i + 2)..<c]),
                attributes: [.font: NSFont.boldSystemFont(ofSize: base.pointSize),
                             .foregroundColor: color, .paragraphStyle: ps]))
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
        // *kursiv*
        if chars[i] == "*", let c = close(i + 1, ["*"]) {
            flush()
            let it = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
            out.append(NSAttributedString(string: String(chars[(i + 1)..<c]),
                attributes: [.font: it, .foregroundColor: color, .paragraphStyle: ps]))
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
while i < lines.count {
    let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

    if trimmed.isEmpty { i += 1; continue }

    // Codeblock
    if trimmed.hasPrefix("```") {
        i += 1
        var buf: [String] = []
        while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            buf.append(lines[i]); i += 1
        }
        if i < lines.count { i += 1 }
        let codePS = ps(spacingBefore: 5, spacingAfter: 9, firstIndent: 9, headIndent: 9, lineSpacing: 2)
        out.append(NSAttributedString(string: buf.joined(separator: "\n") + "\n",
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
                  && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                item += " " + lines[i].trimmingCharacters(in: .whitespaces); i += 1
            }
            let p = ps(spacingAfter: 3, firstIndent: 2, headIndent: 16, tab: 16)
            out.append(NSAttributedString(string: "•\t",
                attributes: [.font: body, .foregroundColor: textColor, .paragraphStyle: p]))
            appendInline(item, to: out, base: body, color: textColor, ps: p); newline(p)
        }
        continue
    }

    // Geordnete Liste
    if isOrdered(trimmed) {
        var n = 1
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            guard isOrdered(t) else { break }
            var item = t.replacingOccurrences(of: "^[0-9]+\\. ", with: "", options: .regularExpression); i += 1
            while i < lines.count && isIndentedCont(lines[i])
                  && !isOrdered(lines[i].trimmingCharacters(in: .whitespaces)) {
                item += " " + lines[i].trimmingCharacters(in: .whitespaces); i += 1
            }
            let p = ps(spacingAfter: 3, firstIndent: 2, headIndent: 20, tab: 20)
            out.append(NSAttributedString(string: "\(n).\t",
                attributes: [.font: bold, .foregroundColor: textColor, .paragraphStyle: p]))
            appendInline(item, to: out, base: body, color: textColor, ps: p); newline(p)
            n += 1
        }
        continue
    }

    // Absatz
    var para: [String] = [trimmed]; i += 1
    while i < lines.count {
        let t = lines[i].trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.hasPrefix("#") || t.hasPrefix("- ") || t.hasPrefix("```")
            || t.hasPrefix("![") || (t.contains("|") && i + 1 < lines.count && isTableSeparator(lines[i + 1]))
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

let op = NSPrintOperation(view: textView, printInfo: info)
op.showsPrintPanel = false
op.showsProgressPanel = false
op.run()

FileHandle.standardError.write("PDF geschrieben: \(outPath)\n".data(using: .utf8)!)
