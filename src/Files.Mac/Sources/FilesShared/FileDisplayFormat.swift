import Foundation

public enum FileDisplayFormat {
    public static func size(_ bytes: Int64, units: String? = nil) -> String {
        let units = units ?? UserDefaults.standard.string(forKey: "displaySizeUnits") ?? "Decimal"
        if units == "Bytes" { return bytes.formatted() + " B" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: units == "Binary" ? .binary : .decimal)
    }
    public static func date(_ value: Date, style: String? = nil, now: Date = Date()) -> String {
        let style = style ?? UserDefaults.standard.string(forKey: "displayDateFormat") ?? "System"
        let formatter = DateFormatter()
        if style == "Universal" { formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss" }
        else if style == "Application" {
            let elapsed = now.timeIntervalSince(value)
            if elapsed >= 0 && elapsed < 7 * 86400 { let relative = RelativeDateTimeFormatter(); relative.unitsStyle = .full; return relative.localizedString(for: value, relativeTo: now) }
            formatter.dateStyle = .full
        } else { formatter.dateStyle = .medium; formatter.timeStyle = .short }
        return formatter.string(from: value)
    }
}
