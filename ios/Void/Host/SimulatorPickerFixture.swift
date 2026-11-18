#if DEBUG && targetEnvironment(simulator)
import Foundation

// Arrange a new, unregistered directory inside the running test app's actual data container.
// UI tests still navigate Apple's Files browser and use its real Open and cancel actions.
enum SimulatorPickerFixture {
    static func prepareIfRequested() async throws {
        guard let token = ProcessInfo.processInfo.environment["VOID_PICKER_TEST_PROJECT"],
              let id = UUID(uuidString:token) else { return }
        let name = "Void Picker " + String(id.uuidString.prefix(8))
        try await DirectoryIO.run { io in
            let root = FolderGrant.documents
            let target = root.appendingPathComponent(name,isDirectory:true)
            let coordinator = NSFileCoordinator()
            try io.withCoordinator(coordinator) {
                var failure: NSError?
                var result: Result<Void,Error>?
                coordinator.coordinate(writingItemAt:target,options:[],error:&failure) { location in
                    result = Result {
                        try io.check()
                        if !FileManager.default.fileExists(atPath:location.path) {
                            _ = try ProjectFiles.create(name,in:location.deletingLastPathComponent(),template:.tsx,io:io)
                        }
                        let snapshot = try ProjectFiles.snapshot(at:location,io:io)
                        guard snapshot.info.name == name, snapshot.info.mode == .native else { throw RuntimeIssue("模拟器测试项目无效") }
                        DirectoryTrace("ui-test").event("fixture.ready")
                    }
                }
                if let failure { throw failure }
                guard let result else { throw RuntimeIssue("模拟器未能准备界面测试目录") }
                try result.get()
            }
        }
    }
}
#endif
