# Files source parity audit

Baseline: current native source for build 11 (0.7.1), compared with the Files source in this checkout. This is a source-to-native mapping, not a claim of full behavioral or pixel parity. A runnable Windows reference was not used. The complete command-file inventory is classified below; many entries still need individual behavior/UI verification. The 29 command gaps and 16 partial command mappings have now been addressed with 44 native implementations/workflows and one explicit lockscreen platform boundary. Broader settings differences below still prevent a complete 1:1 claim.

## Command-gap completion pass

108 tests pass. Native UI checks cover ZIP/extract-here collision handling, alias paste, focused-item toggling, row sizing, multi-folder pin/unpin, dotfiles, filter visibility, app background, compact mode, invalid settings input, logs and TextEdit/Finder/Disk Utility/Storage handoffs. Slideshow and Trash controls were inspected without modifying wallpaper or Trash. See each row for the distinction between execution tests, UI checks and system workflows.

## Earlier build 7 changes

- Added creation-date/tag/path/cloud sorting and files-first/combined ordering; comparator tests pass.
- Added selected/current quoted paths using POSIX escaping; shell round-trip tests cover apostrophes, newlines, Unicode and command-like text.
- Added Git Sync (fast-forward pull then push); local remote tests cover successful sync and refusal after divergence.
- Added targeted new windows and Copy/Terminal actions on pinned folders. Native Home context and selected-folder new window verified. Removed duplicate application menus discovered in UI testing.
- Added saved group direction and modified-date year/month/day grouping. Native Details displayed the expected month heading; legacy presentation decoding tested.
- Added creation-date, tags and path columns and visibility controls. Creation-date column verified in native UI. Auto-fit measures content, with bounded measurement.
- Added paste into selected local folder; retained the existing transfer and conflict pipeline.
- Prevented an older address lookup from navigating after a newer request or intervening navigation.
- Earlier fixes remain: archive/library split preserves snapshots; sidebar/toolbar/extensions visibility; virtual Share/Open With; create folder with local selection.

## Command-file mapping

Status “Native mapping” identifies a native implementation, not certification of every edge case. Infrastructure rows are not user features. Partial mappings, gaps and platform boundaries are explicit.

