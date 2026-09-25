import SwiftUI
import UIKit

nonisolated struct NormalizedPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x.isFinite ? min(max(x, 0), 1) : 0
        self.y = y.isFinite ? min(max(y, 0), 1) : 0
    }
}

struct AreaSelectionCanvas: View {
    let image: UIImage
    let selectedOutline: [NormalizedPoint]
    let activeStroke: [NormalizedPoint]
    let isSelectingArea: Bool
    let isDisabled: Bool
    var onStrokeBegan: (NormalizedPoint) -> Void
    var onStrokeChanged: (NormalizedPoint) -> Void
    var onStrokeEnded: () -> Void

    @State private var isTrackingStroke = false

    var body: some View {
        GeometryReader { geometry in
            let imageRect = aspectFitRect(imageSize: image.size, in: geometry.size)

            let canvas = ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)

                if !selectedOutline.isEmpty {
                    outlinePath(selectedOutline, in: imageRect, closes: true)
                        .stroke(.black.opacity(0.7), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    outlinePath(selectedOutline, in: imageRect, closes: true)
                        .stroke(.yellow, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }

                if !activeStroke.isEmpty {
                    outlinePath(activeStroke, in: imageRect, closes: false)
                        .stroke(.black.opacity(0.7), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    outlinePath(activeStroke, in: imageRect, closes: false)
                        .stroke(.yellow, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .accessibilityLabel(Text("Screenshot"))

            if isSelectingArea {
                canvas.highPriorityGesture(
                    DragGesture(minimumDistance: 10, coordinateSpace: .local)
                        .onChanged { value in
                            guard !isDisabled else { return }
                            if !isTrackingStroke {
                                guard imageRect.contains(value.startLocation),
                                      let start = normalizedPoint(value.startLocation, in: imageRect) else {
                                    return
                                }
                                isTrackingStroke = true
                                onStrokeBegan(start)
                                if let point = normalizedPoint(value.location, clampedTo: imageRect), point != start {
                                    onStrokeChanged(point)
                                }
                                return
                            }
                            if let point = normalizedPoint(value.location, clampedTo: imageRect) {
                                onStrokeChanged(point)
                            }
                        }
                        .onEnded { _ in
                            guard isTrackingStroke else { return }
                            isTrackingStroke = false
                            onStrokeEnded()
                        }
                )
            } else {
                canvas
            }
        }
        .aspectRatio(max(image.size.width, 1) / max(image.size.height, 1), contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func normalizedPoint(_ point: CGPoint, in rect: CGRect) -> NormalizedPoint? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        return NormalizedPoint(
            x: Double((point.x - rect.minX) / rect.width),
            y: Double((point.y - rect.minY) / rect.height)
        )
    }

    private func normalizedPoint(_ point: CGPoint, clampedTo rect: CGRect) -> NormalizedPoint? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        return NormalizedPoint(
            x: Double((point.x - rect.minX) / rect.width),
            y: Double((point.y - rect.minY) / rect.height)
        )
    }

    private func outlinePath(_ points: [NormalizedPoint], in rect: CGRect, closes: Bool) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(
            x: rect.minX + rect.width * CGFloat(first.x),
            y: rect.minY + rect.height * CGFloat(first.y)
        ))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(
                x: rect.minX + rect.width * CGFloat(point.x),
                y: rect.minY + rect.height * CGFloat(point.y)
            ))
        }
        if closes {
            path.closeSubpath()
        }
        return path
    }
}

nonisolated enum AreaImageMasker {
    static func makeMaskedJPEG(from imageData: Data, outline: [NormalizedPoint]) throws -> Data {
        guard outline.count >= 3,
              let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            throw GlanceAIError.invalidResponse(String(localized: "Glance couldn't prepare this area."))
        }

        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let maskedImage = renderer.image { context in
            let neutral = UIColor(red: 242.0 / 255, green: 242.0 / 255, blue: 242.0 / 255, alpha: 1)
            context.cgContext.setFillColor(neutral.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))

            let path = UIBezierPath()
            if let first = outline.first {
                path.move(to: CGPoint(x: size.width * CGFloat(first.x), y: size.height * CGFloat(first.y)))
                for point in outline.dropFirst() {
                    path.addLine(to: CGPoint(x: size.width * CGFloat(point.x), y: size.height * CGFloat(point.y)))
                }
                path.close()
                path.addClip()
            }
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        guard let jpeg = maskedImage.jpegData(compressionQuality: 0.9) else {
            throw GlanceAIError.invalidResponse(String(localized: "Glance couldn't prepare this area."))
        }
        return jpeg
    }
}
