import AppKit
import ScreenCaptureKit
import CoreImage
import CoreMedia
import CoreVideo
import Metal

struct CapturedFrame {
    let contents: Any
    // Retain the CoreVideo wrapper and pixel buffer while SceneKit uses its Metal texture.
    let pixelBuffer: CVPixelBuffer?
    let metalTexture: CVMetalTexture?
    let receivedAt: Double
    let sourceAgeMS: Double
    let gpu: Bool
}

final class DesktopCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((CapturedFrame) -> Void)?
    var onError: ((String) -> Void)?
    private var stream: SCStream?
    private let queue = DispatchQueue(label:"local.rayneo.capture",qos:.userInteractive)
    private let context = CIContext(options:[.cacheIntermediates:false])
    private let mailbox = LatestFrameMailbox<CapturedFrame>()
    private var textureCache: CVMetalTextureCache?
    private let gpuRequested: Bool
    private let fps: Int
    private var accepting = true
    private(set) var frames = 0
    private(set) var deliveryMS = 0.0
    private(set) var sourceAgeMS = 0.0
    private(set) var gpuFrames = 0
    private(set) var fallbackFrames = 0
    var dropped: Int { mailbox.dropped }

    init(settings: WorkspaceSettings, device: MTLDevice?) {
        fps = settings.captureFPS; gpuRequested = settings.useGPUTextures
        super.init()
        if gpuRequested, let device = device ?? MTLCreateSystemDefaultDevice() {
            CVMetalTextureCacheCreate(kCFAllocatorDefault,nil,device,nil,&textureCache)
        }
    }
    @MainActor func start(_ display: SCDisplay) async throws {
        let config = SCStreamConfiguration()
        config.width=1920;config.height=1080
        config.pixelFormat=kCVPixelFormatType_32BGRA
        config.colorSpaceName=CGColorSpace.sRGB
        config.minimumFrameInterval=CMTime(value:1,timescale:CMTimeScale(fps))
        config.queueDepth=3;config.showsCursor=true;config.capturesAudio=false
        let active=SCStream(filter:SCContentFilter(display:display,excludingWindows:[]),configuration:config,delegate:self)
        stream=active
        try active.addStreamOutput(self,type:.screen,sampleHandlerQueue:queue)
        try await active.startCapture()
        if !accepting {
            // Handle a late startCapture completion after a timeout/cancellation.
            try? active.removeStreamOutput(self,type:.screen)
            _ = try? await AsyncDeadline.run(seconds:3,label:"迟到捕获清理") { try await active.stopCapture() }
            throw CancellationError()
        }
    }
    @MainActor func invalidate() {
        accepting=false;mailbox.disable();onFrame=nil;onError=nil
        if let stream { try? stream.removeStreamOutput(self,type:.screen) }
    }
    @MainActor func stop() async -> String? {
        invalidate()
        guard let active=stream else { return nil }
        defer { stream=nil }
        do {
            try await AsyncDeadline.run(seconds:3,label:"停止捕获") { try await active.stopCapture() }
            return nil
        } catch { return error.localizedDescription }
    }
    func stream(_ stream: SCStream,didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.onError?(error.localizedDescription) }
    }
    func stream(_ stream: SCStream,didOutputSampleBuffer sample:CMSampleBuffer,of type:SCStreamOutputType) {
        guard type == .screen,sample.isValid,let pixel=CMSampleBufferGetImageBuffer(sample) else { return }
        if let attachments=CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:false) as? [[SCStreamFrameInfo:Any]],
           let raw=attachments.first?[.status] as? Int,raw != SCFrameStatus.complete.rawValue { return }
        let now=ProcessInfo.processInfo.systemUptime
        let timestamp=CMSampleBufferGetPresentationTimeStamp(sample)
        let sourceAge=timestamp.isValid ? max(0,(CMClockGetTime(CMClockGetHostTimeClock()).seconds-timestamp.seconds)*1000) : 0
        let frame:CapturedFrame
        var wrapper:CVMetalTexture?
        if gpuRequested,let textureCache,
           CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,textureCache,pixel,nil,.bgra8Unorm_srgb,
               CVPixelBufferGetWidth(pixel),CVPixelBufferGetHeight(pixel),0,&wrapper) == kCVReturnSuccess,
           let wrapper,let texture=CVMetalTextureGetTexture(wrapper) {
            frame=CapturedFrame(contents:texture,pixelBuffer:pixel,metalTexture:wrapper,receivedAt:now,sourceAgeMS:sourceAge,gpu:true)
        } else {
            let image=CIImage(cvPixelBuffer:pixel)
            guard let cg=context.createCGImage(image,from:image.extent) else { return }
            frame=CapturedFrame(contents:cg,pixelBuffer:nil,metalTexture:nil,receivedAt:now,sourceAgeMS:sourceAge,gpu:false)
        }
        if mailbox.offer(frame) {
            DispatchQueue.main.async { [weak self] in
                guard let self,let latest=self.mailbox.take() else { return }
                self.frames += 1
                self.deliveryMS=0.9*self.deliveryMS+0.1*max(0,(ProcessInfo.processInfo.systemUptime-latest.receivedAt)*1000)
                self.sourceAgeMS=latest.sourceAgeMS
                if latest.gpu { self.gpuFrames += 1 } else { self.fallbackFrames += 1 }
                self.onFrame?(latest)
            }
        }
    }
}
