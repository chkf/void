import SwiftUI
import UIKit

private final class PreviewContainer: UIView {
    var preview: CALayer? {
        didSet {
            guard oldValue !== preview else { return }
            oldValue?.removeFromSuperlayer()
            if let preview { layer.addSublayer(preview) }
            setNeedsLayout()
        }
    }
    override func layoutSubviews() { super.layoutSubviews(); preview?.frame = bounds }
}
private struct NativeMediaLayer: UIViewRepresentable {
    let source: CALayer
    func makeUIView(context: Context) -> PreviewContainer { PreviewContainer() }
    func updateUIView(_ container: PreviewContainer, context: Context) { container.preview = source }
}
struct NativeMediaPreview: View {
    @ObservedObject var sdk: SDKSession
    var body: some View {
        if let preview = sdk.preview {
            NativeMediaLayer(source:preview).aspectRatio(16 / 9, contentMode:.fit).background(.black).accessibilityLabel("媒体预览")
        }
    }
}
