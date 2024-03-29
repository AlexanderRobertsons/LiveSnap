import Photos
import MobileCoreServices
class LivePhotoMaker {
    let documentsDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
    let inputImagePath: String
    let inputVideoPath: String
    let outputImagePath: String
    let outputVideoPath: String
    let assetID: String = UUID().uuidString
    init(imagePath: String, videoPath: String) {
        self.inputImagePath = imagePath
        self.inputVideoPath = videoPath
        self.outputImagePath = "\(documentsDirectory)/temp.jpeg"
        self.outputVideoPath = "\(documentsDirectory)/temp.mov"
        if FileManager.default.fileExists(atPath: outputImagePath) {
            let _ = try? FileManager.default.removeItem(at: URL(fileURLWithPath: outputImagePath))
        }
        if FileManager.default.fileExists(atPath: outputVideoPath) {
            let _ = try? FileManager.default.removeItem(at: URL(fileURLWithPath: outputVideoPath))
        }
    }
    func create(completion: @escaping (LivePhoto?) -> ()) {
        guard convertImageToLivePhotoFormat(inputImagePath: inputImagePath, outputImagePath: outputImagePath) else { completion(nil); return }
        convertVideoToLivePhotoFormat(inputVideoPath: inputVideoPath, outputVideoPath: outputVideoPath, completion: { (success: Bool) in
            guard success else { completion(nil); return }
            self.makeLivePhotoFromFormattedItems(imagePath: self.outputImagePath, videoPath: self.outputVideoPath, previewImage: UIImage(), completion: { (livePhoto: PHLivePhoto?) in
                if let livePhoto = livePhoto {
                    completion(LivePhoto(phLivePhoto: livePhoto, imageURL: URL(fileURLWithPath: self.outputImagePath), videoURL: URL(fileURLWithPath: self.outputVideoPath)))
                } else {
                    completion(nil)
                }
            })
        })
    }
    func makeLivePhotoFromFormattedItems(imagePath: String, videoPath: String, previewImage: UIImage, completion: @escaping (PHLivePhoto?) -> Void) {
        let imageURL = URL(fileURLWithPath: imagePath)
        let videoURL = URL(fileURLWithPath: videoPath)
        PHLivePhoto.request(withResourceFileURLs: [imageURL, videoURL], placeholderImage: previewImage, targetSize: CGSize.zero, contentMode: .aspectFit) { (livePhoto: PHLivePhoto?, infoDict: [AnyHashable : Any]) in
            completion(livePhoto)
        }
    }
    func convertImageToLivePhotoFormat(inputImagePath: String, outputImagePath: String) -> Bool {
        guard let image = UIImage(contentsOfFile: inputImagePath) else { return false }
        guard let imageData = image.jpegData(compressionQuality: 1.0) else { return false }
        let destinationURL = URL(fileURLWithPath: outputImagePath) as CFURL
        guard let imageDestination = CGImageDestinationCreateWithURL(destinationURL, kUTTypeJPEG, 1, nil) else { return false }
        defer { CGImageDestinationFinalize(imageDestination) }
        guard let imageSource: CGImageSource = CGImageSourceCreateWithData(imageData as CFData, nil) else { return false }
        guard let imageSourceCopyProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as NSDictionary? else { return false }
        guard let metadata = imageSourceCopyProperties.mutableCopy() as? NSMutableDictionary else { return false }
        let makerNote = NSMutableDictionary()
        let kFigAppleMakerNote_AssetIdentifier = "17"
        makerNote.setObject(assetID, forKey: kFigAppleMakerNote_AssetIdentifier as NSCopying)
        metadata.setObject(makerNote, forKey: kCGImagePropertyMakerAppleDictionary as String as String as NSCopying)
        CGImageDestinationAddImageFromSource(imageDestination, imageSource, 0, metadata)
        return true
    }
    func convertVideoToLivePhotoFormat(inputVideoPath: String, outputVideoPath: String, completion: @escaping (Bool) -> ()) {
        guard let writer = try? AVAssetWriter(outputURL: URL(fileURLWithPath: outputVideoPath), fileType: .mov) else { completion(false); return }
        let item = AVMutableMetadataItem()
        item.key = "com.apple.quicktime.content.identifier" as (NSCopying & NSObjectProtocol)?
        item.keySpace = AVMetadataKeySpace.quickTimeMetadata
        item.value = assetID as (NSCopying & NSObjectProtocol)?
        item.dataType = "com.apple.metadata.datatype.UTF-8"
        writer.metadata = [item]
        let asset = AVURLAsset(url: URL(fileURLWithPath: inputVideoPath))
        guard let track = asset.tracks.first else { completion(false); return }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA as UInt32)])
        guard let reader = try? AVAssetReader(asset: asset) else { completion(false); return }
        reader.add(output)
        let outputSettings : [String : Any]
        if #available(iOS 11.0, *) {
            outputSettings = [
                AVVideoCodecKey: AVVideoCodecType.h264 as AnyObject,
                AVVideoWidthKey: track.naturalSize.width as AnyObject,
                AVVideoHeightKey: track.naturalSize.height as AnyObject
            ]
        } else {
            outputSettings = [
                AVVideoWidthKey: track.naturalSize.width as AnyObject,
                AVVideoHeightKey: track.naturalSize.height as AnyObject
            ]
        }
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = true
        writerInput.transform = track.preferredTransform
        writer.add(writerInput)
        let keySpaceQuickTimeMetadata = "mdta"
        let keyStillImageTime = "com.apple.quicktime.still-image-time"
        let metadataSpecifications = [kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as NSString: "\(keySpaceQuickTimeMetadata)/\(keyStillImageTime)",
                                      kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as NSString: "com.apple.metadata.datatype.int8"]
        var formatDescription: CMFormatDescription?
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed, metadataSpecifications: [metadataSpecifications] as CFArray, formatDescriptionOut: &formatDescription)
        let assetWriterInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: formatDescription)
        let adapter = AVAssetWriterInputMetadataAdaptor(assetWriterInput: assetWriterInput)
        writer.add(adapter.assetWriterInput)
        writer.startWriting()
        reader.startReading()
        writer.startSession(atSourceTime: CMTime.zero)
        let item2 = AVMutableMetadataItem()
        item2.key = keyStillImageTime as (NSCopying & NSObjectProtocol)?
        item2.keySpace = AVMetadataKeySpace.quickTimeMetadata
        item2.value = 0 as (NSCopying & NSObjectProtocol)?
        item2.dataType = "com.apple.metadata.datatype.int8"
        adapter.append(AVTimedMetadataGroup(items: [item2], timeRange: CMTimeRangeMake(start: CMTimeMake(value: 0, timescale: 1000), duration: CMTimeMake(value: 200, timescale: 3000))))
        writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "assetVideoWriterQueue", attributes: []), using: {
            while writerInput.isReadyForMoreMediaData {
                if reader.status == .reading {
                    if let buffer = output.copyNextSampleBuffer() {
                        if !writerInput.append(buffer) {
                            reader.cancelReading()
                        }
                    }
                } else {
                    writerInput.markAsFinished()
                    writer.finishWriting() {
                        if let e = writer.error {
                            print(e.localizedDescription)
                            completion(false)
                            return
                        }
                    }
                }
            }
        })
        while writer.status == .writing {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        }
        completion(true)
    }
}
