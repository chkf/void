import AVFoundation
import Foundation
import UniformTypeIdentifiers
import UIKit

@MainActor
final class AudioSDK: SDKModule {
    private var recorder: AVAudioRecorder?
    private var target: String?
    private var player: AVAudioPlayer?
    private var observers: [String:NSObjectProtocol] = [:]
    private var active = false

    private func route() -> [String:Any] {
        let route = AVAudioSession.sharedInstance().currentRoute
        func ports(_ values: [AVAudioSessionPortDescription]) -> [[String:String]] { values.map { ["name":$0.portName,"type":$0.portType.rawValue] } }
        return ["inputs":ports(route.inputs),"outputs":ports(route.outputs)]
    }
    private func configure(_ category: AVAudioSession.Category) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(category, mode:.default, options:category == .playAndRecord ? [.defaultToSpeaker] : [])
        try session.setActive(true); active = true
    }
    func call(_ method: String, _ a: SDKArgs, in s: SDKSession) async throws -> Any {
        switch method {
        case "authorization": return CameraSDK.status(.audio)
        case "importFile","exportFile": return try await FileSDK.transfer(method,a,s,types:[.audio])
        case "route": return route()
        case "watchRoute":
            let id = UUID().uuidString, events = s.events
            observers[id] = NotificationCenter.default.addObserver(forName:AVAudioSession.routeChangeNotification,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor in if let self { events.emit(id,"audio.route",self.route()) } }
            }
            return events.add(id) { [weak self] in if let o = self?.observers.removeValue(forKey:id) { NotificationCenter.default.removeObserver(o) } }
        case "session":
            let category = try a.choice("category",["playback","ambient","playAndRecord"],"playback")
            if category == "playAndRecord" { try await s.require("audio.record") }
            try configure(category == "playAndRecord" ? .playAndRecord : (category == "ambient" ? .ambient : .playback))
            return route()
        case "record":
            guard recorder == nil else { throw SDKFailure("BUSY","录音已开始") }
            try await CameraSDK.authorize(.audio)
            try configure(.playAndRecord)
            let file = try s.files.temp("audio.m4a"), path = try a.string("to","data/Audio/" + UUID().uuidString + ".m4a")
            let rate = try a.number("sampleRate",44100), channels = try a.int("channels",1,range:1...2)
            guard [8000,16000,22050,32000,44100,48000].contains(rate) else { throw SDKFailure.invalid("sampleRate") }
            let rec = try AVAudioRecorder(url:file,settings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:rate,AVNumberOfChannelsKey:channels,AVEncoderAudioQualityKey:AVAudioQuality.high.rawValue])
            guard rec.record() else { throw SDKFailure("MEDIA_ERROR","录音未能启动") }
            recorder = rec; target = path
            return path
        case "stopRecording":
            guard let recorder, let target else { throw SDKFailure("NOT_OPEN","当前没有录音") }
            recorder.stop()
            try s.files.store(recorder.url,at:target)
            self.recorder = nil; self.target = nil
            return target
        case "play":
            try configure(recorder == nil ? .playback : .playAndRecord)
            player?.stop()
            let p = try AVAudioPlayer(contentsOf:s.files.input(a.string("path")))
            guard p.play() else { throw SDKFailure("MEDIA_ERROR","音频未能播放") }
            player = p
            return ["duration":p.duration]
        case "info":
            let file = try AVAudioFile(forReading:s.files.input(a.string("path")))
            return ["sampleRate":file.fileFormat.sampleRate,"channels":file.fileFormat.channelCount,"frames":file.length,"duration":Double(file.length)/file.fileFormat.sampleRate] as [String:Any]
        case "pause","resume":
            if try a.string("target","playback") == "recording" {
                try await s.require("audio.record")
                guard let recorder else { throw SDKFailure("NOT_OPEN","当前没有录音") }
                if method == "pause" { recorder.pause() } else if !recorder.record() { throw SDKFailure("MEDIA_ERROR","无法恢复录音") }
            } else {
                guard let player else { throw SDKFailure("NOT_OPEN","当前没有播放音频") }
                if method == "pause" { player.pause() } else if !player.play() { throw SDKFailure("MEDIA_ERROR","无法恢复播放") }
            }
        case "volume":
            guard let player else { throw SDKFailure("NOT_OPEN","当前没有播放音频") }
            if a.values["value"] != nil {
                let value = try a.number("value"); guard (0...1).contains(value) else { throw SDKFailure.invalid("value") }
                player.volume = Float(value)
            }
            return player.volume
        case "stop": player?.stop(); player = nil
        default: throw SDKFailure("UNKNOWN_METHOD",method)
        }
        return NSNull()
    }
    func close() {
        recorder?.stop(); recorder = nil; player?.stop(); player = nil
        for o in observers.values { NotificationCenter.default.removeObserver(o) }; observers.removeAll()
        if active { try? AVAudioSession.sharedInstance().setActive(false, options:.notifyOthersOnDeactivation); active = false }
    }
}