| Original source | Status | Native behavior / remaining difference |
| --- | --- | --- |
| Actions/BaseUIAction.cs | Infrastructure | Swift command routing / observable view models replace the C# action base or interface; not a separate user feature. |
| Actions/Content/Archives/Compress/BaseCompressArchiveAction.cs | Infrastructure | Swift command routing / observable view models replace the C# action base or interface; not a separate user feature. |
| Actions/Content/Archives/Compress/CompressIntoArchiveAction.cs | Native mapping | Compression tool supports format, destination and password. ArchiveService and SevenZipService integration tests cover the backends. |
| Actions/Content/Archives/Compress/CompressIntoSevenZipAction.cs | Native mapping | Dedicated automatic-name 7z command; ArchiveWorkflows preserves existing archive names. Backend covered by existing archive tests. |
| Actions/Content/Archives/Compress/CompressIntoZipAction.cs | Native mapping | Dedicated automatic-name ZIP command; duplicate-name tests and native creation of Example.zip verified. |
| Actions/Content/Archives/Decompress/BaseDecompressArchiveAction.cs | Infrastructure | Swift command routing / observable view models replace the C# action base or interface; not a separate user feature. |
| Actions/Content/Archives/Decompress/DecompressArchive.cs | Native mapping | Destination picker with password input and batch reports; ArchiveWorkflows shares the tested extraction pipeline. |
| Actions/Content/Archives/Decompress/DecompressArchiveHere.cs | Native mapping | Stages validated extraction, then copies root contents with keep-both collisions and valid undo. Native extraction produced Example (2).txt and preserved Example.txt. |
| Actions/Content/Archives/Decompress/DecompressArchiveHereSmart.cs | Native mapping | Single meaningful archive root extracts here; multiple roots create a wrapper. Tests cover both branches and collisions. |
| Actions/Content/Archives/Decompress/DecompressArchiveToChildFolderAction.cs | Native mapping | Creates a unique archive-named child folder. Placement and duplicate-wrapper tests pass. |
| Actions/Content/Background/BaseSetAsAction.cs | Infrastructure | Swift command routing / observable view models replace the C# action base or interface; not a separate user feature. |
| Actions/Content/Background/SetAsAppBackgroundAction.cs | Native mapping | Selected image or native image picker, persisted path and opacity. Image rendering visually verified. |
| Actions/Content/Background/SetAsLockscreenBackgroundAction.cs | Platform boundary | Explicit Wallpaper settings handoff. Independent Windows lockscreen-image assignment is not exposed as a supported equivalent; this is a platform boundary, not claimed parity. |
| Actions/Content/Background/SetAsSlideshowBackgroundAction.cs | Native mapping | Persisted image list, interval, start/stop and launch resume; NSWorkspace desktop wallpaper updates while app runs. Configuration UI verified; user wallpaper was not changed. |
| Actions/Content/Background/SetAsWallpaperBackgroundAction.cs | Native mapping | MediaService image rotation and NSWorkspace desktop wallpaper integration; upstream format coverage differs. |
| Actions/Content/ImageManipulation/BaseRotateAction.cs | Infrastructure | Swift command routing / observable view models replace the C# action base or interface; not a separate user feature. |
| Actions/Content/ImageManipulation/RotateLeftAction.cs | Native mapping | MediaService image rotation and NSWorkspace desktop wallpaper integration; upstream format coverage differs. |
| Actions/Content/ImageManipulation/RotateRightAction.cs | Native mapping | MediaService image rotation and NSWorkspace desktop wallpaper integration; upstream format coverage differs. |
| Actions/Content/Install/InstallCertificateAction.cs | Native mapping | Explicit Keychain Access handoff for certificate formats. Unsupported-selection UI disabled. Trust/import remains in the system app; no certificate was installed during QA. |
| Actions/Content/Install/InstallFontAction.cs | Native mapping | Explicit Font Book handoff for font formats. Unsupported-selection UI disabled. Font validation/import remains in Font Book; no font was installed during QA. |
| Actions/Content/Install/InstallInfDriverAction.cs | Platform boundary | Windows-specific privilege, shell, driver or Start integration; not implemented as equivalent macOS behavior. |
| Actions/Content/PlayAllAction.cs | Native mapping | Selected audio/video items open through the existing multi-file open pipeline. UTType eligibility rejects folders and non-media; disabled state verified on text files. |
| Actions/Content/PreviewPopup/LaunchPreviewPopupAction.cs | Native mapping | Quick Look plus materialized virtual previews; external extension availability is OS-dependent. |
| Actions/Content/RefreshItemsAction.cs | Native mapping | Native file operation/navigation command exists; exact upstream enablement, dialogs and edge cases are not individually certified. |
| Actions/Content/Run/BaseRunAsAction.cs | Infrastructure | Swift command routing / observable view models replace the C# action base or interface; not a separate user feature. |
| Actions/Content/Run/RunAsAdminAction.cs | Platform boundary | Windows-specific privilege, shell, driver or Start integration; not implemented as equivalent macOS behavior. |
| Actions/Content/Run/RunAsAnotherUserAction.cs | Platform boundary | Windows-specific privilege, shell, driver or Start integration; not implemented as equivalent macOS behavior. |
| Actions/Content/Run/RunWithPowershellAction.cs | Platform boundary | Windows-specific privilege, shell, driver or Start integration; not implemented as equivalent macOS behavior. |
| Actions/Content/Selection/ClearSelectionAction.cs | Native mapping | Select all, clear and invert implemented in MainPageViewModel and keyboard/menu commands. |
| Actions/Content/Selection/InvertSelectionAction.cs | Native mapping | Select all, clear and invert implemented in MainPageViewModel and keyboard/menu commands. |
| Actions/Content/Selection/SelectAllAction.cs | Native mapping | Select all, clear and invert implemented in MainPageViewModel and keyboard/menu commands. |
| Actions/Content/Selection/ToggleSelectAction.cs | Native mapping | Toggles the focused item, matching original action semantics. Option-Space and native selection/deselection verified; ignores text editing focus. |
| Actions/Content/Share/ShareItemAction.cs | Native mapping | Native macOS sharing picker; virtual items materialized first. No message was sent during verification. |
| Actions/Content/Tags/OpenAllTaggedActions.cs | Native mapping | Spotlight-backed tag browser with all-tag or named-tag search and Open all. Query and empty-state UI verified; unindexed paths explicitly excluded. |
| Actions/Content/Tags/RemoveTagsAction.cs | Native mapping | Dedicated remove-all-tags command for local selection using the existing metadata service. Reports per-file errors; no false undo entry. |
| Actions/Display/AutoFitColumnsAction.cs | Native mapping | Details column content measurement, bounded to first 1,000 rows and 500-point maximum; exposed as a persistent auto-fit toggle. |
| Actions/Display/GroupAction.cs | Native mapping | Independent direction and date units plus created, cloud, path, original folder and deleted-date grouping. Trash exposes date unit controls. Grouping tests pass. |
| Actions/Display/LayoutAction.cs | Native mapping | Adaptive layout uses the original greater-than-60-percent media threshold. Increase/decrease sizes follow Details/List/Cards/Grid/Columns order and reset at boundaries; sequence tests and larger Details rows verified. Native Gallery remains an extension. |
| Actions/Display/SortAction.cs | Native mapping | Original-folder and deleted-date sorting added to Trash, alongside existing name/date/type/size/tags/path/cloud sorting. Comparator/group tests pass; Trash controls inspected. |
| Actions/Display/SortFilesAndFoldersTogetherAction.cs | Native mapping | Toolbar offers folders first, files first, or combined ordering; precedence covered by AuditParityTests. |
| Actions/Display/SortFilesFirstAction.cs | Native mapping | Toolbar offers folders first, files first, or combined ordering; precedence covered by AuditParityTests. |
| Actions/Display/SortFoldersFirstAction.cs | Native mapping | Toolbar offers folders first, files first, or combined ordering; precedence covered by AuditParityTests. |
| Actions/FileSystem/AddItemAction.cs | Native mapping | Native file operation/navigation command exists; exact upstream enablement, dialogs and edge cases are not individually certified. |
| Actions/FileSystem/BaseDeleteAction.cs | Infrastructure | Swift command routing / observable view models replace the C# action base or interface; not a separate user feature. |
| Actions/FileSystem/CopyItemFromHomeAction.cs | Native mapping | URL clipboard references available in both context menus; Home menu inspected interactively. |
| Actions/FileSystem/CopyItemPathAction.cs | Native mapping | copyPath supports selected/current local/archive/remote paths; quoted variant uses tested POSIX escaping, not Windows quoting. |
| Actions/FileSystem/CopyItemPathWithQuotesAction.cs | Native mapping | copyPath supports selected/current local/archive/remote paths; quoted variant uses tested POSIX escaping, not Windows quoting. |
| Actions/FileSystem/CopyPathAction.cs | Native mapping | copyPath supports selected/current local/archive/remote paths; quoted variant uses tested POSIX escaping, not Windows quoting. |
| Actions/FileSystem/CopyPathWithQuotesAction.cs | Native mapping | copyPath supports selected/current local/archive/remote paths; quoted variant uses tested POSIX escaping, not Windows quoting. |
| Actions/FileSystem/CreateAlternateDataStreamAction.cs | Platform boundary | Extended-attribute editor exists; macOS xattrs are not NTFS alternate data streams. |
| Actions/FileSystem/CreateFileAction.cs | Native mapping | Native file operation/navigation command exists; exact upstream enablement, dialogs and edge cases are not individually certified. |
| Actions/FileSystem/CreateFolderAction.cs | Native mapping | Native file operation/navigation command exists; exact upstream enablement, dialogs and edge cases are not individually certified. |
| Actions/FileSystem/CreateFolderWithSelectionAction.cs | Native mapping | Creates folder and moves local/mounted selection with compound undo, including the context-menu action. Upstream disables this action inside ZIP folders; custom remote virtual providers do not expose it. |
| Actions/FileSystem/CreateShortcutAction.cs | Native mapping | macOS bookmark alias creation via storage service; not Windows .lnk format. |
| Actions/FileSystem/CreateShortcutFromDialogAction.cs | Native mapping | Native arbitrary-target file/folder picker followed by alias-name input and bookmark alias creation. Picker inspected; alias backend resolution tested. |
| Actions/FileSystem/DeleteItemAction.cs | Native mapping | Native file operation/navigation command exists; exact upstream enablement, dialogs and edge cases are not individually certified. |
| Actions/FileSystem/DeleteItemPermanentlyAction.cs | Native mapping | Normal-folder permanent-delete command with Cancel as default. Confirmation inspected and cancelled; symlink test proves target preservation. |
| Actions/FileSystem/EmptyRecycleBinAction.cs | Native mapping | Native file operation/navigation command exists; exact upstream enablement, dialogs and edge cases are not individually certified. |
| Actions/FileSystem/FlattenFolderAction.cs | Native mapping | Native file operation/navigation command exists; exact upstream enablement, dialogs and edge cases are not individually certified. |
| Actions/FileSystem/FormatDriveAction.cs | Native mapping | Disk Utility handoff from command menu, Home drive card and sidebar drive menu. Disk Utility window verified; no disk was formatted. |
| Actions/FileSystem/FormatDriveFromHomeAction.cs | Native mapping | Disk Utility handoff from command menu, Home drive card and sidebar drive menu. Disk Utility window verified; no disk was formatted. |
| Actions/FileSystem/FormatDriveFromSidebarAction.cs | Native mapping | Disk Utility handoff from command menu, Home drive card and sidebar drive menu. Disk Utility window verified; no disk was formatted. |
| Actions/FileSystem/OpenFileLocationAction.cs | Native mapping | Native file operation/navigation command exists; exact upstream enablement, dialogs and edge cases are not individually certified. |
| Actions/FileSystem/OpenItemAction.cs | Native mapping | Native file operation/navigation command exists; exact upstream enablement, dialogs and edge cases are not individually certified. |
| Actions/FileSystem/PasteItemAction.cs | Native mapping | Native file operation/navigation command exists; exact upstream enablement, dialogs and edge cases are not individually certified. |
| Actions/FileSystem/PasteItemAsShortcutAction.cs | Native mapping | URL clipboard to unique Finder aliases; rejects expiring virtual staging paths. Native Paste shortcut created Example.txt alias; collision/target-resolution tests pass. |
| Actions/FileSystem/PasteItemToSelectionAction.cs | Native mapping | Selected-folder context command passes the explicit destination to existing clipboard transfer pipeline; native UI paste into a disposable selected folder verified. |
| Actions/FileSystem/RenameAction.cs | Native mapping | Native file operation/navigation command exists; exact upstream enablement, dialogs and edge cases are not individually certified. |
| Actions/FileSystem/RestoreAllRecycleBinAction.cs | Native mapping | Restore all known original locations using persistent Trash records and identity-checked storage undo. Unknown originals remain explicit Restore to choices. UI inspected; macOS denied live Trash access in QA. |
| Actions/FileSystem/RestoreRecycleBinAction.cs | Native mapping | Native file operation/navigation command exists; exact upstream enablement, dialogs and edge cases are not individually certified. |
| Actions/FileSystem/Transfer/BaseTransferItemAction.cs | Infrastructure | Swift command routing / observable view models replace the C# action base or interface; not a separate user feature. |
| Actions/FileSystem/Transfer/CopyItemAction.cs | Native mapping | Native file operation/navigation command exists; exact upstream enablement, dialogs and edge cases are not individually certified. |
| Actions/FileSystem/Transfer/CutItemAction.cs | Native mapping | Native file operation/navigation command exists; exact upstream enablement, dialogs and edge cases are not individually certified. |
| Actions/Git/GitCloneAction.cs | Native mapping | GitRepositoryView / GitService. Sync tested with local bare remote and divergent histories; Pull deliberately requires fast-forward. |
| Actions/Git/GitFetchAction.cs | Native mapping | GitRepositoryView / GitService. Sync tested with local bare remote and divergent histories; Pull deliberately requires fast-forward. |
| Actions/Git/GitInitAction.cs | Native mapping | GitRepositoryView / GitService. Sync tested with local bare remote and divergent histories; Pull deliberately requires fast-forward. |
| Actions/Git/GitPullAction.cs | Native mapping | GitRepositoryView / GitService. Sync tested with local bare remote and divergent histories; Pull deliberately requires fast-forward. |
| Actions/Git/GitPushAction.cs | Native mapping | GitRepositoryView / GitService. Sync tested with local bare remote and divergent histories; Pull deliberately requires fast-forward. |
| Actions/Git/GitSyncAction.cs | Native mapping | GitRepositoryView / GitService. Sync tested with local bare remote and divergent histories; Pull deliberately requires fast-forward. |
| Actions/Global/BaseAppThemeAction.cs | Infrastructure | Swift command routing / observable view models replace the C# action base or interface; not a separate user feature. |
| Actions/Global/EditPathAction.cs | Native mapping | Native theme, navigation/search, undo/redo and full-screen controls; no Windows visual identity claim. |
| Actions/Global/EnterCompactOverlayAction.cs | Native mapping | Floating 400×350 compact shell with sidebar/tab/info suppression; previous frame and level restored on exit. Enter and restore visually verified. |
| Actions/Global/ExitCompactOverlayAction.cs | Native mapping | Floating 400×350 compact shell with sidebar/tab/info suppression; previous frame and level restored on exit. Enter and restore visually verified. |
| Actions/Global/OpenHelpAction.cs | Native mapping | Dedicated command opens official Files documentation. |
| Actions/Global/RedoAction.cs | Native mapping | Native theme, navigation/search, undo/redo and full-screen controls; no Windows visual identity claim. |
| Actions/Global/SearchAction.cs | Native mapping | Native theme, navigation/search, undo/redo and full-screen controls; no Windows visual identity claim. |
| Actions/Global/SetDarkThemeAction.cs | Native mapping | Native theme, navigation/search, undo/redo and full-screen controls; no Windows visual identity claim. |
| Actions/Global/SetDefaultThemeAction.cs | Native mapping | Native theme, navigation/search, undo/redo and full-screen controls; no Windows visual identity claim. |
| Actions/Global/SetLightThemeAction.cs | Native mapping | Native theme, navigation/search, undo/redo and full-screen controls; no Windows visual identity claim. |
| Actions/Global/ToggleAppThemeAction.cs | Native mapping | Native theme, navigation/search, undo/redo and full-screen controls; no Windows visual identity claim. |
| Actions/Global/ToggleCompactOverlayAction.cs | Native mapping | Floating 400×350 compact shell with sidebar/tab/info suppression; previous frame and level restored on exit. Enter and restore visually verified. |
| Actions/Global/ToggleFullScreenAction.cs | Native mapping | Native theme, navigation/search, undo/redo and full-screen controls; no Windows visual identity claim. |
| Actions/Global/UndoAction.cs | Native mapping | Native theme, navigation/search, undo/redo and full-screen controls; no Windows visual identity claim. |
| Actions/IAction.cs | Infrastructure | Swift command routing / observable view models replace the C# action base or interface; not a separate user feature. |
| Actions/IToggleAction.cs | Infrastructure | Swift command routing / observable view models replace the C# action base or interface; not a separate user feature. |
| Actions/Navigation/ArrangePanesHorizontallyAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/ArrangePanesVerticallyAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/CloseActivePaneAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/CloseAllTabsAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/CloseOtherTabsSelectedAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/CloseSelectedTabAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/CloseTabBaseAction.cs | Infrastructure | Swift command routing / observable view models replace the C# action base or interface; not a separate user feature. |
| Actions/Navigation/CloseTabsToTheLeftSelectedAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/CloseTabsToTheRightSelectedAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/DuplicateSelectedTabAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/FocusOtherPane.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/NavigateBackAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/NavigateForwardAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/NavigateHomeAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/NavigateUpAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/NewTabAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/NewWindowAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/NextTabAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/OpenCurrentFolderInOtherPane/OpenCurrentFolderInOtherPaneAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/OpenInNewPane/BaseOpenInNewPaneAction.cs | Infrastructure | Swift command routing / observable view models replace the C# action base or interface; not a separate user feature. |
| Actions/Navigation/OpenInNewPane/OpenInNewPaneAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/OpenInNewPane/OpenInNewPaneFromHomeAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/OpenInNewPane/OpenInNewPaneFromSidebarAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/OpenInNewTab/BaseOpenInNewTabAction.cs | Infrastructure | Swift command routing / observable view models replace the C# action base or interface; not a separate user feature. |
| Actions/Navigation/OpenInNewTab/OpenInNewTabAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/OpenInNewTab/OpenInNewTabFromHomeAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/OpenInNewTab/OpenInNewTabFromSidebarAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/OpenInNewWindow/BaseOpenInNewWindowAction.cs | Infrastructure | Swift command routing / observable view models replace the C# action base or interface; not a separate user feature. |
| Actions/Navigation/OpenInNewWindow/OpenInNewWindowAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/OpenInNewWindow/OpenInNewWindowFromHomeAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/OpenInNewWindow/OpenInNewWindowFromSidebarAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/OpenInOtherPane/BaseOpenInOtherPaneAction.cs | Infrastructure | Swift command routing / observable view models replace the C# action base or interface; not a separate user feature. |
| Actions/Navigation/OpenInOtherPane/OpenInOtherPaneAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/OpenInOtherPane/OpenInOtherPaneFromHomeAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/OpenInOtherPane/OpenInOtherPaneFromSidebarAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/PreviousTabAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/ReopenClosedTabAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/SplitPaneHorizontallyAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Navigation/SplitPaneVerticallyAction.cs | Native mapping | MainPageViewModel, ShellPageViewModel, tab menus and Home/sidebar context actions. Split state and selected-folder new-window checked; each remaining entry point has not received individual UI verification. |
| Actions/Open/CustomizeToolbarAction.cs | Native mapping | Native tools/settings/properties/Terminal commands. See properties and settings comparison below; entry-by-entry UI verification incomplete. |
| Actions/Open/EditInNotepadAction.cs | Native mapping | Dedicated TextEdit handoff. Example.txt opened with the expected fixture content in TextEdit. |
| Actions/Open/OpenClassicPropertiesAction.cs | Native mapping | Finder Get Info through the Finder scripting dictionary, explicit errors and native-properties fallback. Example.txt Info displayed in Finder. Reveal-before-open addresses closed-window activation. |
| Actions/Open/OpenCommandPaletteAction.cs | Native mapping | Native tools/settings/properties/Terminal commands. See properties and settings comparison below; entry-by-entry UI verification incomplete. |
| Actions/Open/OpenInIDEAction.cs | Native mapping | Persisted application picker and selected/current-path launch via NSWorkspace; paths are URL arguments rather than shell interpolation. |
| Actions/Open/OpenLogFileAction.cs | Native mapping | Bounded private operation log and in-app selectable viewer; viewer and operation records verified. Rotation preserves UTF-8 line boundaries. |
| Actions/Open/OpenLogFileLocationAction.cs | Native mapping | Reveals the log file in Finder; Logs window and operations.log selection verified. |
| Actions/Open/OpenPropertiesAction.cs | Native mapping | Native tools/settings/properties/Terminal commands. See properties and settings comparison below; entry-by-entry UI verification incomplete. |
| Actions/Open/OpenReleaseNotesAction.cs | Native mapping | Dedicated command opens bundled port notes in TextEdit; offline content ships in the app. |
| Actions/Open/OpenRepoInIDEAction.cs | Native mapping | Configured IDE launch resolves the repository root using the existing tested GitService.inspect operation. |
| Actions/Open/OpenSettingsAction.cs | Native mapping | Native tools/settings/properties/Terminal commands. See properties and settings comparison below; entry-by-entry UI verification incomplete. |
| Actions/Open/OpenSettingsFileAction.cs | Native mapping | Versioned JSON editor, import/export/reload and validate-before-apply. Covers preferences, shortcuts, toolbar, favorites, cloud folders, libraries, searches and folder presentations. Invalid JSON UI and invalid-settings tests pass. |
| Actions/Open/OpenStorageSenseAction.cs | Native mapping | Storage settings handoff from command menu, Home drive card and sidebar drive menu. The actual Storage settings pane was verified. |
| Actions/Open/OpenStorageSenseFromHomeAction.cs | Native mapping | Storage settings handoff from command menu, Home drive card and sidebar drive menu. The actual Storage settings pane was verified. |
| Actions/Open/OpenStorageSenseFromSidebarAction.cs | Native mapping | Storage settings handoff from command menu, Home drive card and sidebar drive menu. The actual Storage settings pane was verified. |
| Actions/Open/OpenTerminalAction.cs | Native mapping | Native tools/settings/properties/Terminal commands. See properties and settings comparison below; entry-by-entry UI verification incomplete. |
| Actions/Open/OpenTerminalAsAdminAction.cs | Platform boundary | Windows-specific privilege, shell, driver or Start integration; not implemented as equivalent macOS behavior. |
| Actions/Open/OpenTerminalFromHomeAction.cs | Native mapping | Native tools/settings/properties/Terminal commands. See properties and settings comparison below; entry-by-entry UI verification incomplete. |
| Actions/Open/OpenTerminalFromSidebarAction.cs | Native mapping | Native tools/settings/properties/Terminal commands. See properties and settings comparison below; entry-by-entry UI verification incomplete. |
| Actions/Shelf/CopyItemFromShelfAction.cs | Native mapping | ShelfStore and shelf tool; individual cut/delete entry points require UI equivalence review. |
| Actions/Shelf/CutItemFromShelfAction.cs | Native mapping | ShelfStore and shelf tool; individual cut/delete entry points require UI equivalence review. |
| Actions/Shelf/DeleteItemFromShelfAction.cs | Native mapping | ShelfStore and shelf tool; individual cut/delete entry points require UI equivalence review. |
| Actions/Show/ToggleDetailsPaneAction.cs | Native mapping | View/menu state supports sidebar, toolbar, extensions, hidden items, split/details/preview/shelf; native presentation differs from WinUI. |
| Actions/Show/ToggleDotFilesSettingAction.cs | Native mapping | Independent dotfile visibility with migration from previous hidden setting. Dotfile filtering test and .audit-hidden UI visibility verified. |
| Actions/Show/ToggleDualPaneAction.cs | Native mapping | View/menu state supports sidebar, toolbar, extensions, hidden items, split/details/preview/shelf; native presentation differs from WinUI. |
| Actions/Show/ToggleFilterHeaderAction.cs | Native mapping | Independent persisted filter/search-header toggle; header disappears in native UI. |
| Actions/Show/ToggleInfoPaneAction.cs | Native mapping | View/menu state supports sidebar, toolbar, extensions, hidden items, split/details/preview/shelf; native presentation differs from WinUI. |
| Actions/Show/TogglePreviewPaneAction.cs | Native mapping | View/menu state supports sidebar, toolbar, extensions, hidden items, split/details/preview/shelf; native presentation differs from WinUI. |
| Actions/Show/ToggleShelfPaneAction.cs | Native mapping | View/menu state supports sidebar, toolbar, extensions, hidden items, split/details/preview/shelf; native presentation differs from WinUI. |
| Actions/Show/ToggleShowFileExtensionsAction.cs | Native mapping | View/menu state supports sidebar, toolbar, extensions, hidden items, split/details/preview/shelf; native presentation differs from WinUI. |
| Actions/Show/ToggleShowHiddenItemsAction.cs | Native mapping | View/menu state supports sidebar, toolbar, extensions, hidden items, split/details/preview/shelf; native presentation differs from WinUI. |
| Actions/Show/ToggleSidebarAction.cs | Native mapping | View/menu state supports sidebar, toolbar, extensions, hidden items, split/details/preview/shelf; native presentation differs from WinUI. |
| Actions/Show/ToggleToolbarAction.cs | Native mapping | View/menu state supports sidebar, toolbar, extensions, hidden items, split/details/preview/shelf; native presentation differs from WinUI. |
| Actions/Sidebar/CopyItemFromSidebarAction.cs | Native mapping | URL clipboard references available in both context menus; Home menu inspected interactively. |
| Actions/Sidebar/PinFolderToSidebarAction.cs | Native mapping | Pins all selected local folders or the current folder. PinA and PinB appeared together in the sidebar. |
| Actions/Sidebar/UnpinFolderToSidebarAction.cs | Native mapping | Unpins all selected local folders; both PinA and PinB disappeared together in the UI. |
| Actions/Start/PinToStartAction.cs | Platform boundary | Windows-specific privilege, shell, driver or Start integration; not implemented as equivalent macOS behavior. |
| Actions/Start/UnpinFromStartAction.cs | Platform boundary | Windows-specific privilege, shell, driver or Start integration; not implemented as equivalent macOS behavior. |

