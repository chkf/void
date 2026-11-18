import SwiftUI

@main
struct VoidApp: App {
    @StateObject private var model = HostModel()
    var body: some Scene { WindowGroup { HostView(model: model) } }
}
