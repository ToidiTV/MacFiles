import SwiftUI

struct SettingsCategory: Identifiable {
    let id: String
    let symbol: String
    static let all: [Self] = [
        .init(id: "General", symbol: "gearshape"), .init(id: "Appearance", symbol: "paintbrush"),
        .init(id: "Layout", symbol: "rectangle.3.group"), .init(id: "Folders", symbol: "folder"),
        .init(id: "Actions", symbol: "keyboard"), .init(id: "Developer tools", symbol: "chevron.left.forwardslash.chevron.right"),
        .init(id: "Advanced", symbol: "slider.horizontal.3"), .init(id: "Tags", symbol: "tag"), .init(id: "About", symbol: "info.circle")
    ]
    static func contains(_ section: String, in category: String) -> Bool {
        let sections: [String: [String]] = [
            "General": ["Language", "Home", "Startup", "Startup folders", "Startup and tabs"],
            "Appearance": ["Appearance", "Custom theme", "Context menu", "Background image", "Background image and status"],
            "Layout": ["Layout", "Synchronize folder preferences"],
            "Folders": ["Browsing", "Smooth scrolling", "File information", "Size units", "Confirmations", "Confirm moving files to Trash", "Natural language search", "Libraries"],
            "Developer tools": ["IDE", "GitHub account"],
            "Advanced": ["Launch at login", "Thumbnails", "Show thumbnails", "macOS integration", "File operations"],
            "Tags": ["Tags", "Manage tags", "Tag name"], "About": ["About MacFiles"]
        ]
        return sections[category, default: []].contains(section)
    }
}
