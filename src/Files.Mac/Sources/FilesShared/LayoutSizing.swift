import Foundation

public enum LayoutSizing {
    public static let families: [LayoutMode] = [.details, .list, .tiles, .icons, .columns]
    public static let grids: [LayoutMode] = [.smallIcons, .mediumIcons, .largeIcons, .extraLargeIcons]
    public static func family(_ mode: LayoutMode) -> LayoutMode { grids.contains(mode) ? .icons : mode }
    public static func count(_ mode: LayoutMode) -> Int { [.tiles, .icons].contains(family(mode)) ? 4 : 5 }
    public static func level(_ mode: LayoutMode, sizes: [String: Int]) -> Int {
        if let index = grids.firstIndex(of: mode) { return index }
        return min(count(mode) - 1, max(0, sizes[family(mode).rawValue] ?? 1))
    }
    public static func step(_ mode: LayoutMode, sizes: inout [String: Int], forward: Bool, cycle: Bool = false) -> LayoutMode {
        let group = family(mode)
        guard let index = families.firstIndex(of: group) else { return mode }
        let next = level(mode, sizes: sizes) + (forward ? 1 : -1)
        let target: LayoutMode
        let value: Int
        if !cycle && (0..<count(group)).contains(next) { target = group; value = next }
        else { target = families[(index + (forward ? 1 : families.count - 1)) % families.count]; value = forward ? 0 : count(target) - 1 }
        sizes[target.rawValue] = value
        return target == .icons ? grids[value] : target
    }
    public static func rowHeight(_ level: Int) -> Double { [26, 34, 42, 50, 60][min(4, max(0, level))] }
}
