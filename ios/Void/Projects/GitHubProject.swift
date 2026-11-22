import Foundation

struct GitHubRepository: Equatable {
    let address: String
    let name: String

    init(_ input: String) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = RuntimeIssue("请输入公开 GitHub 仓库的 HTTPS 地址，例如 https://github.com/owner/repo")
        guard let url = URLComponents(string: text), url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com", url.port == nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { throw invalid }
        var path = url.percentEncodedPath
        if path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix(".git") { path.removeLast(4) }
        let parts = path.components(separatedBy: "/")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard parts.count == 3, parts[0].isEmpty,
              parts.dropFirst().allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") && $0.unicodeScalars.allSatisfy(allowed.contains) })
        else { throw invalid }
        name = parts[2]
        address = "https://github.com/" + parts[1] + "/" + name + ".git"
    }
}

struct GitHubCheckout: Codable {
    let address: String
    var commit: String
}

enum ProjectGit {
    private static func run(_ operation: (inout [CChar], inout [CChar]) -> Int32) throws -> String {
        var commit = [CChar](repeating: 0, count: Int(VoidGitIDSize))
        var message = [CChar](repeating: 0, count: 1024)
        guard operation(&commit, &message) == 0 else { throw RuntimeIssue(String(cString: message)) }
        return String(cString: commit)
    }

    static func clone(_ address: String, to destination: URL) throws -> String {
        try run { commit, message in
            let size = message.count
            return VoidGitClone(address, destination.path, &commit, &message, size)
        }
    }

    static func fetch(_ current: String, database: URL) throws -> String {
        try run { commit, message in
            let size = message.count
            return VoidGitFetch(database.path, current, &commit, &message, size)
        }
    }

    static func checkout(_ target: String, from current: String, database: URL, at worktree: URL) throws {
        _ = try run { _, message in
            let size = message.count
            return VoidGitCheckout(database.path, worktree.path, current, target, &message, size)
        }
    }
}
