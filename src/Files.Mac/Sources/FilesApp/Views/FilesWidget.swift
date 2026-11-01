import SwiftUI

struct FilesWidget<Content: View>: View {
    let title: String
    let actionTitle: String?
    let action: (() -> Void)?
    let content: Content
    @AppStorage private var expanded: Bool
    init(title: String, actionTitle: String? = nil, action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.actionTitle = actionTitle; self.action = action; self.content = content()
        _expanded = AppStorage(wrappedValue: true, "homeWidgetExpanded." + title)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button { expanded.toggle() } label: {
                    HStack { Text(L10n.text(title)).font(ExplorerFont.font(size: 12, weight: .semibold)).foregroundStyle(.secondary); Spacer(); Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 10)).foregroundStyle(.secondary) }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityValue(L10n.text(expanded ? "Expanded" : "Collapsed"))
                if let actionTitle, let action { Button(L10n.text(actionTitle), action: action).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary) }
            }.frame(minHeight: 24)
            if expanded { content }
        }
    }
}
