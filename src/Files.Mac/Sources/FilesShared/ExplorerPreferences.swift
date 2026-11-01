import Foundation

public struct ExplorerPreferences: Codable, Equatable, Sendable {
    public var openExternalInNewWindow = false
    public var naturalLanguageSearch = false
    public var smoothScrolling = true
    public var reverseTabScroll = false
    public var showTabActions = true
    public var showShelfButton = false
    public var hiddenContextActions: [String] = []
    public var fontFamily: String = "System"
    public var backdrop: String = "Solid"
    public var closeToBackground = false
    public var showMenuBarIcon = false
    public var sizeUnits: String = "Decimal"
    public var dateFormat: String = "System"
    public var calculateFolderSizes: Bool = false
    public var selectPreviousFolder: Bool = true
    public var backgroundFit: String = "Fill"
    public var backgroundHorizontal: String = "Center"
    public var backgroundVertical: String = "Center"
    public var separateItemCounts: Bool = false
    public var alwaysShowOperations: Bool = false
    public var confirmTrash: Bool = true
    public var extensionWarning: Bool = true
    public var syncFolderPreferences: Bool = false
    public var defaultSort: SortField = .name
    public var defaultAscending: Bool = true
    public var defaultGroup: GroupField = .none
    public var defaultGroupAscending: Bool = true
    public var defaultGroupDateUnit: GroupDateUnit = .relative
    public var showThumbnails: Bool = true
    public var cacheThumbnails: Bool = true
    public var thumbnailCacheMB: Int = 128
    public var showStatusBar: Bool = true
    public var showQuickAccess: Bool = true
    public var showDrives: Bool = true
    public var showRecentFiles = true
    public var showNetwork = true
    public var showTags = true
    public var showRecentFolders: Bool = false
    public var startupPages: [String] = []
    public var foldersInNewTab: Bool = false
    public var switchToNewTab: Bool = true
    public var newTabsDualPane: Bool = false
    public var newTabsVerticalSplit: Bool = false
    public var singleClickFiles = false
    public var singleClickFolders = false
    public var singleClickColumns = true
    public var selectOnHover = false
    public var selectionCheckboxes = false
    public var doubleClickUp = false
    public func opensOnSingleClick(directory: Bool) -> Bool { directory ? singleClickFolders : singleClickFiles }
    public init() {}
    enum CodingKeys: String, CodingKey { case openExternalInNewWindow, naturalLanguageSearch, smoothScrolling, reverseTabScroll, showTabActions, showShelfButton, hiddenContextActions, fontFamily, backdrop, closeToBackground, showMenuBarIcon, sizeUnits, dateFormat, calculateFolderSizes, selectPreviousFolder, backgroundFit, backgroundHorizontal, backgroundVertical, separateItemCounts, alwaysShowOperations, confirmTrash, extensionWarning, showRecentFiles, showNetwork, showTags, singleClickFiles, singleClickFolders, singleClickColumns, selectOnHover, selectionCheckboxes, doubleClickUp, syncFolderPreferences, defaultSort, defaultAscending, defaultGroup, defaultGroupAscending, defaultGroupDateUnit, showThumbnails, cacheThumbnails, thumbnailCacheMB, showStatusBar, showQuickAccess, showDrives, showRecentFolders, startupPages, foldersInNewTab, switchToNewTab, newTabsDualPane, newTabsVerticalSplit }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        openExternalInNewWindow = try values.decodeIfPresent(Bool.self, forKey: .openExternalInNewWindow) ?? false
        naturalLanguageSearch = try values.decodeIfPresent(Bool.self, forKey: .naturalLanguageSearch) ?? false
        smoothScrolling = try values.decodeIfPresent(Bool.self, forKey: .smoothScrolling) ?? true
        reverseTabScroll = try values.decodeIfPresent(Bool.self, forKey: .reverseTabScroll) ?? false
        showTabActions = try values.decodeIfPresent(Bool.self, forKey: .showTabActions) ?? true
        showShelfButton = try values.decodeIfPresent(Bool.self, forKey: .showShelfButton) ?? false
        hiddenContextActions = try values.decodeIfPresent([String].self, forKey: .hiddenContextActions) ?? []
        fontFamily = try values.decodeIfPresent(String.self, forKey: .fontFamily) ?? "System"
        backdrop = try values.decodeIfPresent(String.self, forKey: .backdrop) ?? "Solid"
        closeToBackground = try values.decodeIfPresent(Bool.self, forKey: .closeToBackground) ?? false
        showMenuBarIcon = try values.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? false
        sizeUnits = try values.decodeIfPresent(String.self, forKey: .sizeUnits) ?? "Decimal"
        dateFormat = try values.decodeIfPresent(String.self, forKey: .dateFormat) ?? "System"
        calculateFolderSizes = try values.decodeIfPresent(Bool.self, forKey: .calculateFolderSizes) ?? false
        selectPreviousFolder = try values.decodeIfPresent(Bool.self, forKey: .selectPreviousFolder) ?? true
        backgroundFit = try values.decodeIfPresent(String.self, forKey: .backgroundFit) ?? "Fill"
        backgroundHorizontal = try values.decodeIfPresent(String.self, forKey: .backgroundHorizontal) ?? "Center"
        backgroundVertical = try values.decodeIfPresent(String.self, forKey: .backgroundVertical) ?? "Center"
        separateItemCounts = try values.decodeIfPresent(Bool.self, forKey: .separateItemCounts) ?? false
        alwaysShowOperations = try values.decodeIfPresent(Bool.self, forKey: .alwaysShowOperations) ?? false
        confirmTrash = try values.decodeIfPresent(Bool.self, forKey: .confirmTrash) ?? true
        extensionWarning = try values.decodeIfPresent(Bool.self, forKey: .extensionWarning) ?? true
        showRecentFiles = try values.decodeIfPresent(Bool.self, forKey: .showRecentFiles) ?? true
        showNetwork = try values.decodeIfPresent(Bool.self, forKey: .showNetwork) ?? true
        showTags = try values.decodeIfPresent(Bool.self, forKey: .showTags) ?? true
        singleClickFiles = try values.decodeIfPresent(Bool.self, forKey: .singleClickFiles) ?? false
        singleClickFolders = try values.decodeIfPresent(Bool.self, forKey: .singleClickFolders) ?? false
        singleClickColumns = try values.decodeIfPresent(Bool.self, forKey: .singleClickColumns) ?? true
        selectOnHover = try values.decodeIfPresent(Bool.self, forKey: .selectOnHover) ?? false
        selectionCheckboxes = try values.decodeIfPresent(Bool.self, forKey: .selectionCheckboxes) ?? false
        doubleClickUp = try values.decodeIfPresent(Bool.self, forKey: .doubleClickUp) ?? false

