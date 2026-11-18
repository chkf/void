import AVFoundation
import UIKit

final class PictureCapture: NSObject, AVCapturePhotoCaptureDelegate {
    let result: SDKWait<Data>
    init(_ result: SDKWait<Data>) { self.result = result }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            if let error { result.finish(.failure(error)) }
            else if let data { result.finish(.success(data)) }
            else { result.finish(.failure(SDKFailure("CAPTURE_FAILED","照片为空"))) }
        }
    }
}
final class MovieCapture: NSObject, AVCaptureFileOutputRecordingDelegate {
    let result: SDKWait<URL>
    init(_ result: SDKWait<URL>) { self.result = result }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            if let e = error as NSError?, e.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true { result.finish(.failure(e)) }
            else { result.finish(.success(outputFileURL)) }
        }
    }
}
@MainActor
final class CameraSDK: SDKModule {
    private let queue = DispatchQueue(label:"void.camera")
    private var capture: AVCaptureSession?
    private var input: AVCaptureDeviceInput?
    private var photos: AVCapturePhotoOutput?
    private var movie: AVCaptureMovieFileOutput?
    private var picture: PictureCapture?
    private var recording: MovieCapture?
    private var recordingPath: String?
    private var flash: AVCaptureDevice.FlashMode = .off
    private var opening = false
    private weak var host: SDKSession?
    private func device(_ face: String) throws -> AVCaptureDevice {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:face == "front" ? .front : .back) else { throw SDKFailure.unavailable("此设备没有所选摄像头") }
        return device
    }
    static func authorize(_ type: AVMediaType) async throws {
        var state = AVCaptureDevice.authorizationStatus(for:type)
        if state == .notDetermined { _ = await AVCaptureDevice.requestAccess(for:type); state = AVCaptureDevice.authorizationStatus(for:type) }
        guard state == .authorized else { throw SDKFailure.denied(type == .video ? "相机未获授权" : "麦克风未获授权") }
    }
    static func status(_ type: AVMediaType) -> String {
        switch AVCaptureDevice.authorizationStatus(for:type) { case .authorized:return "authorized"; case .denied:return "denied"; case .restricted:return "restricted"; default:return "notDetermined" }
    }
    func call(_ method: String, _ a: SDKArgs, in s: SDKSession) async throws -> Any {
        if method == "authorization" { return Self.status(.video) }
        if method == "available" { return ["front":(try? device("front")) != nil,"back":(try? device("back")) != nil] }
        if method == "close" { close(); return NSNull() }
        if method == "open" {
            guard !opening, capture == nil else { throw SDKFailure("BUSY","相机已打开") }
            opening = true; defer { opening = false }
            let position = try a.choice("position",["front","back"],"back")
            let selected = try device(position)
            try await Self.authorize(.video)
            let mic = try a.bool("microphone")
            if mic { try await s.require("audio.record"); try await Self.authorize(.audio) }
            try Task.checkCancellation()
            let capture = AVCaptureSession(), camera = try AVCaptureDeviceInput(device:selected)
            let photos = AVCapturePhotoOutput(), movie = AVCaptureMovieFileOutput()
            capture.beginConfiguration()
            capture.sessionPreset = .high
            guard capture.canAddInput(camera) else { capture.commitConfiguration(); throw SDKFailure.unavailable("无法使用所选摄像头") }
            capture.addInput(camera)
            if mic {
                guard let m = AVCaptureDevice.default(for:.audio) else { capture.commitConfiguration(); throw SDKFailure.unavailable("麦克风不可用") }
                let sound = try AVCaptureDeviceInput(device:m)
                guard capture.canAddInput(sound) else { capture.commitConfiguration(); throw SDKFailure.unavailable("无法接入麦克风") }
                capture.addInput(sound)
            }
            guard capture.canAddOutput(photos) else { capture.commitConfiguration(); throw SDKFailure.unavailable("拍照不可用") }
            capture.addOutput(photos)
            if capture.canAddOutput(movie) { capture.addOutput(movie); self.movie = movie }
            capture.commitConfiguration()
            self.capture = capture; input = camera; self.photos = photos; host = s
            await withCheckedContinuation { continuation in queue.async { capture.startRunning(); continuation.resume() } }
            try Task.checkCancellation()
            guard capture.isRunning else { close(); throw SDKFailure.unavailable("摄像头未能启动") }
            let layer = AVCaptureVideoPreviewLayer(session:capture); layer.videoGravity = .resizeAspect
            s.preview = layer
            return ["position":position,"flash":selected.hasFlash,"video":self.movie != nil]
        }
        guard let capture, let input, let photos else { throw SDKFailure("NOT_OPEN","请先打开相机") }
        let device = input.device
        switch method {
        case "switchCamera":
            guard recording == nil, picture == nil else { throw SDKFailure("BUSY","请先完成拍摄") }
            let pos = try a.choice("position",["front","back"], device.position == .front ? "back" : "front")
            let next = try AVCaptureDeviceInput(device:self.device(pos))
            capture.beginConfiguration(); defer { capture.commitConfiguration() }
            capture.removeInput(input)
            guard capture.canAddInput(next) else { if capture.canAddInput(input) { capture.addInput(input) }; throw SDKFailure.unavailable("无法切换摄像头") }
            capture.addInput(next); self.input = next
            flash = .off
            return pos
        case "configure":
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if a.values["flash"] != nil {
                let val = try a.choice("flash",["off","on","auto"])
                let mode: AVCaptureDevice.FlashMode = val == "on" ? .on : (val == "auto" ? .auto : .off)
                guard photos.supportedFlashModes.contains(mode) else { throw SDKFailure.unavailable("所选闪光模式不可用") }
                flash = mode
            }
            if let point = a.values["focus"] as? [String:Any] {
                let x = try SDKArgs(point).number("x"), y = try SDKArgs(point).number("y")
                guard (0...1).contains(x), (0...1).contains(y) else { throw SDKFailure.invalid("focus") }
                guard device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) else { throw SDKFailure.unavailable("此摄像头不支持点按对焦") }
                device.focusPointOfInterest = CGPoint(x:x,y:y); device.focusMode = .autoFocus
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = CGPoint(x:x,y:y); device.exposureMode = .continuousAutoExposure
                }
            }
            if a.values["exposure"] != nil {
                let exposure = Float(try a.number("exposure"))
                guard (device.minExposureTargetBias...device.maxExposureTargetBias).contains(exposure) else { throw SDKFailure.invalid("exposure") }
                device.setExposureTargetBias(exposure, completionHandler:nil)
            }
        case "capturePhoto":
            guard picture == nil else { throw SDKFailure("BUSY","拍照进行中") }
            let path = try a.string("to","data/Camera/" + UUID().uuidString + ".jpg")
            let wait = SDKWait<Data>(), delegate = PictureCapture(wait)
            picture = delegate; defer { picture = nil }
            let settings = AVCapturePhotoSettings(format:[AVVideoCodecKey: AVVideoCodecType.jpeg])
            if photos.supportedFlashModes.contains(flash) { settings.flashMode = flash }
            photos.capturePhoto(with:settings,delegate:delegate)
            let bytes = try await wait.value(), file = try s.files.temp("capture.jpg")
            try bytes.write(to:file); try s.files.store(file,at:path)
            return path
        case "startRecording":
            guard recording == nil, let movie else { throw SDKFailure.unavailable("录像不可用或已在进行") }
            let path = try a.string("to","data/Camera/" + UUID().uuidString + ".mov")
            let file = try s.files.temp("capture.mov"), delegate = MovieCapture(SDKWait<URL>())
            recordingPath = path; recording = delegate
            movie.startRecording(to:file,recordingDelegate:delegate)
            return path
        case "stopRecording":
            guard let movie, let recording, let target = recordingPath else { throw SDKFailure("NOT_OPEN","尚未开始录像") }
            if movie.isRecording { movie.stopRecording() }
            defer { self.recording = nil; recordingPath = nil }
            let url = try await recording.result.value()
            try s.files.store(url,at:target)
            return target
        default: throw SDKFailure("UNKNOWN_METHOD", method)
        }
        return NSNull()
    }
    func close() {
        if movie?.isRecording == true { movie?.stopRecording() }
        if let capture { queue.async { capture.stopRunning() } }
        picture?.result.finish(.failure(CancellationError())); recording?.result.finish(.failure(CancellationError()))
        if host?.preview is AVCaptureVideoPreviewLayer { host?.preview = nil }
        input = nil; capture = nil; movie = nil; photos = nil; picture = nil; recording = nil; recordingPath = nil
    }
}
