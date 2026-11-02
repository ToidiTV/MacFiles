# MacFiles — native macOS port of Files, build 11 (0.7.1)

This is a working native application built from the Files feature set and layer structure in this repository. This build implements virtual cut and drag-out, shared layouts and toolbar contexts, virtual properties, and native interface translations. It follows Files workflows using native macOS APIs. **A complete control-by-control and pixel-for-pixel match with upstream Files has not been established**; platform and verification boundaries are documented below. The Windows solution is unchanged. The macOS implementation is in `src/Files.Mac`.

## Build 8 completion pass

The 29 command gaps and 16 partial mappings were addressed with 44 native workflows and one explicit lockscreen boundary. Added archive quick actions, aliases, selection and layout commands, system handoffs, slideshow settings, tag browsing, settings transfer, startup/Home/layout/interaction preferences, saved colored tags, font/material/background controls, date/size formats, folder sizes, context-menu customization, IDE configuration, a Keychain-backed GitHub PAT helper, background/menu-bar behavior and login-launch control. Fixed single-click tracking, collection drag refresh/destination routing, Details column sizing and a startup feedback loop. The app retains Shared/Storage/App boundaries.

108 tests pass without skips; 1,064 native keys validate across 49 locales. The user confirmed dragging works; automated physical drag completion remains unverified. This build reconstructs the Files shell, Home widgets and in-window Settings navigation from the checked-out XAML and screenshot references. It also adds the original 20 background presets, external-folder window preference, stable custom-color tag metadata and optional on-device natural-language search. GitHub still uses PAT authorization rather than upstream OAuth. See PARITY-AUDIT.md and the packaged verification report for precise coverage and remaining differences. Full pixel-for-pixel parity has not been certified.

## Build 7 audit changes

Added creation-date/tag/path/cloud sorting, files-first/combined ordering, POSIX-quoted paths, targeted new windows, pinned-folder clipboard/Terminal actions, Git Sync, group direction and date units, selectable Details columns, content-based auto-fit, and paste into a selected local folder. Fixed duplicate application menus, preserved grouping from properties, and guarded stale asynchronous address requests. The source comparison now classifies every command file and settings page in PARITY-AUDIT.md. This inventory is not full parity certification: portable feature gaps and unverified entry points remain.

## Architecture

| Original Files area | Native implementation |
| --- | --- |
| Files.Shared models | FilesShared: listed items, navigation, grouping, layouts, session snapshots, libraries and themes |
| Files.Storage services | FilesStorage: directory listing, watching, serial file operations, undo/redo, archives, Git, remote providers, search and metadata |
| MainPage / ModernShellPage / ShellPanesPage | MainPageViewModel, ShellPageViewModel, ExplorerWindow and ShellView |
| Layout controls | AppKit NSTableView / NSCollectionView and SwiftUI columns / gallery |
| Commands, dialogs and services | ExplorerCommands, command palette, ToolSheet and native macOS panels |
| Windows shell, COM, WinRT | FileManager, NSWorkspace, NSPasteboard, Quick Look and asynchronous Swift services |
| Original localized resources | 49 upstream resource locales plus complete native catalogs, plural rules, interpolation and right-to-left presentation |

The layer boundaries and MVVM approach are preserved. Swift/AppKit replaces C#/WinUI; the two platforms do not share a runtime or binary ABI. There is no Windows VM, Wine or embedded browser.

## Implemented feature coverage

