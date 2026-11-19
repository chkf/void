import CryptoKit
import Foundation

enum CompiledProject {
    static let entry = "SwiftUI/ProjectContentView.swift"

    static func validate(_ snapshot: SourceSnapshot) throws {
        guard snapshot.info.entry == entry else {
            throw RuntimeIssue("app/manifest.json · 此安装包的 SwiftUI 入口为 " + entry)
        }
        guard let template = Bundle.main.url(forResource: ProjectTemplate.swiftUI.rawValue, withExtension: nil) else {
            throw RuntimeIssue("安装包缺少 SwiftUI 项目资源")
        }
        func sources(_ files: [String: Data]) throws -> [String: Data] {
            try files.filter { $0.key.hasPrefix("app/SwiftUI/") && $0.key.hasSuffix(".swift") }.mapValues { data in
                guard data.contains(13) else { return data }
                guard let text = String(data: data, encoding: .utf8) else { throw RuntimeIssue("SwiftUI 源文件需要使用 UTF-8 编码") }
                return Data(text.replacingOccurrences(of: "\r\n", with: "\n").utf8)
            }
        }
        let bundled = try sources(ProjectFiles.snapshot(at: template).files)
        let project = try sources(snapshot.files)
        if bundled["app/" + entry] != nil && project == bundled { return }
        // The shipped greeting form gained only its settings link. Match both complete
        // source sets so custom Swift builds still require their own exact sources.
        func soleEntryDigest(_ files: [String: Data]) -> String? {
            guard files.count == 1, let source = files["app/" + entry] else { return nil }
            return SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined()
        }
        guard soleEntryDigest(project) == "32e5f5a0cfb737a2c93e924f79fcbf30ec93948510272c2d75c83f8252b4c380",
              soleEntryDigest(bundled) == "b1fdde4a6adc9dfc2347ec42f34328de490e48e71706443ba4c85dc5b3e27a1f" else {
            throw RuntimeIssue("SwiftUI 源码与已安装版本不同。请将 app/SwiftUI/ 同步到仓库的 ios/StarterProject/app/SwiftUI/，通过 GitHub Actions 构建并安装对应的 IPA。")
        }
    }
}
