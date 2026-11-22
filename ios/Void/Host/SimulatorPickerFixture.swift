#if DEBUG && targetEnvironment(simulator)
import Foundation

// Create a project in the simulator's Files container before the project list appears.
enum SimulatorPickerFixture {
    static var directory: URL? {
        guard let token = ProcessInfo.processInfo.environment["VOID_PICKER_TEST_PROJECT"],
              let id = UUID(uuidString:token) else { return nil }
        return FolderGrant.documents.appendingPathComponent("Void Picker " + String(id.uuidString.prefix(8)),isDirectory:true)
    }
    static func prepareIfRequested() async throws {
        guard let target = directory else { return }
        let name = target.lastPathComponent
        try await DirectoryIO.run { io in
            // This is a new fixture in this test app's own sandbox, created before
            // the Files picker opens. ProjectFiles publishes it with an atomic rename.
            try io.check()
            if !FileManager.default.fileExists(atPath:target.path) {
                _ = try ProjectFiles.create(name,in:target.deletingLastPathComponent(),io:io)
                if ProcessInfo.processInfo.environment["VOID_TEST_SLOW_FIRST_FRAME"] == "1" {
                    let source = """
                    import {render, Text} from "@runtime/ui";
                    setTimeout(() => render(<Text value="预览已恢复"/>), 25000);
                    """
                    try Data(source.utf8).write(to:target.appendingPathComponent("app/src/main.tsx"),options:.atomic)
                }
            }
            let snapshot = try ProjectFiles.snapshot(at:target,io:io)
            guard snapshot.info.name == name, snapshot.info.mode == .native else { throw RuntimeIssue("模拟器测试项目无效") }
            DirectoryTrace("ui-test").event("fixture.ready")
        }
    }
}
#endif