| Area | Native behavior |
| --- | --- |
| Shell | Home, pinned folders, expandable sidebar trees, volume capacity, mounted drives and locally available cloud folders |
| Windows and tabs | Independent application windows, tab reordering, duplicate/reopen/close-left/right/others; restoration of layouts, libraries and split panes |
| Navigation | Breadcrumbs, editable paths, back/forward/up, refresh, folder chooser and native folder-open service |
| Panes | Side-by-side or top/bottom panes, other-pane navigation, focus switching and details pane |
| Layouts | Ten shared layout modes across local, archive and remote panes: Details, five icon sizes, list, tiles, columns and Quick Look gallery; shared selection/filter/sort/group, nested columns, file promises and per-location presentation |
| File operations | Create folder/file/from-template, copy/cut/paste/move, duplicate, rename, bulk rename, alias, Trash, flatten folders, native sharing and Open With |
| Conflicts | Keep both, Skip existing or Replace; replacements are moved to Trash; staged copies avoid exposing incomplete destination files |
| Undo / redo | Persistent bounded local journal shared across windows, identity checks, batch rename swaps, replacement recovery and archive/media-edit undo; compound cross-provider undo and persisted remote recovery steps; reconnect to the same server/account to use remote history after restart |
| Bulk rename | Numbered names, find/replace, prefix/suffix, preview, extension preservation, collision preflight and rollback |
| File shelf | Persistent references collected across folders, then copied or moved together |
| Archives | Restored virtual tabs, folder history, shared layouts/custom toolbar/properties, filtering, preview, clipboard copy/cut, native drag-out, paste/drop/add/create/rename/remove/permissions with whole-archive undo; ZIP / 7z / TAR / TAR.GZ / TAR.BZ2; encrypted ZIP/7z and split ZIP/7z volumes; safe link extraction |
| Git | Repository status, staged/working diffs, stage/unstage, commit, branch create/switch, history, remotes, initialize, clone, fetch, fast-forward pull and push |
| Remote files | FTP, explicit FTPS and SFTP virtual tabs; keys, password/passphrase via private askpass, explicit host-fingerprint review, optional Keychain; recursive upload/download, shared layouts/custom toolbar/properties, preview, copy/cut/paste, native file-promise drag-out/drop upload, create/rename/permissions, conflict choices, recovery-folder removal, global undo/redo and periodic listing refresh |
| Network volumes | macOS mount handoff for SMB/AFP/WebDAV; mounted volumes appear under Drives; eject support |
| Search | Live filtering and recursive advanced filters; streaming UTF-8, bounded UTF-16, PDF text and Office/OpenDocument XML content; cancellation, skipped-item counts and saved searches |
| Metadata | Image rotation and wallpaper, embedded image/media metadata editing with original-file recovery, Quick Look, file dates/kind/size/tags, recursive folder size, MD5/SHA-1/SHA-256/SHA-512, native tag editing, POSIX permissions, extended attribute viewing/editing/export |
| Trash | Accessible Trash locations across mounted volumes, original-location restore for MacFiles deletions across launches, restore elsewhere, explicit permanent-delete/empty confirmation |
| Preferences | System/light/dark appearance, imported/exported color themes, compact rows, per-folder layout/sort/group, hidden files, folders first, language and multi-folder libraries |
| Toolbar | Context-specific customization, add/remove/reorder, separators, icon/label controls, live preview, apply/discard, reset and JSON import/export |
| Properties | Local General/allocated size/flags, Spotlight details, POSIX permissions and ACL/owner editing, custom icons, alias/link retargeting, libraries, compatibility, hashes and signatures. Virtual General, Details, Security, Hashes, Preview, Customization, Compatibility and Signatures use actual archive/server metadata and materialize content on demand. |
| Cloud status | iCloud download/upload/pending/conflict/error/synced metadata; third-party provider local availability from dataless flags; badges, status column, polling, explicit download and guarded iCloud eviction; detected/custom provider folders and handoff to provider account applications |
| Localization | All 49 locales include native labels, dialogs and errors; upstream translations are reused, missing text is translated locally with a pinned model, German and Arabic corrections are applied, and Files plural forms are converted to native strings dictionaries. |
| Operations | Per-window serial queue for local files, archives, remote mutations and Git mutations; cancellation, completed/error history; native copyfile cancellation during copies |
| Commands | Native menus, configurable keyboard bindings with conflict detection/recording/JSON import/export, command palette, selection inversion, always-on-top and full-screen actions |
| Integration | Quick Look, native thumbnails/icons, Terminal, Finder reveal, aliases, package browsing and optional folder-URL handler registration with restoration |

## Transfer and presentation behavior

- Cut stages a snapshot, fingerprints its contents, verifies the destination, then rechecks every source before removal. Copy failures, skipped items or changed contents retain the source. Local identity checks also reject a replacement with identical bytes. Archive removals retain the original archive; remote removals retain items in `.MacFiles-Recovery`.
- Cut/paste within MacFiles consumes a single-use receipt and groups destination creation with source recovery in one undo operation. A failed remote undo keeps the destination available for recovery and can be retried after reconnecting. FTP/SFTP have no transaction spanning arbitrary servers, so concurrent remote mutations cannot be eliminated completely.
- Drag-out uses native file promises for files and folders. Downloads/extraction happen when the receiver requests them, with the original provider retained even if its tab closes. External applications receive copies. The clipboard also exposes materialized copies to other apps; only MacFiles consumes its virtual-cut receipt and removes the original.
- Details, icon/list/tile, Columns and Gallery share virtual item models, selection, sorting, filtering, toolbar contexts and properties routing. Columns refresh after edits and transfers; virtual previews materialize on demand. Server listings refresh every 15 seconds while idle.
- Security pages show archive modes/encryption or server permissions, owner/group, links and connection trust when the backend exposes them. Archive mode edits support whole-archive undo; remote mode changes require server support. macOS extended attributes and ACLs are available on local/mounted files; these archive and FTP/SFTP backends do not expose them, so their edit commands are unavailable in virtual panes.

