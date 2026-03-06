import ScreenCaptureKit
import Accelerate
import CoreMedia

// MARK: - Audio Reactor (System Audio via ScreenCaptureKit)

class AudioReactor: NSObject, SCStreamOutput, SCStreamDelegate {
    static let shared = AudioReactor()

    private var stream: SCStream?
    private let lock = NSLock()
    private var _levels = AudioLevels.zero
    private(set) var isRunning = false
    private var isStarting = false
    private let audioQueue = DispatchQueue(label: "com.taigrr.livingglass.audio", qos: .userInteractive)

    // Exponential smoothing state (fast attack, slow release)
    private var smoothedBands = [Float](repeating: 0, count: 32)
    private var smoothedRMS: Float = 0
    private var smoothedPeak: Float = 0
    private var smoothedBass: Float = 0
    private var smoothedMid: Float = 0
    private var smoothedHigh: Float = 0

    // Debug: count audio callbacks to verify capture is working
    private var callbackCount: Int = 0

    // Attack/release coefficients (per-callback, ~100 callbacks/sec at 48kHz/480 frames)
    private let attack: Float = 0.6    // snap up quickly
    private let release: Float = 0.3   // drop fast — bars visibly fall between beats

    // 32 logarithmic band boundaries in Hz (20 Hz → 20 kHz)
    private let bandEdges: [Float] = {
        var edges = [Float]()
        let numBands = 32
        let minFreq: Float = 20.0
        let maxFreq: Float = 20000.0
        let logMin = log2f(minFreq)
        let logMax = log2f(maxFreq)
        for i in 0...numBands {
            let t = Float(i) / Float(numBands)
            edges.append(exp2f(logMin + t * (logMax - logMin)))
        }
        return edges
    }()

    var levels: AudioLevels {
        lock.lock()
        defer { lock.unlock() }
        return _levels
    }

    private var sensitivityMultiplier: Float {
        switch LivingGlassPreferences.audioSensitivity {
        case 0: return 0.5
        case 2: return 2.0
        default: return 1.0
        }
    }

    private override init() {
        super.init()
    }