        syncFolderPreferences = try values.decodeIfPresent(Bool.self, forKey: .syncFolderPreferences) ?? false
        defaultSort = try values.decodeIfPresent(SortField.self, forKey: .defaultSort) ?? .name
        defaultAscending = try values.decodeIfPresent(Bool.self, forKey: .defaultAscending) ?? true
        defaultGroup = try values.decodeIfPresent(GroupField.self, forKey: .defaultGroup) ?? .none
        defaultGroupAscending = try values.decodeIfPresent(Bool.self, forKey: .defaultGroupAscending) ?? true
        defaultGroupDateUnit = try values.decodeIfPresent(GroupDateUnit.self, forKey: .defaultGroupDateUnit) ?? .relative
        showThumbnails = try values.decodeIfPresent(Bool.self, forKey: .showThumbnails) ?? true
        cacheThumbnails = try values.decodeIfPresent(Bool.self, forKey: .cacheThumbnails) ?? true
        thumbnailCacheMB = try values.decodeIfPresent(Int.self, forKey: .thumbnailCacheMB) ?? 128
        showStatusBar = try values.decodeIfPresent(Bool.self, forKey: .showStatusBar) ?? true
        showQuickAccess = try values.decodeIfPresent(Bool.self, forKey: .showQuickAccess) ?? true
        showDrives = try values.decodeIfPresent(Bool.self, forKey: .showDrives) ?? true
        showRecentFolders = try values.decodeIfPresent(Bool.self, forKey: .showRecentFolders) ?? false
        startupPages = try values.decodeIfPresent([String].self, forKey: .startupPages) ?? []
        foldersInNewTab = try values.decodeIfPresent(Bool.self, forKey: .foldersInNewTab) ?? false
        switchToNewTab = try values.decodeIfPresent(Bool.self, forKey: .switchToNewTab) ?? true
        newTabsDualPane = try values.decodeIfPresent(Bool.self, forKey: .newTabsDualPane) ?? false
        newTabsVerticalSplit = try values.decodeIfPresent(Bool.self, forKey: .newTabsVerticalSplit) ?? false
    }
    public var isValid: Bool { fontFamily.count <= 256 && ["Solid", "Sidebar", "Under window", "HUD"].contains(backdrop) && hiddenContextActions.count <= 100 && ["Decimal", "Binary", "Bytes"].contains(sizeUnits) && ["Application", "System", "Universal"].contains(dateFormat) && ["None", "Stretch", "Fit", "Fill"].contains(backgroundFit) && ["Left", "Center", "Right"].contains(backgroundHorizontal) && ["Top", "Center", "Bottom"].contains(backgroundVertical) && (16...2048).contains(thumbnailCacheMB) && startupPages.count <= 20 && startupPages.allSatisfy { $0.hasPrefix("/") } }
}