## Translation quality and parity scope

Native catalog coverage is complete across 49 locales. Automated checks validate every catalog key, nonempty values, interpolation tokens, bundled strings and plural dictionaries. Native tests exercise interpolation and plural selection across all locales. Original Files translations are preferred; missing native text is machine translated locally with Meta M2M100-418M. Catalogs preserve per-entry provenance and a pinned model revision. The app ships only the text resources, with no translation model or service dependency. See `Localization/README.md` for regeneration and review.

Machine-generated translations have **not** received fluent-speaker review in all languages. German and Arabic terminology has targeted corrections; layout and runtime checks do not establish linguistic quality. System dialogs, command output and user metadata keep their system/provider language.

This matrix documents implemented workflows, not a completed audit of every upstream control or pixel. Native properties, Columns/Gallery and platform integrations use macOS equivalents. Windows-only behavior and private cloud-provider APIs cannot be reproduced through the portable backends below.

## Platform boundaries

- WSL, Windows registry/COM shell extensions, Windows executable compatibility/elevation, Windows driver installation and NTFS alternate streams are Windows APIs. Native executable information, code-signature inspection, POSIX/ACL permissions, extended attributes, sharing and macOS provider folders implement corresponding Mac workflows with different semantics.
- Third-party File Provider availability is visible, but private provider sync/account APIs are not exposed universally. Account login and sync preferences open the provider’s app; availability never claims that upload is complete. Live cloud download/eviction must still be exercised with the intended account. Development did not change cloud accounts or sync preferences.
- Finder's desktop and other applications’ Open/Save panels remain macOS components. MacFiles can be registered for folder URLs; it does not replace those system surfaces.
- Trash restoration uses original locations recorded by MacFiles. For items deleted elsewhere, choose a destination; no undocumented Finder restoration database is modified.

## Operational limits

- Local replacements, archive edits and media edits retain the original in Trash and use identity checks for undo. Undo depends on those originals remaining available. The shared history retains up to 30 batches, including remote and compound operations. Remote journal entries persist endpoint identity and recovery paths, not credentials; reconnect after restart to replay them.
- Remote replacement stages uploads under a private name and retains prior items in `.MacFiles-Recovery`. Server-side concurrent changes can still race preflight; FTP/SFTP cannot provide a transaction across an arbitrary batch. A cancelled transfer may leave a hidden partial upload on the server. No existing user data is purged automatically.
- Archive editing rebuilds ZIP, 7z and TAR-family containers and preserves the archive file's filesystem attributes. Split archives and RAR/CAB/ISO/XAR are read-only in the editor. All split volumes must remain together. Less common format variants require broader fixtures. Unsupported/ambiguous paths are rejected, and symbolic links cannot escape extraction roots.
- JPEG/PNG/TIFF/HEIC image editing may re-encode pixels. Multi-frame images are rejected. M4A/MP4 metadata rewrites retain media bytes; MOV uses passthrough export. Saved fields are verified before replacement. Fragmented, compressed-header, open-ended or unsupported metadata containers retain the original and report why editing failed.
- PDF search needs an accessible text layer; scanned PDFs are not OCRed. Office/OpenDocument XML and UTF-16 decoding are bounded at 64 MiB. Binary formats may use available Spotlight text. Online-only files are skipped to avoid implicit cloud downloads. Hidden files and package descendants are excluded by default.
- SSH host-key checks and FTPS certificate checks remain enabled. Host fingerprints require explicit review before saving trust; passwords are not passed in command-line arguments or saved in tab snapshots. Keychain storage is opt-in.

## Build and run

Requires macOS 14 or later and Xcode/Swift 6 or later. The native Swift targets retain Shared/Storage/App layer boundaries. Git and SSH use system tools, ordinary archive formats use system libarchive, and encrypted/split 7z workflows use the bundled official 7-Zip 26.05 universal binary. Complete corresponding 7-Zip source and license notices are included; no package-manager download is required for the app build.

```sh
cd "/Users/toidi/Documents/Unreal Projects/MacFiles/src/Files.Mac"
python3 build.py --universal
swift test
open dist/MacFiles.app
```

`build.py --configuration debug --output /some/folder` builds an isolated preview. `--universal` includes Apple Silicon and Intel; without it the current CPU is targeted. The helper is compiled by build.py before packaging/testing. Builds are ad-hoc signed for local use. Developer ID signing/notarization and execution across older supported macOS releases still need validation.

