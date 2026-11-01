import Foundation

public enum NativeLocalization {
    private static let lock = NSLock()
    private static var resourceBundle = Bundle.main
    private static var templates: [(String, NSRegularExpression)] = []
    public static func configure(bundle: Bundle) {
        lock.lock(); defer { lock.unlock() }; resourceBundle = bundle
        guard let url = bundle.url(forResource: "NativeTemplates", withExtension: "json"), let data = try? Data(contentsOf: url), let keys = try? JSONDecoder().decode([String].self, from: data) else { return }
        let placeholder = try! NSRegularExpression(pattern: #"%\d+\$@"#)
        templates = keys.compactMap { key in
            var pattern = ""; var position = key.startIndex
            for match in placeholder.matches(in: key, range: NSRange(key.startIndex..., in: key)) {
                guard let range = Range(match.range, in: key) else { continue }
                pattern += NSRegularExpression.escapedPattern(for: String(key[position..<range.lowerBound]).replacingOccurrences(of: "%%", with: "%")) + "(.*?)"; position = range.upperBound
            }
            pattern += NSRegularExpression.escapedPattern(for: String(key[position...]).replacingOccurrences(of: "%%", with: "%"))
            guard let regex = try? NSRegularExpression(pattern: "^" + pattern + "$", options: [.dotMatchesLineSeparators]) else { return nil }
            return (key, regex)
        }
    }
    public static var locale: Locale {
        let language = UserDefaults.standard.string(forKey: "language") ?? "System"
        return language == "System" ? .current : Locale(identifier: language)
    }
    public static var isRightToLeft: Bool { locale.language.characterDirection == .rightToLeft }
    public static func plural(_ key: String, count: Int) -> String {
        lock.lock(); let bundle = resourceBundle; lock.unlock()
        let language = UserDefaults.standard.string(forKey: "language") ?? "System"
        let selected: Bundle
        if language != "System", let path = bundle.path(forResource: language, ofType: "lproj"), let localized = Bundle(path: path) { selected = localized } else { selected = bundle }
        let format = selected.localizedString(forKey: key, value: key, table: "Localizable")
        guard format != key else { return "\(count)" }
        return String(format: format, locale: locale, arguments: [count])
    }
    public static func text(_ value: String) -> String {
        lock.lock(); let bundle = resourceBundle; let patterns = templates; lock.unlock()
        let language = UserDefaults.standard.string(forKey: "language") ?? "System"
        let selected: Bundle
        if language != "System", let path = bundle.path(forResource: language, ofType: "lproj"), let localized = Bundle(path: path) { selected = localized } else { selected = bundle }
        let exact = selected.localizedString(forKey: value, value: value, table: "Localizable")
        if exact != value { return exact }
        for (key, regex) in patterns {
            let translated = selected.localizedString(forKey: key, value: key, table: "Localizable")
            guard translated != key, let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { continue }
            let arguments: [String] = (1..<match.numberOfRanges).map { index in Range(match.range(at: index), in: value).map { String(value[$0]) } ?? "" }
            let placeholder = try! NSRegularExpression(pattern: #"%(\d+)\$@"#)
            var output = translated
            let matches = placeholder.matches(in: translated, range: NSRange(translated.startIndex..., in: translated))
            guard matches.count == arguments.count else { return value }
            for token in matches.reversed() {
                guard let numberRange = Range(token.range(at: 1), in: translated), let number = Int(translated[numberRange]), arguments.indices.contains(number - 1), let range = Range(token.range, in: output) else { return value }
                output.replaceSubrange(range, with: arguments[number - 1])
            }
            return output
        }
        return value
    }
}
