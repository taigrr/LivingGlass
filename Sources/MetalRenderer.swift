import Metal
import MetalKit
import simd

// Must match Shaders.metal VertexIn
struct Vertex {
    var basePos: SIMD2<Float>
    var heightFactor: Float
    var faceIndex: UInt32
}

// Must match Shaders.metal InstanceIn
struct CubeInstance {
    var posHeightScale: SIMD4<Float>  // xy=screenPos, z=cubeHeight, w=scale
    var topColor: SIMD4<Float>        // rgb, a=alpha
    var leftColor: SIMD4<Float>       // rgb, a unused
    var rightColor: SIMD4<Float>      // rgb, a unused
}

// Precomputed face colors (CPU-side)
struct FaceRGB {
    let top: SIMD3<Float>
    let left: SIMD3<Float>
    let right: SIMD3<Float>
}

class MetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState
    let vertexBuffer: MTLBuffer
    let vertexCount: Int

    // Dynamic
    var instanceBuffer: MTLBuffer?
    var instanceCount: Int = 0
    var viewportSize: SIMD2<Float> = .zero

    // Tile geometry (set by view)
    var tileW: Float = 72
    var tileH: Float = 18

    init?(mtkView: MTKView, bundle: Bundle = Bundle.main) {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.device = device
        mtkView.device = device
        mtkView.depthStencilPixelFormat = .depth32Float

        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        // Load shader library (try provided bundle first, then main bundle)
        var library: MTLLibrary?
        library = try? device.makeDefaultLibrary(bundle: bundle)
        if library == nil, let libURL = bundle.url(forResource: "default", withExtension: "metallib") {
            library = try? device.makeLibrary(URL: libURL)
        }
        if library == nil && bundle != Bundle.main {
            library = try? device.makeDefaultLibrary(bundle: Bundle.main)
            if library == nil, let libURL = Bundle.main.url(forResource: "default", withExtension: "metallib") {
                library = try? device.makeLibrary(URL: libURL)
            }
        }
        guard let lib = library,
              let vertFunc = lib.makeFunction(name: "vertex_main"),
              let fragFunc = lib.makeFunction(name: "fragment_main") else { return nil }

        // Pipeline with depth
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertFunc
        desc.fragmentFunction = fragFunc
        desc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        desc.depthAttachmentPixelFormat = .depth32Float

        guard let ps = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }
        self.pipelineState = ps

        // Depth stencil: closer cubes occlude farther ones
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        guard let dss = device.makeDepthStencilState(descriptor: depthDesc) else { return nil }
        self.depthStencilState = dss

        // Build unit cube template
        let (verts, count) = MetalRenderer.buildCubeTemplate()
        guard let vb = device.makeBuffer(bytes: verts, length: MemoryLayout<Vertex>.stride * count) else { return nil }
        self.vertexBuffer = vb
        self.vertexCount = count

        super.init()
    }

    // Build the 18 vertices for one isometric cube (3 faces × 2 triangles × 3 vertices)
    // Positions are in "unit" space: halfW=0.5, halfH=0.125 (4:1 ratio)
    // cubeHeight is applied via heightFactor in the shader
    static func buildCubeTemplate() -> ([Vertex], Int) {
        let hw: Float = 0.5
        let hh: Float = 0.125  // 4:1 ratio

        // Top face vertices (all at heightFactor=1)
        let topN = SIMD2<Float>(0, hh)
        let topE = SIMD2<Float>(hw, 0)
        let topS = SIMD2<Float>(0, -hh)
        let topW = SIMD2<Float>(-hw, 0)

        // Bottom vertices (heightFactor=0)
        let botS = SIMD2<Float>(0, -hh)
        let botE = SIMD2<Float>(hw, 0)
        let botW = SIMD2<Float>(-hw, 0)

        var verts: [Vertex] = []

        // Top face (faceIndex=0, heightFactor=1)
        verts.append(Vertex(basePos: topN, heightFactor: 1, faceIndex: 0))
        verts.append(Vertex(basePos: topE, heightFactor: 1, faceIndex: 0))
        verts.append(Vertex(basePos: topS, heightFactor: 1, faceIndex: 0))
        verts.append(Vertex(basePos: topN, heightFactor: 1, faceIndex: 0))
        verts.append(Vertex(basePos: topS, heightFactor: 1, faceIndex: 0))
        verts.append(Vertex(basePos: topW, heightFactor: 1, faceIndex: 0))

        // Left face (faceIndex=1)
        verts.append(Vertex(basePos: topW, heightFactor: 1, faceIndex: 1))
        verts.append(Vertex(basePos: topS, heightFactor: 1, faceIndex: 1))
        verts.append(Vertex(basePos: botS, heightFactor: 0, faceIndex: 1))
        verts.append(Vertex(basePos: topW, heightFactor: 1, faceIndex: 1))
        verts.append(Vertex(basePos: botS, heightFactor: 0, faceIndex: 1))
        verts.append(Vertex(basePos: botW, heightFactor: 0, faceIndex: 1))

        // Right face (faceIndex=2)
        verts.append(Vertex(basePos: topS, heightFactor: 1, faceIndex: 2))
        verts.append(Vertex(basePos: topE, heightFactor: 1, faceIndex: 2))
        verts.append(Vertex(basePos: botE, heightFactor: 0, faceIndex: 2))
        verts.append(Vertex(basePos: topS, heightFactor: 1, faceIndex: 2))
        verts.append(Vertex(basePos: botE, heightFactor: 0, faceIndex: 2))
        verts.append(Vertex(basePos: botS, heightFactor: 0, faceIndex: 2))

        return (verts, verts.count)
    }

    func updateInstances(_ instances: [CubeInstance]) {
        instanceCount = instances.count
        guard instanceCount > 0 else { return }

        let size = MemoryLayout<CubeInstance>.stride * instanceCount
        if instanceBuffer == nil || instanceBuffer!.length < size {
            instanceBuffer = device.makeBuffer(length: max(size, 4096), options: .storageModeShared)
        }
        instanceBuffer?.contents().copyMemory(from: instances, byteCount: size)
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = SIMD2<Float>(Float(size.width), Float(size.height))
    }

    func draw(in view: MTKView) {
        guard instanceCount > 0,
              let instanceBuffer = instanceBuffer,
              let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmdBuffer = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthStencilState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)

        var vp = viewportSize
        encoder.setVertexBytes(&vp, length: MemoryLayout<SIMD2<Float>>.size, index: 2)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount,
                               instanceCount: instanceCount)

        encoder.endEncoding()
        cmdBuffer.present(drawable)
        cmdBuffer.commit()
    }
}