The optional SFTP password integration fixture uses Paramiko in a test-only Python environment. It is not a runtime dependency:

```sh
python3 -m venv work/ssh-test-env
work/ssh-test-env/bin/pip install paramiko
MACFILES_SFTP_TEST_PYTHON="$PWD/work/ssh-test-env/bin/python" swift test
```

Without that variable the password integration fixture explicitly skips. FTP/FTPS fixtures use Python's standard library, disposable certificates and loopback sockets. No external server/account is required.

## Verification

The current suite has 100 automated tests, all passing with no skips in the full configured run. The complete run includes archive encryption/split volumes/path and link safety, permissions, archive/media edits and undo, audio metadata and unchanged media bytes, local replacement/cancellation, queue isolation, virtual command routing/session persistence, shortcuts, layout grouping, search, hashes, properties, Git fixtures, FTP replacement recovery, FTPS certificate rejection and SFTP password/known-host behavior. Added coverage includes cut/source identity and payload verification, destination archive verification, compound undo failure recovery, file-promise lifetime/collisions/Unicode folders, all virtual layout models, archive permissions, remote endpoint persistence and localization/plurals. Tests run on Apple Silicon; binary architecture checks do not constitute Intel hardware testing.

Native UI checks cover grouped icons/tiles, shortcut recording/application/reset, restoration of archive/network tabs, archive folder creation/history/undo, cloud-provider page rendering, toolbar customization and the properties pages checked in the prior build. This build additionally exercises archive nested Columns and Gallery, virtual hashes/properties, archive cut to a local pane with undo, historical native promised-file drag-out, remote FTP Gallery/properties, German and Arabic settings, Arabic right-to-left sheets, native group headings/date formatting, and restoration to the system language. Every control and every external provider has not been exercised. No user Git repository was pushed, no external transfer server was contacted, and no user SSH host trust was changed.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New window / tab | Command-N / Command-T |
| Close / reopen tab | Command-W / Command-Shift-T |
| Next / previous tab | Control-Tab / Control-Shift-Tab |
| Address / search / advanced search | Command-L / Command-F / Command-Option-F |
| Command palette | Command-Shift-P |
| Back / forward / up | Command-[ / Command-] / Command-Up |
| Refresh | Command-R or F5 |
| Open / Quick Look | Return / Space |
| Copy / cut / paste / select all | Command-C / X / V / A; Control equivalents outside text fields |
| Move clipboard items here | Command-Option-V |
| Rename / Trash | F2 / Command-Backspace |
| New folder | Command-Shift-N |
| Undo / redo | Command-Z / Command-Shift-Z |
| Icons / details / columns / gallery | Command-1 / 2 / 3 / 4 |
| Split panes / details pane | Command-Shift-D / Command-I |
| Hidden files | Command-Shift-Period |
| Git / server | Command-Shift-G / Command-K |

## Attribution

Based on Files Community source in this repository, including its shell, MVVM, commands, dialogs, libraries, shelf, layout and resource structure. The app icon comes from Files.App's Dev assets. Original MIT and MPL-2.0 notices are bundled. The official 7-Zip binary, complete corresponding source, provenance hashes, LGPL-2.1 and 7-Zip/RAR notices are bundled under Tools and Notices. Native translations additionally use the MIT-licensed Meta M2M100-418M during development, with provenance under Localization. libarchive 3.7.4 public headers and their notice are in Sources/CArchive and Notices/LICENSE-libarchive; the implementation linked at runtime is supplied by macOS. This independent macOS port is not an official Files Community release.

## macOS API references

