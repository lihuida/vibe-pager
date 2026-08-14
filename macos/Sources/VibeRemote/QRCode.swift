import AppKit
import CoreImage
import Foundation

enum QRCode {
    static func image(from string: String, size: CGFloat = 168) -> NSImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = size / max(output.extent.width, 1)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }

    static func image(data: Data, size: CGFloat = 168) -> NSImage? {
        guard let raw = NSImage(data: data) else { return nil }
        raw.size = NSSize(width: size, height: size)
        return raw
    }
}
