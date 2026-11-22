import SwiftUI
import UniformTypeIdentifiers

struct FolderPickerPresenter: View {
    @ObservedObject var flow: FolderRequests

    var body: some View {
        if let request = flow.request {
            Color.clear
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .fileImporter(isPresented: Binding(
                    get: { flow.request?.id == request.id && flow.ready },
                    set: { if !$0 { flow.dismissed(request.id) } }
                ), allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                    switch result {
                    case .success(let urls): flow.picked(request.id, urls)
                    case .failure(let error): flow.pickerFailed(request.id, error)
                    }
                } onCancellation: {
                    flow.pickerCancelled(request.id)
                }
                #if DEBUG && targetEnvironment(simulator)
                .fileDialogDefaultDirectory(SimulatorPickerFixture.directory)
                #endif
                .onChange(of: flow.ready, initial: true) { _, ready in
                    if ready { flow.didPresent(request.id) }
                }
                .id(request.id)
        }
    }
}