Cloud state uses Apple’s [URLResourceValues ubiquitous download status](https://developer.apple.com/documentation/foundation/urlresourcevalues/ubiquitousitemdownloadingstatus) and associated upload/error keys. File Provider managers are provider-scoped; this app does not impersonate other providers. Local availability is kept separate from sync completion.

Audio/video metadata uses Apple’s [AVFoundation metadata API](https://developer.apple.com/documentation/avfoundation/avassetexportsession/metadata) and documented [media atom structure](https://developer.apple.com/documentation/quicktime-file-format/metadata_atoms_and_types). The archive backend comes from the [official 7-Zip download](https://www.7-zip.org/download.html).

## Build 6 audit fixes

Preserved virtual locations and presentation when splitting panes; added persisted sidebar/toolbar visibility and filename-extension display; enabled virtual Share/Open With through materialized copies; added Create folder with selection with compound undo. See PARITY-AUDIT.md for source inventory and outstanding comparisons. This does not certify full upstream parity.

## Build 10 UI update

Unified archive/remote navigation with the main explorer address bar and toolbar, moved tools into centered Files-style dialogs, rebuilt local/virtual Properties category navigation, and restyled compression/bulk rename/name prompts. Fixed the reported Rename button behavior and a remote history bug found during loopback UI testing. 108 tests pass; native UI checks include an actual rename/Undo, archive creation, nested ZIP browsing and FTP navigation. System-owned pickers/security flows remain macOS interfaces; exact Windows pixel parity is not certified.

## Build 11 inline rename

Single-item Rename and F2 now edit the filename at its displayed position instead of opening a dialog. The same editor serves Details, icons/list/tiles, Columns and Gallery, including archive and remote file names. Enter validates and commits; Escape or focus loss cancels. The initial selection excludes the final file extension, while directories select the entire name. Bulk rename retains its preview dialog. Offscreen selected items in Details/Icons are scrolled into view before editing.

Interactive checks verified Details commit, Escape cancellation, icon-view commit and F2 activation, with the basename selected and no dialog. Existing storage/virtual undo and extension-warning paths are retained. The full suite passes 110 tests, including editor commit/cancel/invalid-name validation and Unicode/extension selection.

## Build 12 navigation, dialog checks, and distribution

Added per-breadcrumb folder menus for local, archive and connected remote locations. Archive menus include implicit parent directories. Up from an archive root returns to its containing local folder and selects the archive. Network connection fields use grouped, scrollable cards; Port remains labeled when populated. Dialog buttons show disabled state. Connection dialogs use a 600-point preferred width.

Rendered the actual SwiftUI dialog views for Properties, connection, compression, bulk rename and toolbar customization; Properties and connection were also checked at the 860 × 560 minimum window size. These are app-hosted render checks, not automated external mouse/keyboard tests. Home launch was checked in the packaged debug app. The earlier desktop-control tool was unavailable; macOS denied the fallback harness assistive/event-posting access. Full live click-through and exact Windows pixel parity remain unverified.

Distribution now keeps one runnable MacFiles.app at the repository root. Generated development/test app bundles and redundant development archives are removed after validating the root app. Build defaults target that same root path to avoid accumulating Spotlight results. Source, reports and one portable ZIP remain available.

## Build 13 secondary dialogs and virtual history

Compared DecompressArchiveDialog.xaml and MainPropertiesPage.xaml with the native views. Added the centered extraction dialog with destination/Browse, password, default Extract action, Cancel, and open-destination-on-completion. Local archive commands and archive entry extraction share it; local here/smart/child-folder placement and multi-archive reporting retain their existing backend. The destination chooser remains a macOS picker. Upstream encoding selection and extraction-location suggestions are not implemented in this dialog.

Added page-back history to the shared local/virtual Properties navigation and full-label help for truncated page names. Primary actions in extraction, compression, bulk rename, network connection, and toolbar customization now use the configured accent color.

Archive Back/Forward works without a mounted browser callback and clears stale search/selection/column state. Up within an archive uses the same validated navigation path. Disconnected remote paths report failure instead of pretending to navigate; address/search editing state resets on virtual navigation. Two new regression tests cover archive history/state and disconnected remote navigation.

114 tests pass, with the loopback SFTP fixture and no skips. Actual SwiftUI dialog renders cover normal/minimum sizes, including the new extraction dialog. This is render/source/model verification; external mouse/keyboard click-through and running-Windows pixel comparison are still unavailable. Full 1:1 UI parity is not certified. Only the existing root MacFiles.app is replaced; no additional app bundles are produced.

## Build 14 archive dialog controls

Compared CreateArchiveDialog.xaml with CompressView. Added compression levels (None/Fast/Low/Normal/High/Ultra), 7z dictionary and word size, and bounded CPU-thread controls. ZIP/7z options are passed to the bundled 7-Zip backend and validated before execution. Dictionary/word controls disable for ZIP and stored mode. Archive creation disables for invalid names. Increased preferred dialog height while retaining scrolling and a fixed action footer at minimum window size.

Extraction now offers the ten most recent successful destinations. All newly used dialog label keys exist in all 49 locale resources. Existing machine-translation quality limitations remain.

116 tests pass without skips. Added ZIP/7z byte-for-byte round trips with explicit advanced settings, compression-versus-stored size comparison, invalid-option rejection, and existing-archive preservation. Rendered the actual dialog at 1100 × 760 and 860 × 560. No external click-through or Windows pixel-diff certification is claimed. Builds continue to replace the sole repository-root app.