## Settings-page comparison

The inventory contains 183 distinct ViewModel binding names across 11 pages; these include commands and metadata, not 183 independent preferences.

| Original page | Native coverage and unresolved controls |
| --- | --- |
| Views/Settings/AboutPage.xaml | Bundled licenses, app/OS version copy, port notes, source and upstream issue links, documentation and diagnostics. Upstream donation, Discord, Crowdin, privacy-policy and anonymous user-ID controls are not reproduced as port services. |
| Views/Settings/ActionsPage.xaml | Custom shortcuts, conflicts, recording, import/export and reset. Commands also use native menus; not every upstream action is individually configurable through the native shortcut editor. |
| Views/Settings/AdvancedPage.xaml | Settings JSON export/import/editor, folder handler, bounded memory thumbnail cache and clear/disable controls. Login launch uses SMAppService; background lifetime and menu-bar access are implemented. Login registration was not changed during QA. Finder desktop and other applications’ Open/Save dialogs remain system components. |
| Views/Settings/AppearancePage.xaml | Theme/accent/background, compact rows, image opacity/stretch/alignment, native font and backdrop, tab actions, shelf toggle, toolbar/status visibility, separate counts and persistent Operations access. Arial and Sidebar material visually checked. The 20 background presets from AppThemeResourcesFactory are implemented; the earlier claim of an upstream per-resource color editor was incorrect. |
| Views/Settings/DevToolsPage.xaml | IDE app picker/test/launch and repository IDE action. GitHub account stores an opt-in PAT in Keychain and uses a host-scoped credential helper. This differs from upstream OAuth device authorization. Empty/disabled account UI and malformed-input rejection checked; live account authentication not tested. |
| Views/Settings/FoldersPage.xaml | Hidden/dotfiles/extensions, thumbnails, selection checkboxes, single-click preferences, new-tab folders, confirmation policy, extension warning, hover selection and empty-space Up. Previous-folder selection, size units and asynchronous local folder-size calculation implemented/tested. Folder-size/date UI checked. Windows protected-file/ADS semantics differ; optional on-device FoundationModels search translates queries to validated filters on supported Apple Intelligence systems, with literal fallback; live generation is not certified. |
| Views/Settings/GeneralPage.xaml | Language/date format, restored or specific startup pages, foreground/background tabs, dual-pane defaults, Home widgets, context-menu visibility, scroll inertia/tab-wheel direction and restart. Recent files/network/tag widgets and date format inspected. External folder URLs can open in new native windows or tabs according to the new preference; this uses one native app process rather than Windows process instances. |
| Views/Settings/LayoutPage.xaml | Shared layouts, per-folder or synchronized presentation, default sort/group/direction/date units, adaptive media threshold, size cycling, columns and auto-fit. Details initial column sizing fixed and visually checked so Date/Type/Size/Cloud remain visible. |
| Views/Settings/SettingsPage.xaml | Localized section/label search, matching headings and an explicit empty-search state. Generated index tracks search keywords; native grouped settings replace the upstream navigation/control hierarchy. |
| Views/Settings/TagsPage.xaml | Saved named/color tags, validation, metadata-preserving rename/remove, saved-tag picker and indexed tag browser. Creation/color UI and preservation tests pass. Global changes depend on Spotlight indexing and retain catalog entries on failure. Custom hex colors and stable UUID records are retained in a MacFiles xattr alongside Finder palette metadata. Global rename still depends on Spotlight indexing. |
| Views/Settings/ToolbarCustomizationPage.xaml | Context-specific ordered entries, add/remove/reorder, search, visibility, apply/discard, reset, persistence and JSON transfer. Prior UI checks cover editing; exact upstream control equivalence is not certified. |