@MainActor
final class VideoSDK: SDKModule {
    private var player: AVPlayer?
    private var observer: Any?
    private var ended: NSObjectProtocol?
    private weak var host: SDKSession?
    private var playbackID: String?

    func call(_ method: String, _ a: SDKArgs, in s: SDKSession) async throws -> Any {
        if ["importFile","exportFile"].contains(method) { return try await FileSDK.transfer(method,a,s,types:[.movie]) }
        switch method {
        case "pause","resume","seek","stop":
            guard let player else { throw SDKFailure("NOT_OPEN","当前没有播放视频") }
            if method == "pause" { player.pause() }
            else if method == "resume" { player.play() }
            else if method == "stop" { if let playbackID { s.events.stop(playbackID) } }
            else {
                let seconds = try a.number("seconds"); guard seconds >= 0 else { throw SDKFailure.invalid("seconds") }
                return await player.seek(to:CMTime(seconds:seconds,preferredTimescale:600))
            }
            return NSNull()
        default: break
        }
        let url = try s.files.input(a.string("path")), asset = AVURLAsset(url:url)
        switch method {
        case "info":
            let seconds = try await asset.load(.duration).seconds
            var value: [String:Any] = ["duration":seconds.isFinite ? seconds : 0]
            if let track = try await asset.loadTracks(withMediaType:.video).first {
                let size = try await track.load(.naturalSize), transform = try await track.load(.preferredTransform)
                let display = size.applying(transform)
                value["width"] = abs(display.width); value["height"] = abs(display.height)
                value["frameRate"] = try await track.load(.nominalFrameRate)
            }
            return value
        case "play":
            if let playbackID { s.events.stop(playbackID) }
            guard try await asset.load(.isPlayable) else { throw SDKFailure.unavailable("无法播放此视频") }
            let p = AVPlayer(playerItem:AVPlayerItem(asset:asset)), layer = AVPlayerLayer(player:p)
            layer.videoGravity = .resizeAspect
            host = s; s.preview = layer; player = p
            let id = UUID().uuidString, events = s.events
            playbackID = id
            observer = p.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.5,preferredTimescale:600),queue:.main) { time in
                Task { @MainActor in if time.seconds.isFinite { events.emit(id,"video.progress",["seconds":time.seconds]) } }
            }
            ended = NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:p.currentItem,queue:.main) { _ in
                Task { @MainActor in events.emit(id,"video.ended",NSNull()) }
            }
            p.play()
            return events.add(id) { [weak self] in self?.close() }
        case "thumbnail":
            let seconds = try a.number("seconds",0), dimension = try a.int("size",512,range:1...4096)
            guard seconds >= 0 else { throw SDKFailure.invalid("seconds") }
            let generator = AVAssetImageGenerator(asset:asset)
            generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width:dimension,height:dimension)
            let frame = try await generator.image(at:CMTime(seconds:seconds,preferredTimescale:600))
            guard let bytes = UIImage(cgImage:frame.image).jpegData(compressionQuality:0.9) else { throw SDKFailure("MEDIA_ERROR","无法生成视频截图") }
            let path = try a.string("to","cache/Thumbnails/" + UUID().uuidString + ".jpg")
            let file = try s.files.temp("frame.jpg"); try bytes.write(to:file); try s.files.store(file,at:path); return path
        case "transcode":
            let preset = try a.choice("quality",["low","medium","high","passthrough"],"medium")
            let name = ["low":AVAssetExportPresetLowQuality,"medium":AVAssetExportPresetMediumQuality,"high":AVAssetExportPresetHighestQuality,"passthrough":AVAssetExportPresetPassthrough][preset]!
            guard let exporter = AVAssetExportSession(asset:asset,presetName:name), exporter.supportedFileTypes.contains(.mp4) else { throw SDKFailure.unavailable("不支持此视频的 MP4 转码") }
            let file = try s.files.temp("video.mp4"), target = try a.string("to")
            exporter.outputFileType = .mp4; exporter.outputURL = file
            let wait = SDKWait<Bool>()
            exporter.exportAsynchronously { Task { @MainActor in
                if exporter.status == .completed { wait.finish(.success(true)) }
                else { wait.finish(.failure(exporter.error ?? SDKFailure("MEDIA_ERROR","视频转码未完成"))) }
            } }
            _ = try await withTaskCancellationHandler { try await wait.value() } onCancel: { exporter.cancelExport() }
            try s.files.store(file,at:target); return target
        default: throw SDKFailure("UNKNOWN_METHOD",method)
        }
    }
    func close() {
        player?.pause()
        if let observer { player?.removeTimeObserver(observer) }
        if let ended { NotificationCenter.default.removeObserver(ended) }
        if host?.preview is AVPlayerLayer { host?.preview = nil }
        observer = nil; ended = nil; player = nil; playbackID = nil
    }
}
