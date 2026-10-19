import AppKit

/// The annotation color new arrows, boxes, and labels start with. The editor's
/// color well and Settings share this value, and the last color picked is kept
/// across launches.
enum AnnotationColorSettings {
    static let didChange = Notification.Name("AnnotationColorSettingsDidChange")
    private static let defaultsKey = "annotationColorHex"

    static var color: NSColor {
        guard let hex = UserDefaults.standard.string(forKey: defaultsKey),
              let stored = color(fromHex: hex) else {
            return ArrowshotStyle.defaultAnnotationColor
        }
        return stored
    }

    static func set(_ color: NSColor) {
        guard let hex = hexString(for: color) else { return }
        guard UserDefaults.standard.string(forKey: defaultsKey) != hex else { return }
        UserDefaults.standard.set(hex, forKey: defaultsKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func hexString(for color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let red = byte(rgb.redComponent)
        let green = byte(rgb.greenComponent)
        let blue = byte(rgb.blueComponent)
        let alpha = byte(rgb.alphaComponent)
        if alpha == 255 {
            return String(format: "#%02X%02X%02X", red, green, blue)
        }
        return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
    }

    static func color(fromHex hex: String) -> NSColor? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, text.allSatisfy(\.isHexDigit) else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: text).scanHexInt64(&value) else { return nil }
        let red, green, blue, alpha: CGFloat
        if text.count == 6 {
            red = CGFloat((value >> 16) & 0xFF) / 255
            green = CGFloat((value >> 8) & 0xFF) / 255
            blue = CGFloat(value & 0xFF) / 255
            alpha = 1
        } else {
            red = CGFloat((value >> 24) & 0xFF) / 255
            green = CGFloat((value >> 16) & 0xFF) / 255
            blue = CGFloat((value >> 8) & 0xFF) / 255
            alpha = CGFloat(value & 0xFF) / 255
        }
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    private static func byte(_ component: CGFloat) -> Int {
        Int((min(1, max(0, component)) * 255).rounded())
    }
}

/// The file name used when an image is dragged out of the editor, and by ⌘S.
/// `{date}`, `{time}`, and `{datetime}` are filled in at save time.
enum ExportFileName {
    static let defaultPattern = "Arrowshot {datetime}"
    private static let defaultsKey = "exportFileNamePattern"
    private static let tokenExpression = try! NSRegularExpression(
        pattern: #"\{(datetime|date|time)\}"#,
        options: [.caseInsensitive]
    )

    static var pattern: String {
        let stored = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? defaultPattern : stored
    }

    static func setPattern(_ pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == defaultPattern {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: defaultsKey)
        }
    }

    static func fileName(format: ImageFormat, pattern: String? = nil, date: Date = Date()) -> String {
        let requested = pattern ?? self.pattern
        let base = stem(from: requested, date: date)
        let resolved = base.isEmpty ? stem(from: defaultPattern, date: date) : base
        return "\(resolved).\(format.fileExtension)"
    }

    private static func stem(from pattern: String, date: Date) -> String {
        let expanded = expandTokens(in: pattern, date: date)
        let cleaned = sanitize(expanded)
        return stripImageExtension(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func expandTokens(in pattern: String, date: Date) -> String {
        let source = pattern as NSString
        let range = NSRange(location: 0, length: source.length)
        var result = ""
        var cursor = 0
        for match in tokenExpression.matches(in: pattern, range: range) {
            let prefix = NSRange(location: cursor, length: match.range.location - cursor)
            result += source.substring(with: prefix)
            switch source.substring(with: match.range(at: 1)).lowercased() {
            case "datetime":
                result += formatted(date, "yyyy-MM-dd HH.mm.ss")
            case "date":
                result += formatted(date, "yyyy-MM-dd")
            case "time":
                result += formatted(date, "HH.mm.ss")
            default:
                break
            }
            cursor = match.range.location + match.range.length
        }
        result += source.substring(from: cursor)
        return result
    }

    private static func formatted(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// Finder file names cannot contain `/` or `:`.
    private static func sanitize(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\u{0}")
        let cleaned = String(name.unicodeScalars.map { scalar in
            forbidden.contains(scalar) ? "-" : Character(scalar)
        })
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." || trimmed == ".." { return "" }
        let hasLetterOrDigit = trimmed.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        return hasLetterOrDigit ? trimmed : ""
    }

    private static func stripImageExtension(_ name: String) -> String {
        let lowercased = name.lowercased()
        for suffix in [".png", ".jpg", ".jpeg"] where lowercased.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }
}