## Properties comparison

| Page / behavior | Native status |
| --- | --- |
| General and details | File metadata, attributes, names, size calculation and media details; local and virtual views differ by provider capability. |
| Security | POSIX permissions, owner/group and ACLs; not Windows security descriptors/UAC inheritance semantics. |
| Customization | Folder layout and custom icons; new grouping preferences preserved when saving layout. |
| Hashes | Native hashing; virtual items staged when supported. |
| Shortcut | Native alias/symlink inspection and retargeting; Windows .lnk editing not implemented. |
| Library | Native folder collections; not Windows .library-ms shell integration. |
| Cloud | Public iCloud/File Provider metadata and supported actions; private provider sync APIs unavailable. Live user cloud mutation not tested. |
| Compatibility | Mach-O / executable information; Windows compatibility modes do not map to macOS. |
| Signatures | Native code-signature inspection; not Windows Authenticode equivalence. |
| Extended attributes | Native xattrs; not NTFS ADS. |

## Verification limits

108 tests passed on the current source, including the stale-navigation guard. Native UI: selected-folder window, unique menu bar, creation-date column and month grouping checked. Other new paths are source/test checked only. Runtime checked on Apple Silicon/macOS 27.2; Intel and macOS 14–26 untested. Localized catalogs checked structurally; not all translations reviewed by fluent speakers. Auto-fit and paste-to-selection passed final interactive checks. The stale-request guard has compiled/test-suite coverage but no deterministic delayed-request UI reproduction. The isolated audit app encountered slow metadata reads under protected user folders; disposable /tmp fixtures worked. No user files were edited during these checks.

