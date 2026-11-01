import SwiftUI
import AppKit
import FilesShared

struct AdditionalSettings: View {
    @ObservedObject private var settings = SettingsService.shared
    var search: String
    var category: String = "General"
    private func matches(_ keys: [String]) -> Bool { search.isEmpty ? SettingsCategory.contains(keys.first ?? "", in: category) : keys.contains { L10n.text($0).localizedStandardContains(search) } }
    var body: some View {
        if matches(["Natural language search"]) {
            Section(L10n.text("Natural language search")) {
                Toggle(L10n.text("Natural language search"), isOn: $settings.preferences.naturalLanguageSearch).disabled(!NaturalLanguageSearch.available)
                Text(L10n.text("Uses the on-device Apple Intelligence model when available. Otherwise searches the words you entered. No file content is sent to a server.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        if matches(["IDE", "Developer tools", "No IDE selected", "Choose IDE…", "Test IDE", "IDE opened.", "Clear", "Open in IDE uses the selected application. Open repository in IDE resolves the Git repository root first."]) { IDESettings() }
        if matches(["GitHub account", "GitHub username", "Access token", "Keychain", "HTTPS Git operations can use a GitHub access token stored in your macOS Keychain. Choose the repositories and permissions when creating the token. Existing Git authentication remains in use when no MacFiles account is saved.", "Create a GitHub token", "Save to Keychain", "Saved. The token will be used for GitHub HTTPS operations.", "Remove saved credentials"]) { GitAccountSettings() }
        if matches(["Context menu", "Font", "Font and material", "Backdrop material", "Open in new tab", "Open in new window", "Open in other pane", "Copy path", "CreateFolderWithSelection", "Make alias…", "Pin to sidebar", "Compress…", "Flatten folder…", "Share…", "Open in Terminal", "Edit tags…", "Extended attributes…"]) { ContextAppearanceSettings(search: search) }
        if matches(["Launch at login", "Keep running after closing windows", "Show menu bar icon", "Background", "Open MacFiles", "Quit MacFiles", "Approve MacFiles in Login Items in System Settings.", "Open Login Items settings", "Background mode keeps the menu bar icon available so you can reopen MacFiles or quit it."]) { BackgroundSettings() }
        if matches(["Tags", "Manage tags", "Tag color", "Renaming or deleting a saved tag updates files found by Spotlight. Unindexed or inaccessible files may retain the old tag. Tag colors use the macOS palette.", "Edit", "Delete", "Tag name", "Cancel", "Delete saved tag and remove it from indexed files?", "Tag names must be unique.", "Indexed files updated.", "Some files could not be updated. The saved tag was retained so you can retry."]) { TagSettingsSection() }
        if matches(["Size units", "Date format", "Calculate folder sizes", "Select previous folder when navigating up", "File information"]) {
            Section(L10n.text("File information")) {
                Picker(L10n.text("Size units"), selection: $settings.preferences.sizeUnits) { ForEach(["Decimal", "Binary", "Bytes"], id: \.self) { Text(L10n.text($0)).tag($0) } }
                Picker(L10n.text("Date format"), selection: $settings.preferences.dateFormat) { ForEach(["Application", "System", "Universal"], id: \.self) { Text(L10n.text($0)).tag($0) } }
                Toggle(L10n.text("Calculate folder sizes"), isOn: $settings.preferences.calculateFolderSizes)
                Text(L10n.text("Folder sizes are calculated in the background after Refresh. Large or network folders may take longer.")).font(.caption).foregroundStyle(.secondary)
                Toggle(L10n.text("Select previous folder when navigating up"), isOn: $settings.preferences.selectPreviousFolder)
            }
        }
        if matches(["Background image", "Image fit", "Image alignment", "Separate file and folder counts", "Always show operations", "Show tab actions", "Show shelf button", "Background image and status"]) {
            Section(L10n.text("Background image and status")) {
                Picker(L10n.text("Image fit"), selection: $settings.preferences.backgroundFit) { ForEach(["None", "Stretch", "Fit", "Fill"], id: \.self) { Text(L10n.text($0)).tag($0) } }
                Picker(L10n.text("Horizontal alignment"), selection: $settings.preferences.backgroundHorizontal) { ForEach(["Left", "Center", "Right"], id: \.self) { Text(L10n.text($0)).tag($0) } }
                Picker(L10n.text("Vertical alignment"), selection: $settings.preferences.backgroundVertical) { ForEach(["Top", "Center", "Bottom"], id: \.self) { Text(L10n.text($0)).tag($0) } }
                Toggle(L10n.text("Separate file and folder counts"), isOn: $settings.preferences.separateItemCounts)
                Toggle(L10n.text("Show tab actions"), isOn: $settings.preferences.showTabActions)
                Toggle(L10n.text("Show shelf button"), isOn: $settings.preferences.showShelfButton)
                Toggle(L10n.text("Always show operations"), isOn: $settings.preferences.alwaysShowOperations)
            }
        }
        if matches(["Confirm moving files to Trash", "Warn when changing file extensions", "Confirmations"]) {
            Section(L10n.text("Confirmations")) {
                Toggle(L10n.text("Confirm moving files to Trash"), isOn: $settings.preferences.confirmTrash)
                Toggle(L10n.text("Warn when changing file extensions"), isOn: $settings.preferences.extensionWarning)
            }
        }
        if matches(["Smooth scrolling", "Reverse tab scroll direction", "Browsing", "Single-click files", "Single-click folders", "Single-click columns", "Select on hover", "Selection checkboxes", "Double-click empty space to go up", "Browsing interactions"]) {
            Section(L10n.text("Browsing interactions")) {
                Toggle(L10n.text("Smooth scrolling"), isOn: $settings.preferences.smoothScrolling)
                Toggle(L10n.text("Reverse tab scroll direction"), isOn: $settings.preferences.reverseTabScroll)
                Toggle(L10n.text("Single-click files"), isOn: $settings.preferences.singleClickFiles)
                Toggle(L10n.text("Single-click folders"), isOn: $settings.preferences.singleClickFolders)
                Toggle(L10n.text("Single-click columns"), isOn: $settings.preferences.singleClickColumns)
                Toggle(L10n.text("Select on hover"), isOn: $settings.preferences.selectOnHover)
                Toggle(L10n.text("Selection checkboxes"), isOn: $settings.preferences.selectionCheckboxes)
                Toggle(L10n.text("Double-click empty space to go up"), isOn: $settings.preferences.doubleClickUp)
            }
        }
        if matches(["Layout", "Sort by", "Group by", "Synchronize folder preferences", "Ascending", "Group by date unit"]) {
            Section(L10n.text("Layout")) {
                Toggle(L10n.text("Synchronize folder preferences"), isOn: $settings.preferences.syncFolderPreferences)
                Picker(L10n.text("Default sorting"), selection: $settings.preferences.defaultSort) { ForEach(SortField.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
                Toggle(L10n.text("Ascending"), isOn: $settings.preferences.defaultAscending)
                Picker(L10n.text("Default grouping"), selection: $settings.preferences.defaultGroup) { ForEach(GroupField.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
                Toggle(L10n.text("Group ascending"), isOn: $settings.preferences.defaultGroupAscending)
                Picker(L10n.text("Group by date unit"), selection: $settings.preferences.defaultGroupDateUnit) { ForEach(GroupDateUnit.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
                Toggle(L10n.text("Auto-fit columns"), isOn: $settings.autoFitColumns)
            }
        }
        if matches(["Thumbnails", "Show thumbnails", "Cache thumbnails", "Thumbnail cache limit", "Clear thumbnail cache"]) {
            Section(L10n.text("Thumbnails")) {
                Toggle(L10n.text("Show thumbnails"), isOn: $settings.preferences.showThumbnails)
                Toggle(L10n.text("Cache thumbnails"), isOn: $settings.preferences.cacheThumbnails)
                    .onChange(of: settings.preferences.cacheThumbnails) { if !settings.preferences.cacheThumbnails { ThumbnailCache.shared.clear() } }
                Stepper(value: $settings.preferences.thumbnailCacheMB, in: 16...2048, step: 16) { Text(L10n.text("Thumbnail cache limit")); Text("\(settings.preferences.thumbnailCacheMB) MB").foregroundStyle(.secondary) }
                Button(L10n.text("Clear thumbnail cache")) { ThumbnailCache.shared.clear() }
                Text(L10n.text("Thumbnails are cached in memory. The limit applies to decoded images.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        if matches(["Home", "Quick access", "Drives", "Recent folders", "Recent files", "Network", "Tags", "Show status bar"]) {
            Section(L10n.text("Home")) {
                Toggle(L10n.text("Quick access"), isOn: $settings.preferences.showQuickAccess)
                Toggle(L10n.text("Drives"), isOn: $settings.preferences.showDrives)
                Toggle(L10n.text("Recent files"), isOn: $settings.preferences.showRecentFiles)
                Toggle(L10n.text("Network"), isOn: $settings.preferences.showNetwork)
                Toggle(L10n.text("Tags"), isOn: $settings.preferences.showTags)
                Toggle(L10n.text("Recent folders"), isOn: $settings.preferences.showRecentFolders)
                Toggle(L10n.text("Show status bar"), isOn: $settings.preferences.showStatusBar)
            }
        }
        if matches(["Startup", "Tabs", "Restore tabs at launch", "Startup folders", "Open folders in new tabs", "Switch to new tabs", "Open new tabs with dual panes", "Vertical split", "Startup and tabs", "Open external folders in new windows"]) {
            Section(L10n.text("Startup and tabs")) {
                Toggle(L10n.text("Open external folders in new windows"), isOn: $settings.preferences.openExternalInNewWindow)
                Toggle(L10n.text("Restore tabs at launch"), isOn: $settings.restoreTabs)
                Text(L10n.text("Startup folders are used when session restoration is disabled. An empty list opens Home.")).font(.caption).foregroundStyle(.secondary)
                ForEach(settings.preferences.startupPages, id: \.self) { path in
                    HStack { Text(path).lineLimit(1).truncationMode(.middle); Spacer(); Button(L10n.text("Remove")) { settings.preferences.startupPages.removeAll { $0 == path } } }
                }
                Button(L10n.text("Add startup folders…")) { addStartupFolders() }
                Toggle(L10n.text("Open folders in new tabs"), isOn: $settings.preferences.foldersInNewTab)
                Toggle(L10n.text("Switch to new tabs"), isOn: $settings.preferences.switchToNewTab)
                Toggle(L10n.text("Open new tabs with dual panes"), isOn: $settings.preferences.newTabsDualPane)
                Toggle(L10n.text("Vertical split"), isOn: $settings.preferences.newTabsVerticalSplit).disabled(!settings.preferences.newTabsDualPane)
            }
        }
    }
    private func addStartupFolders() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !settings.preferences.startupPages.contains(url.path) && settings.preferences.startupPages.count < 20 { settings.preferences.startupPages.append(url.path) }
    }
}
