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
struct ProjectPermissionView: View {
    @ObservedObject var model: HostModel
    @ObservedObject private var consent = SDKConsent.shared
    var body: some View {
        List {
            if model.permissions.isEmpty { Text("此项目没有声明权限") }
            if let record = model.current {
                ForEach(model.permissions, id:\.self) { key in
                    let label = SDKConsent.labels[key] ?? key
                    let decision = consent.decision(key,project:record.id)
                    Menu {
                        Button("允许") { set(true,key:key,project:record.id) }
                        Button("拒绝",role:.destructive) { set(false,key:key,project:record.id) }
                        Button("下次询问") { set(nil,key:key,project:record.id) }
                    } label: { LabeledContent(label, value:decision.map { $0 ? "已允许" : "已拒绝" } ?? "使用时询问") }
                }
                let recent = Array(consent.history(record.id).reversed())
                if !recent.isEmpty {
                    Section("最近使用") {
                        ForEach(Array(recent.enumerated()),id:\.offset) { _, item in
                            VStack(alignment:.leading) {
                                Text(verbatim:item["method"] ?? "")
                                Text(verbatim:[item["time"],item["result"]].compactMap{$0}.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }.navigationTitle("项目权限")
    }
    private func set(_ value: Bool?, key: String, project: UUID) {
        consent.set(value,for:key,project:project)
        if value != true, model.page != nil || model.candidate != nil {
            model.page?.sdk.close()
            model.candidate?.sdk.close()
            model.refresh(force:true)
        }
    }
}