## Build 8 final verification and remaining differences

The previous 29 gaps and 16 partial command rows now map to 44 native workflows plus the explicit independent-lockscreen-image boundary. This classification does not certify full Files parity. All 172 command sources and 11 settings pages are inventoried; the 183 distinct settings binding names include view state and commands as well as preferences. Remaining portable differences are listed in their settings rows above rather than being mislabeled as OS restrictions.

Drag/drop now resolves the collection destination from the pointer, defers collection reload during a drag, and uses the shared validated receiver with copy/move negotiation. The private-pasteboard destination/operation test passes. A physical automated drag did not complete in either MacFiles or the Finder comparison; the user subsequently confirmed that dragging works and requested focus on visual parity. Independent automated drag completion, including drag-out to other applications, is not certified by this pass. Earlier file-promise backend and UI evidence is retained as historical evidence only.

Additional UI checks used disposable fixtures and isolated preferences: Home widgets, tag creation/color, single-click folder navigation, Details folder sizes and universal dates, visible Details columns, settings heading search, Arial font/Sidebar material and GitHub secure-field/disabled actions. An observed MenuBarExtra startup feedback loop was fixed and startup rechecked. No credentials were stored, login item registered, live cloud action performed, certificate/font installed or wallpaper changed. Additional checks of the final packaged binary are recorded in MacFiles-verification.json.

