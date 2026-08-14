import AppKit
import SwiftUI

struct BrandMark: View {
    var id: String
    var onAccent = false
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let image = Self.image(named: id) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }

    private static func image(named id: String) -> NSImage? {
        let bundle = Bundle.main
        if let url = bundle.url(forResource: "brand-\(id)@2x", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let url = bundle.url(forResource: "brand-\(id)", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return nil
    }
}
