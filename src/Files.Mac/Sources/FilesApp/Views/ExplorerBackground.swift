import SwiftUI
import FilesShared

struct ExplorerBackground: View {
    let image: NSImage
    let preferences: ExplorerPreferences
    private var alignment: Alignment {
        Alignment(horizontal: preferences.backgroundHorizontal == "Left" ? .leading : preferences.backgroundHorizontal == "Right" ? .trailing : .center,
                  vertical: preferences.backgroundVertical == "Top" ? .top : preferences.backgroundVertical == "Bottom" ? .bottom : .center)
    }
    var body: some View {
        GeometryReader { geometry in
            Group {
                switch preferences.backgroundFit {
                case "None": Image(nsImage: image)
                case "Stretch": Image(nsImage: image).resizable().frame(width: geometry.size.width, height: geometry.size.height)
                case "Fit": Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                default: Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: alignment).clipped()
        }.allowsHitTesting(false)
    }
}