The 100-test run includes all prior 85 tests plus 15 audit-completion tests, with no skips and the loopback SFTP password fixture enabled. Catalog validation covers 1,066 native keys in 49 locales. Machine translations have not received fluent-speaker review in all locales. The universal binary targets macOS 14; runtime QA covers Apple Silicon/macOS 27.2 only. Signing is ad-hoc, not Developer ID notarization.

Final universal release UI: settings empty-search feedback, context-menu action removal, Home rendering and mouse-wheel tab switching passed. Restart exposed a still-open-sheet process leak; ending/dismissing the sheet before relaunch fixed it. Retest restored the fixture tab and left a single process.

## Build 9 visual comparison and verification

Compared the checked-out MainPage/HomePage/QuickAccessWidget XAML and FilesScreenshot.png against the native window. Moved navigation across the full window width; matched compact tabs, right caption controls, command-bar alignment, rounded content, neutral light/dark surfaces, source folder/Home/drive artwork, six-column Quick access and collapsible Home sections. Settings is now an in-window category page with integrated shortcut editing. Text-file icons retain visible outlines in light mode. Existing customized toolbar configurations are preserved; new defaults include Share and Properties.

Interactive checks: dark/light Home, collapse/expand, General/Appearance/Actions settings navigation, light theme switch, address navigation to isolated /tmp fixtures, Details/Icons and inline recursive search/clear. UI testing exposed a recursive alias-resolution crash and a search-focus bug; both were fixed. Folder/alias/symlink navigation now has a regression test. All 108 tests pass without skips. The user confirms dragging works.

