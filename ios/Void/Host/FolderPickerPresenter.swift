import SwiftUI
import UniformTypeIdentifiers

struct FolderPickerPresenter: UIViewControllerRepresentable {
    @ObservedObject var flow: FolderRequests
    func makeUIViewController(context: Context) -> Anchor { Anchor() }
    func updateUIViewController(_ anchor: Anchor, context: Context) {
        anchor.flow = flow
        anchor.update()
    }

    @MainActor
    final class Anchor: UIViewController, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
        weak var flow: FolderRequests?
        private var picker: UIDocumentPickerViewController?
        private var active: FolderRequest?
        private var closing = false
        private var didPresent = false
        private var scheduled = false
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); update() }

        func update() {
            guard !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in self?.scheduled = false; self?.reconcile() }
        }
        private func reconcile() {
            guard let flow else { return }
            if let picker, let active {
                if flow.request?.id != active.id || flow.phase != .presenting { dismissPicker(picker) }
                return
            }
            guard flow.ready, flow.phase == .presenting, let request = flow.request, viewIfLoaded?.window != nil else { return }
            var host: UIViewController = self
            while let parent = host.parent { host = parent }
            if host.presentedViewController != nil || host.isBeingDismissed {
                DispatchQueue.main.asyncAfter(deadline:.now()+0.15) { [weak self] in self?.update() }
                return
            }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes:[.folder],asCopy:false)
            picker.allowsMultipleSelection = false
            #if DEBUG && targetEnvironment(simulator)
            // Files still owns selection and grants access only when the tester presses Open.
            if let start = SimulatorPickerFixture.directory { picker.directoryURL = start }
            #endif
            picker.sheetPresentationController?.prefersGrabberVisible = true
            picker.delegate = self
            self.picker = picker; active = request; closing = false; didPresent = false
            request.trace.event("picker.willPresent")
            host.present(picker,animated:true) { [weak self,weak picker] in
                guard let self,let picker,self.picker === picker else { return }
                self.didPresent = true
                self.flow?.didPresent(request.id)
                self.observeDismissal(picker)
                self.update()
            }
            picker.presentationController?.delegate = self
            DispatchQueue.main.asyncAfter(deadline:.now()+5) { [weak self,weak picker] in
                guard let self, let picker, self.picker === picker, !self.didPresent,
                      picker.presentingViewController == nil, picker.viewIfLoaded?.window == nil else { return }
                self.flow?.presentationFailed(request.id)
                self.completed(picker)
            }
        }
        private func observeDismissal(_ picker: UIDocumentPickerViewController) {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.35) { [weak self,weak picker] in
                guard let self,let picker,self.picker === picker else { return }
                if picker.presentingViewController == nil { self.completed(picker) }
                else { self.observeDismissal(picker) }
            }
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard controller === picker, let active else { return }
            flow?.picked(active.id,urls)
            dismissPicker(controller)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            guard controller === picker, let active else { return }
            flow?.cancel(active.id)
            dismissPicker(controller)
        }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            if let picker, presentationController.presentedViewController === picker { completed(picker) }
        }
        private func dismissPicker(_ picker: UIDocumentPickerViewController) {
            guard !closing else { return }
            if picker.isBeingPresented && !didPresent { return }
            closing = true
            if picker.isBeingDismissed, let transition = picker.transitionCoordinator {
                transition.animate(alongsideTransition:nil) { [weak self] _ in self?.completed(picker) }
            } else if picker.presentingViewController != nil {
                picker.dismiss(animated:true) { [weak self] in self?.completed(picker) }
            } else { completed(picker) }
        }
        private func completed(_ controller: UIDocumentPickerViewController) {
            guard controller === picker, let request = active else { return }
            controller.delegate = nil; controller.presentationController?.delegate = nil
            picker = nil; active = nil; closing = false
            if flow?.request?.id == request.id { flow?.dismissed(request.id) }
            else { request.trace.event("picker.dismiss") }
            update()
        }
    }
}

struct DirectoryDiagnosticView: View {
    @State private var rows = DirectoryJournal.shared.recent()
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:8) {
                ForEach(rows.reversed()) { row in
                    Text(verbatim:row.line).font(.caption.monospaced()).frame(maxWidth:.infinity,alignment:.leading)
                }
            }.padding().textSelection(.enabled)
        }.navigationTitle("目录诊断")
            .toolbar {
                if let id = rows.last(where:{ ["picker.request","local.request","preview.begin","workspace.begin"].contains($0.stage) })?.request ?? rows.last?.request {
                    let lines = rows.filter { $0.request == id }.map(\.line).joined(separator:"\n")
                    ShareLink(item:lines) { Label("分享这次目录诊断",systemImage:"square.and.arrow.up") }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for:DirectoryJournal.changed)) { _ in rows = DirectoryJournal.shared.recent() }
    }
}
