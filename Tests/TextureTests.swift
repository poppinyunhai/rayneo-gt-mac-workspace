import AppKit
import SceneKit
import Metal
import CoreVideo
import CoreImage

@main struct TextureTests {
    static func main() throws {
        guard let device=MTLCreateSystemDefaultDevice() else { throw NSError(domain:"TextureTest",code:1) }
        var pixel:CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault,128,128,kCVPixelFormatType_32BGRA,
            [kCVPixelBufferMetalCompatibilityKey:true,kCVPixelBufferIOSurfacePropertiesKey:[:]] as CFDictionary,&pixel)
        let buffer=pixel!
        CVPixelBufferLockBaseAddress(buffer,[])
        let bytes=CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to:UInt8.self)
        let stride=CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<128 { for x in 0..<128 {
            let i=y*stride+x*4
            if x<64 { bytes[i]=y<64 ? 0 : 255;bytes[i+1]=0;bytes[i+2]=y<64 ? 255 : 0 }
            else { let value:UInt8=y<64 ? 128 : 32;bytes[i]=value;bytes[i+1]=value;bytes[i+2]=value }
            bytes[i+3]=255
        }}
        CVPixelBufferUnlockBaseAddress(buffer,[])
        var cache:CVMetalTextureCache?;CVMetalTextureCacheCreate(kCFAllocatorDefault,nil,device,nil,&cache)
        var wrapper:CVMetalTexture?
        precondition(CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,cache!,buffer,nil,.bgra8Unorm_srgb,128,128,0,&wrapper)==kCVReturnSuccess)
        let texture=CVMetalTextureGetTexture(wrapper!)!
        let cg=CIContext().createCGImage(CIImage(cvPixelBuffer:buffer),from:CGRect(x:0,y:0,width:128,height:128))!
        func render(_ contents:Any,flip:Bool) -> [Double] {
            let scene=SCNScene(),camera=SCNNode()
            camera.camera=SCNCamera();camera.position=SCNVector3(0,0,3);camera.camera?.fieldOfView=45
            scene.rootNode.addChildNode(camera)
            let plane=SCNPlane(width:2,height:2);plane.firstMaterial?.lightingModel = .constant
            plane.firstMaterial?.diffuse.contents=contents
            if flip { var transform=SCNMatrix4MakeScale(1,-1,1);transform.m42=1;plane.firstMaterial?.diffuse.contentsTransform=transform }
            scene.rootNode.addChildNode(SCNNode(geometry:plane))
            let renderer=SCNRenderer(device:device,options:nil);renderer.scene=scene;renderer.pointOfView=camera
            let image=renderer.snapshot(atTime:0,with:CGSize(width:128,height:128),antialiasingMode:.none)
            let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
            return [32,96].flatMap { y -> [Double] in
                [32,96].flatMap { x -> [Double] in
                    let color=bitmap.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
                    return [Double(color.redComponent),Double(color.greenComponent),Double(color.blueComponent)]
                }
            }
        }
        let reference=render(cg,flip:false),raw=render(texture,flip:false),flipped=render(texture,flip:true)
        func matches(_ sample:[Double]) -> Bool { zip(reference,sample).allSatisfy { abs($0-$1)<0.05 } }
        print("CoreVideo isFlipped:",CVMetalTextureIsFlipped(wrapper!))
        print("Reference:",reference,"raw:",raw,"flipped:",flipped)
        fflush(stdout)
        precondition(matches(raw),"Metal and CGImage texture paths differ; investigate orientation before shipping")
        print("PASS: GPU texture matches compatibility path; requiresYFlip=",!matches(raw))
    }
}