This is source/screenshot-based comparison, not a measured pixel-diff certification against a running Windows app. Native system controls, virtual-location navigation, some secondary dialogs and Settings row composition retain differences. Runtime Intel/older-macOS coverage and fluent review of all translations remain unverified.

## Build 10 dialogs and virtual navigation

Archive and FTP/FTPS/SFTP folders now use the same full-width breadcrumb/address/search bar and Back/Forward/Up/Refresh controls as local folders. Removed the separate archive/remote headers and bottom button strips. Extract/Add and remote Upload/Download/Disconnect/conflict controls remain available in the shared toolbar overflow. Archive paths validate against existing entries, normalize dot segments within root, and preserve history. Remote typed navigation now truncates forward history correctly after Back. Empty virtual folders use the same empty-state presentation.

Tool dialogs now use a centered, dimmed overlay with a shared 8-pixel rounded frame, 24-pixel content margins and footer dismissal, replacing the fixed native sheet. Properties uses the original 200-pixel navigation column and rounded content panel for both local and virtual items; metadata rows support selection/copy. Compression and bulk rename use 440-pixel card content. Rename/New-item prompts use native AppKit input and button targets within the Files-style frame; this avoids the stale-value problem discovered in the first SwiftUI prompt. Background controls are disabled while a tool dialog is open.

