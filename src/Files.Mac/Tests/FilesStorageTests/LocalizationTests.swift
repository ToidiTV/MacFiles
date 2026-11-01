import XCTest
import FilesShared
@testable import FilesApp

final class LocalizationTests: XCTestCase {
    @MainActor func testNativeTranslationAndLiteralFormatArguments() {
        let settings = SettingsService.shared; let original = settings.language
        defer { settings.language = original }
        settings.language = "de-DE"
        XCTAssertEqual(L10n.text("POSIX permissions"), "POSIX-Berechtigungen")
        let folder = ListedItem(virtualURL: URL(string: "macfiles-archive://fixture/Folder")!, name: "Folder", directory: true, size: 0)
        XCTAssertEqual(folder.localizedKind, "Ordner")
        XCTAssertEqual(ItemGrouping.groups([folder], by: .kind).first?.localizedTitle(for: .kind), "Ordner")
        XCTAssertFalse(NativeLocalization.isRightToLeft)
        XCTAssertEqual(L10n.text("3 folders"), "3 Ordner")
        XCTAssertEqual(L10n.text("3 folders · saves to /tmp/%1$@/日本語"), "3 Ordner · speichert in /tmp/%1$@/日本語")
    }
    @MainActor func testEveryLocaleRendersNativeInterpolations() {
        let settings = SettingsService.shared; let original = settings.language
        defer { settings.language = original }
        XCTAssertEqual(L10n.languages.count, 49)
        for language in L10n.languages {
            settings.language = language
            let rendered = L10n.text("12 folders · saves to /tmp/日本語")
            XCTAssertTrue(rendered.contains("12"), language)
            XCTAssertTrue(rendered.contains("/tmp/日本語"), language)
            XCTAssertFalse(rendered.contains("$@"), language)
        }
    }
}

extension LocalizationTests {
    @MainActor func testOriginalFilesPluralRulesUseTheSelectedLanguage() {
        let settings = SettingsService.shared; let original = settings.language
        defer { settings.language = original }
        settings.language = "en"
        XCTAssertEqual(L10n.items(1), "1 item"); XCTAssertEqual(L10n.items(2), "2 items")
        settings.language = "ar"; XCTAssertTrue(NativeLocalization.isRightToLeft)
        settings.language = "ru-RU"
        XCTAssertNotEqual(L10n.items(1).replacingOccurrences(of: "1", with: ""), L10n.items(2).replacingOccurrences(of: "2", with: ""))
        XCTAssertEqual(L10n.items(21).replacingOccurrences(of: "21", with: ""), L10n.items(1).replacingOccurrences(of: "1", with: ""))
        for language in L10n.languages {
            settings.language = language
            for number in [0, 1, 2, 5, 21, 100] {
                XCTAssertFalse(L10n.items(number).isEmpty, language)
                XCTAssertFalse(L10n.selected(number).isEmpty, language)
                XCTAssertFalse(L10n.items(number).contains("%"), language)
                XCTAssertFalse(L10n.selected(number).contains("%"), language)
            }
        }
    }
}
