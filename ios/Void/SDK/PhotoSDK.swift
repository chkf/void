import Foundation
import Photos
import PhotosUI
import UIKit
import UniformTypeIdentifiers

@MainActor
private final class PhotoChoice: NSObject, PHPickerViewControllerDelegate {
    let result = SDKWait<[PHPickerResult]>()
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        result.finish(.success(results))
    }
}

@MainActor
final class PhotoSDK: SDKModule {
    private func status(_ level: PHAccessLevel) -> String {
        switch PHPhotoLibrary.authorizationStatus(for:level) {
        case .authorized:return "authorized"; case .limited:return "limited"; case .denied:return "denied"; case .restricted:return "restricted"
        default:return "notDetermined"
        }
    }
    private func authorize(_ level: PHAccessLevel) async throws -> String {
        var auth = PHPhotoLibrary.authorizationStatus(for:level)
        if auth == .notDetermined { auth = await PHPhotoLibrary.requestAuthorization(for:level) }
        guard auth == .authorized || auth == .limited else { throw SDKFailure.denied("图库访问未获授权") }
        return status(level)
    }

    func call(_ method: String, _ a: SDKArgs, in s: SDKSession) async throws -> Any {
        if method == "authorization" { return ["readWrite":status(.readWrite),"addOnly":status(.addOnly)] }
        if method == "pick" {
            let types = try a.strings("mediaTypes", ["image","video"])
            guard !types.isEmpty, Set(types).isSubset(of:["image","video"]) else { throw SDKFailure.invalid("mediaTypes") }
            var config = PHPickerConfiguration(photoLibrary:.shared())
            config.filter = .any(of:types.map { $0 == "image" ? .images : .videos })
            config.selectionLimit = try a.bool("multiple") ? 0 : 1
            config.preferredAssetRepresentationMode = .current
            let chooser = PhotoChoice(), picker = PHPickerViewController(configuration:config)
            picker.delegate = chooser
            let picked = try await s.ui.show(picker, until:chooser.result)
            var media: [[String:Any]] = []
            for item in picked {
                try Task.checkCancellation()
                let provider = item.itemProvider
                guard let type = provider.registeredTypeIdentifiers.compactMap({ UTType($0) }).first(where:{ $0.conforms(to:.image) || $0.conforms(to:.movie) }) else { throw SDKFailure("INVALID_MEDIA","所选媒体格式不可用") }
                let ext = type.preferredFilenameExtension ?? "bin"
                let temp = try s.files.temp("media." + ext), wait = SDKWait<URL>()
                let progress = provider.loadFileRepresentation(forTypeIdentifier:type.identifier) { url, error in
                    let result = Result<URL,Error> {
                        if let error { throw error }
                        guard let url else { throw SDKFailure("INVALID_MEDIA","媒体仍未下载") }
                        try FileManager.default.copyItem(at:url,to:temp)
                        return temp
                    }
                    Task { @MainActor in wait.finish(result) }
                }
                let file = try await withTaskCancellationHandler { try await wait.value() } onCancel: { progress.cancel() }
                let path = "data/Media/" + UUID().uuidString + "." + ext
                try s.files.store(file,at:path)
                var value: [String:Any] = ["path":path,"type":type.conforms(to:.movie) ? "video" : "image","contentType":type.identifier]
                if let id = item.assetIdentifier { value["assetId"] = id }
                media.append(value)
            }
            return media
        }
        if method == "save" {
            _ = try await authorize(.addOnly)
            let file = try s.files.input(a.string("path")), type = try a.choice("type",["image","video"])
            var id: String?
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with:type == "image" ? .photo : .video,fileURL:file,options:nil)
                id = req.placeholderForCreatedAsset?.localIdentifier
            }
            return id as Any? ?? NSNull()
        }
        let auth = try await authorize(.readWrite)
        if method == "requestAccess" { return auth }
        guard let asset = try PHAsset.fetchAssets(withLocalIdentifiers:[a.string("id")],options:nil).firstObject else { throw SDKFailure("NOT_FOUND","照片资源不在允许的范围内") }
        if method == "asset" {
            let resources = PHAssetResource.assetResources(for:asset)
            var value: [String:Any] = ["id":asset.localIdentifier,"width":asset.pixelWidth,"height":asset.pixelHeight,"duration":asset.duration,
                "type":asset.mediaType == .video ? "video" : "image","filename":resources.first?.originalFilename ?? ""]
            if let date = asset.creationDate { value["created"] = date.ISO8601Format() }
            if a.values["to"] != nil {
                let target = try a.string("to")
                guard let resource = resources.first(where:{ $0.type == .photo || $0.type == .video }) ?? resources.first else { throw SDKFailure("NOT_FOUND","资源为空") }
                let tmp = try s.files.temp(resource.originalFilename), options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = true
                try await PHAssetResourceManager.default().writeData(for:resource,toFile:tmp,options:options)
                try Task.checkCancellation(); try s.files.store(tmp,at:target); value["path"] = target
            }
            return value
        }
        let size = try a.int("size",256,range:1...2048)
        let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = true; options.deliveryMode = .highQualityFormat
        let wait = SDKWait<UIImage>()
        let request = PHImageManager.default().requestImage(for:asset,targetSize:CGSize(width:size,height:size),contentMode:.aspectFit,options:options) { image, info in
            guard (info?[PHImageResultIsDegradedKey] as? Bool) != true else { return }
            Task { @MainActor in
                if let error = info?[PHImageErrorKey] as? Error { wait.finish(.failure(error)) }
                else if let image { wait.finish(.success(image)) }
                else { wait.finish(.failure(SDKFailure("INVALID_MEDIA","缩略图不可用"))) }
            }
        }
        defer { PHImageManager.default().cancelImageRequest(request) }
        let image = try await wait.value()
        guard let bytes = image.jpegData(compressionQuality:0.85) else { throw SDKFailure("INVALID_MEDIA","缩略图编码失败") }
        let path = try a.string("to","cache/Thumbnails/" + UUID().uuidString + ".jpg")
        let file = try s.files.temp("thumb.jpg"); try bytes.write(to:file); try s.files.store(file,at:path)
        return path
    }
}
