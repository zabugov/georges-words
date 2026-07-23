import AVFoundation

enum AudioTrim {
    /// Trim leading/trailing near-silence (e.g. the pause before speaking
    /// and the beat between finishing and releasing the key), keeping
    /// 0.15 s of padding on each side. Less audio → faster transcription.
    static func trimSilence(_ samples: [Float], threshold: Float = 0.003) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let padding = 2_400 // 0.15 s at 16 kHz

        var start = 0
        while start < samples.count && abs(samples[start]) < threshold { start += 1 }
        // All silence — nothing to keep.
        guard start < samples.count else { return [] }

        var end = samples.count - 1
        while end > start && abs(samples[end]) < threshold { end -= 1 }

        let from = max(0, start - padding)
        let to = min(samples.count, end + 1 + padding)
        return Array(samples[from..<to])
    }

    /// True when the clip is quiet enough to be a pause in speech — RMS
    /// under the same near-silence threshold trimSilence trims at. Used
    /// by speculative polish to spot pauses worth polishing during.
    static func isNearSilence(_ samples: [Float], threshold: Float = 0.003) -> Bool {
        guard !samples.isEmpty else { return true }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return (sum / Float(samples.count)).squareRoot() < threshold
    }
}

/// Captures microphone audio and accumulates it as 16 kHz mono Float32
/// samples — the input format Whisper-family models expect.
final class AudioRecorder {

    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()

    /// Preferred input device UID (backlog 6.5); nil = system default.
    /// Applied at each start(); any failure to resolve or apply falls
    /// back to the default input — a stale picker choice must never
    /// break dictation.
    var preferredInputUID: String?

    /// Called on the main thread with a 0…1 loudness estimate while recording.
    var onLevel: ((Float) -> Void)?

    /// Called on the main thread when the audio hardware configuration
    /// changes (e.g. AirPods connect/disconnect) — a recording in flight is
    /// using a stale engine graph at that point.
    var onConfigurationChange: (() -> Void)?

    init() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.onConfigurationChange?()
        }
    }

    func start() throws {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
        try beginCapture()
    }

    /// Rebuild the engine graph and tap after a device/configuration
    /// change WITHOUT discarding captured audio — samples are already
    /// converted to 16 kHz mono, so the dictation continues seamlessly
    /// on the new device (owner report, 2026-07-23: the first press
    /// after every update died with "Audio device changed").
    func restart() throws {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try beginCapture()
    }

    private func beginCapture() throws {
        let input = engine.inputNode
        // Select the microphone before reading the format — the format
        // follows the device. Always assign explicitly: the audio unit
        // keeps whatever device was set on a previous start, so switching
        // the picker back to "System default" (or unplugging the chosen
        // mic) must actively re-point it at today's default input, not
        // just skip the selection (review P2, 2026-07-22).
        var chosen: AudioDeviceID?
        if let uid = preferredInputUID {
            chosen = AudioInputDevices.deviceID(forUID: uid)
            if chosen == nil {
                DebugLog.log("Chosen input device not present — using system default")
            }
        }
        if chosen == nil {
            chosen = AudioInputDevices.systemDefaultInputID()
        }
        if let deviceID = chosen, let unit = input.audioUnit {
            // Only assign when it actually differs: setting the property
            // fires AVAudioEngineConfigurationChange, and doing that on
            // every start made the first recording after launch cancel
            // itself (owner report, 2026-07-23).
            var current = AudioDeviceID(0)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            let read = AudioUnitGetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &current, &size
            )
            if read != noErr || current != deviceID {
                var device = deviceID
                let status = AudioUnitSetProperty(
                    unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                    &device, UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                if status != noErr {
                    DebugLog.log("Input device select failed (\(status)) — using engine default")
                }
            }
        }
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(
                domain: "GeorgesWords", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No microphone input available."]
            )
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // Roll the tap back — a leftover tap makes the next start()
            // attempt install a second one on the same bus, which crashes.
            input.removeTap(onBus: 0)
            converter = nil
            throw error
        }
    }

    /// Samples captured so far, without copying the buffer — cheap enough
    /// to poll every preview tick.
    var sampleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }

    /// Copy of the samples captured so far — used by the live-preview loop
    /// while recording continues.
    func snapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    /// Copy of just the last `seconds` of audio. The live preview only
    /// needs the recent window — keeping its per-tick cost constant no
    /// matter how long the recording runs.
    func snapshotTail(seconds: Double) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let keep = Int(seconds * 16_000)
        guard samples.count > keep else { return samples }
        return Array(samples.suffix(keep))
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: converted, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard conversionError == nil, let channel = converted.floatChannelData?[0] else { return }

        let frameCount = Int(converted.frameLength)
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: frameCount))
        lock.unlock()

        if let onLevel, frameCount > 0 {
            var sum: Float = 0
            for i in 0..<frameCount { sum += channel[i] * channel[i] }
            let rms = (sum / Float(frameCount)).squareRoot()
            // Map typical speech RMS (~0.01–0.2) into a lively 0…1 range.
            let level = min(1, rms * 8)
            DispatchQueue.main.async { onLevel(level) }
        }
    }
}