Interactive evidence: local Properties General/Hashes and dismissal; nested ZIP navigation and Back/Forward/Up; loopback FTP connection, folder open, Back and typed path; dark compression cards and successful archive creation; bulk rename preview; rename button changes Example.txt to Renamed.txt and Undo restores it. Three additional regression tests cover archive path/history/search, remote path dispatch and remote history branching. 108 tests pass without skips.

The reference is checked-out XAML and screenshot assets, not a running Windows pixel-diff test. OS file pickers, sharing, permission/security confirmations and OS-specific Properties data retain native macOS behavior. Exact upstream animation, typography and every dialog control are not certified as identical. Historical build-9 visual limitations above describe that earlier build.

## Build 11 inline rename

Single-item Rename and F2 now edit the filename at its displayed position instead of opening a dialog. The same editor serves Details, icons/list/tiles, Columns and Gallery, including archive and remote file names. Enter validates and commits; Escape or focus loss cancels. The initial selection excludes the final file extension, while directories select the entire name. Bulk rename retains its preview dialog. Offscreen selected items in Details/Icons are scrolled into view before editing.

Interactive checks verified Details commit, Escape cancellation, icon-view commit and F2 activation, with the basename selected and no dialog. Existing storage/virtual undo and extension-warning paths are retained. The full suite passes 110 tests, including editor commit/cancel/invalid-name validation and Unicode/extension selection.

## Build 12 navigation, dialog checks, and distribution

Added per-breadcrumb folder menus for local, archive and connected remote locations. Archive menus include implicit parent directories. Up from an archive root returns to its containing local folder and selects the archive. Network connection fields use grouped, scrollable cards; Port remains labeled when populated. Dialog buttons show disabled state. Connection dialogs use a 600-point preferred width.

Rendered the actual SwiftUI dialog views for Properties, connection, compression, bulk rename and toolbar customization; Properties and connection were also checked at the 860 × 560 minimum window size. These are app-hosted render checks, not automated external mouse/keyboard tests. Home launch was checked in the packaged debug app. The earlier desktop-control tool was unavailable; macOS denied the fallback harness assistive/event-posting access. Full live click-through and exact Windows pixel parity remain unverified.

Distribution now keeps one runnable MacFiles.app at the repository root. Generated development/test app bundles and redundant development archives are removed after validating the root app. Build defaults target that same root path to avoid accumulating Spotlight results. Source, reports and one portable ZIP remain available.
