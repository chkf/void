import SwiftUI

@main
struct VoidApp: App {
    @UIApplicationDelegateAdaptor(VoidAppDelegate.self) private var appDelegate
    @StateObject private var model = HostModel()
    var body: some Scene { WindowGroup { HostView(model: model) } }
}