    /// Start capturing system audio. Retries once after 2s on failure.
    /// Calls onFailure on main thread only after the retry also fails.
    func start(onFailure: (() -> Void)? = nil) {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        attemptStart { [weak self] success in
            guard let self = self else { return }
            if success {
                self.isStarting = false
            } else {
                // Retry once after 2 seconds (permission may need time to propagate)
                DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                    self.attemptStart { success in
                        self.isStarting = false
                        if !success, let onFailure = onFailure {
                            DispatchQueue.main.async { onFailure() }
                        }
                    }
                }
            }
        }
    }

    private func attemptStart(completion: @escaping (Bool) -> Void) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            guard let self = self else {
                completion(false)
                return
            }

            if let error = error {
                NSLog("[LivingGlass] SCShareableContent error: \(error)")
            }

            guard let content = content, let display = content.displays.first else {
                NSLog("[LivingGlass] No displays available (content=\(content != nil), displays=\(content?.displays.count ?? 0))")
                completion(false)
                return
            }

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.channelCount = 2
            config.sampleRate = 48000
            // Low-overhead video (we only want audio, but stream requires video config)
            config.width = 64
            config.height = 64
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            config.showsCursor = false

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let stream = SCStream(filter: filter, configuration: config, delegate: self)

            do {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.audioQueue)
                stream.startCapture { error in
                    if let error = error {
                        NSLog("[LivingGlass] startCapture failed: \(error)")
                        completion(false)
                    } else {
                        NSLog("[LivingGlass] Audio capture started successfully")
                        self.stream = stream
                        self.isRunning = true
                        completion(true)
                    }
                }
            } catch {
                NSLog("[LivingGlass] addStreamOutput failed: \(error)")
                completion(false)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        stream?.stopCapture()
        stream = nil
        isRunning = false

        lock.lock()
        _levels = .zero
        smoothedBands = [Float](repeating: 0, count: 32)
        smoothedRMS = 0
        smoothedPeak = 0
        smoothedBass = 0
        smoothedMid = 0
        smoothedHigh = 0
        lock.unlock()
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let data = dataPointer else { return }

        let floatCount = length / MemoryLayout<Float>.size
        guard floatCount > 0 else { return }

        let floatPtr = UnsafeRawPointer(data).bindMemory(to: Float.self, capacity: floatCount)

        // Mix stereo to mono
        let channelCount = 2
        let frameCount = floatCount / channelCount
        guard frameCount > 0 else { return }

        var mono = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let left = floatPtr[i * channelCount]
            let right = channelCount > 1 ? floatPtr[i * channelCount + 1] : left
            mono[i] = (left + right) * 0.5
        }

        analyzeAudio(mono, frameCount: frameCount, sampleRate: 48000.0)

        // Log audio levels every ~2 seconds for debugging
        callbackCount += 1
        if callbackCount % 200 == 0 {
            let lvl = levels
            NSLog("[LivingGlass] Audio callback #%d — rms=%.3f bass=%.3f mid=%.3f high=%.3f bands(8of32)=[%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f]",
                  callbackCount, lvl.rms, lvl.bass, lvl.mid, lvl.high,
                  lvl.bands[0], lvl.bands[4], lvl.bands[8], lvl.bands[12],
                  lvl.bands[16], lvl.bands[20], lvl.bands[24], lvl.bands[28])
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isRunning = false
        lock.lock()
        _levels = .zero
        lock.unlock()
    }

    // MARK: - Smoothing

    /// Smooth a value with fast attack, slow release
    private func smooth(current: Float, target: Float) -> Float {
        if target > current {
            return current + (target - current) * attack
        } else {
            return current * release + target * (1.0 - release)
        }
    }

    // MARK: - FFT Analysis

    private func analyzeAudio(_ samples: [Float], frameCount: Int, sampleRate: Float) {
        let sensitivity = sensitivityMultiplier
        let fftSize = 1024
        let halfFFT = fftSize / 2
        let sampleCount = min(frameCount, fftSize)

        // RMS
        var rawRMS: Float = 0
        samples.withUnsafeBufferPointer { buf in
            vDSP_measqv(buf.baseAddress!, 1, &rawRMS, vDSP_Length(sampleCount))
        }
        rawRMS = min(sqrtf(rawRMS) * sensitivity * 4.0, 1.0)

        // Peak
        var rawPeak: Float = 0
        samples.withUnsafeBufferPointer { buf in
            vDSP_maxmgv(buf.baseAddress!, 1, &rawPeak, vDSP_Length(sampleCount))
        }
        rawPeak = min(rawPeak * sensitivity * 2.0, 1.0)

        // Window the signal
        var windowed = [Float](repeating: 0, count: fftSize)
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        samples.withUnsafeBufferPointer { buf in
            vDSP_vmul(buf.baseAddress!, 1, window, 1, &windowed, 1, vDSP_Length(sampleCount))
        }

        // FFT
        var realPart = [Float](repeating: 0, count: halfFFT)
        var imagPart = [Float](repeating: 0, count: halfFFT)

        var rawBands = [Float](repeating: 0, count: 32)
        var rawBass: Float = 0
        var rawMid: Float = 0
        var rawHigh: Float = 0

        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(
                    realp: realBuf.baseAddress!,
                    imagp: imagBuf.baseAddress!
                )

                windowed.withUnsafeBufferPointer { windowedBuf in
                    windowedBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfFFT) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfFFT))
                    }
                }

                if let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2f(Float(fftSize))), FFTRadix(kFFTRadix2)) {
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, vDSP_Length(log2f(Float(fftSize))), FFTDirection(FFT_FORWARD))
                    vDSP_destroy_fftsetup(fftSetup)
                }

                var magnitudes = [Float](repeating: 0, count: halfFFT)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfFFT))

                // Normalize magnitudes by FFT size (critical for correct scaling)
                var normFactor: Float = 1.0 / Float(fftSize * fftSize)
                vDSP_vsmul(magnitudes, 1, &normFactor, &magnitudes, 1, vDSP_Length(halfFFT))

                let binWidth = sampleRate / Float(fftSize)

                // Compute 32 frequency bands
                for band in 0..<32 {
                    let loFreq = bandEdges[band]
                    let hiFreq = bandEdges[band + 1]
                    let loBin = max(Int(loFreq / binWidth), 0)
                    let hiBin = min(Int(hiFreq / binWidth), halfFFT)
                    guard hiBin > loBin else { continue }

                    var energy: Float = 0
                    let slice = Array(magnitudes[loBin..<hiBin])
                    slice.withUnsafeBufferPointer { buf in
                        vDSP_meanv(buf.baseAddress!, 1, &energy, vDSP_Length(slice.count))
                    }
                    // sqrt for perceptual loudness, moderate boost for higher bands
                    let boost: Float = 2.0 + Float(band) * 0.15
                    rawBands[band] = sqrtf(energy) * sensitivity * boost
                }

                // Legacy 3-band for compatibility (bass/mid/high)
                let bassEnd = min(Int(250.0 / binWidth), halfFFT)
                let midEnd = min(Int(4000.0 / binWidth), halfFFT)

                if bassEnd > 0 {
                    var e: Float = 0
                    vDSP_meanv(magnitudes, 1, &e, vDSP_Length(bassEnd))
                    rawBass = min(sqrtf(e) * sensitivity * 3.0, 1.0)
                }
                if midEnd > bassEnd {
                    let slice = Array(magnitudes[bassEnd..<midEnd])
                    var e: Float = 0
                    slice.withUnsafeBufferPointer { buf in
                        vDSP_meanv(buf.baseAddress!, 1, &e, vDSP_Length(slice.count))
                    }
                    rawMid = min(sqrtf(e) * sensitivity * 4.0, 1.0)
                }
                if halfFFT > midEnd {
                    let slice = Array(magnitudes[midEnd..<halfFFT])
                    var e: Float = 0
                    slice.withUnsafeBufferPointer { buf in
                        vDSP_meanv(buf.baseAddress!, 1, &e, vDSP_Length(slice.count))
                    }
                    rawHigh = min(sqrtf(e) * sensitivity * 5.0, 1.0)
                }
            }
        }

        // Apply exponential smoothing
        smoothedRMS = smooth(current: smoothedRMS, target: rawRMS)
        smoothedPeak = smooth(current: smoothedPeak, target: rawPeak)
        smoothedBass = smooth(current: smoothedBass, target: rawBass)
        smoothedMid = smooth(current: smoothedMid, target: rawMid)
        smoothedHigh = smooth(current: smoothedHigh, target: rawHigh)
        for i in 0..<32 {
            smoothedBands[i] = smooth(current: smoothedBands[i], target: rawBands[i])
        }

        lock.lock()
        _levels = AudioLevels(
            rms: smoothedRMS,
            bass: smoothedBass,
            mid: smoothedMid,
            high: smoothedHigh,
            peak: smoothedPeak,
            bands: smoothedBands
        )
        lock.unlock()
    }
}
