import Foundation

/// The sound of each cue, as samples.
///
/// Synthesized rather than shipped, so it's licence-free and testable. Every
/// cue is a pure function of its input — a seeded generator, never `Float.random`.
public enum SoundCue {
    public static let sampleRate: Double = 44_100

    /// What every cue is normalized to. One number, so nothing clips on the
    /// way to 16-bit and no cue arrives twice as loud as its neighbour.
    public static let peak: Float = 0.7

    /// The shutter cue outlasts `CaptureSequence.flashSeconds` on purpose:
    /// the flash is fill light, the sound is a shutter, and a shutter has a tail.
    public static func duration(of cue: CaptureCue) -> Double {
        switch cue {
        case .tick: 0.04
        case .shutter: 0.09
        case .finished: 0.40
        }
    }

    /// Mono samples in -1...1, normalized and ending in true silence.
    public static func samples(for cue: CaptureCue) -> [Float] {
        var buffer: [Float]
        switch cue {
        case .tick: buffer = tick()
        case .shutter: buffer = shutter()
        case .finished: buffer = chime()
        }
        normalize(&buffer)
        // Ramped to zero rather than trusted to decay, so a stopped buffer
        // doesn't click mid-swing. Fade is proportional: 3ms suits a click but not a chime.
        release(&buffer, seconds: max(0.003, duration(of: cue) * 0.05))
        return buffer
    }

    public static func wav(for cue: CaptureCue) -> Data {
        wav(samples(for: cue))
    }

    /// A dry blip. Short enough to sit inside one second of countdown with
    /// room to spare, and pitched above speech so it carries across a room.
    private static func tick() -> [Float] {
        var buffer = silence(duration(of: .tick))
        for index in buffer.indices {
            let t = time(index)
            buffer[index] = Float(sin(2 * .pi * 1_200 * t) * attack(t, 0.001) * exp(-t / 0.006))
        }
        return buffer
    }

    /// Two clicks: a mirror and a curtain. One click is a tap on a desk; the
    /// gap between two is what reads as a camera.
    private static func shutter() -> [Float] {
        var buffer = silence(duration(of: .shutter))
        click(into: &buffer, at: 0, level: 1.0, decay: 0.010, cutoff: 3_500, seed: 0x5EED_1)
        click(into: &buffer, at: 0.055, level: 0.6, decay: 0.016, cutoff: 1_800, seed: 0x5EED_2)
        return buffer
    }

    /// Band-limited noise: low-pass keeps it a mechanism rather than a cymbal,
    /// high-pass keeps it from reading as a door.
    private static func click(
        into buffer: inout [Float], at start: Double, level: Double,
        decay: Double, cutoff: Double, seed: UInt64
    ) {
        var noise = SeededNoise(seed: seed)
        let lowPass = 1 - exp(-2 * .pi * cutoff / sampleRate)
        let highPass = exp(-2 * .pi * 400 / sampleRate)
        var low = 0.0, highIn = 0.0, highOut = 0.0

        for index in frames(start)..<buffer.count {
            let t = time(index - frames(start))
            let sample = Double(noise.next())
            low += lowPass * (sample - low)
            highOut = highPass * (highOut + low - highIn)
            highIn = low
            let envelope = attack(t, 0.0003) * exp(-t / decay)
            buffer[index] += Float(highOut * envelope * level)
        }
    }

    /// Two notes, the second entering while the first still rings. One note is
    /// a beep and says "alert"; two are a chime and say "come and look".
    private static func chime() -> [Float] {
        var buffer = silence(duration(of: .finished))
        note(into: &buffer, at: 0, frequency: 880, decay: 0.13)
        note(into: &buffer, at: 0.12, frequency: 1_318.51, decay: 0.16)
        return buffer
    }

    private static func note(
        into buffer: inout [Float], at start: Double, frequency: Double, decay: Double
    ) {
        for index in frames(start)..<buffer.count {
            let t = time(index - frames(start))
            let envelope = attack(t, 0.005) * exp(-t / decay)
            // A bare sine reads as a test tone; one quiet partial is enough to sound like an instrument.
            let tone = sin(2 * .pi * frequency * t) + 0.25 * sin(4 * .pi * frequency * t)
            buffer[index] += Float(tone * envelope * 0.5)
        }
    }

    private static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: frames(seconds))
    }

    private static func frames(_ seconds: Double) -> Int {
        Int((seconds * sampleRate).rounded())
    }

    private static func time(_ index: Int) -> Double {
        Double(index) / sampleRate
    }

    /// A linear ramp in. Starting a tone at full height is a click of its own.
    private static func attack(_ t: Double, _ seconds: Double) -> Double {
        seconds > 0 ? min(1, t / seconds) : 1
    }

    private static func normalize(_ buffer: inout [Float]) {
        guard let loudest = buffer.map({ abs($0) }).max(), loudest > 0 else { return }
        let gain = peak / loudest
        for index in buffer.indices { buffer[index] *= gain }
    }

    private static func release(_ buffer: inout [Float], seconds: Double) {
        let count = min(frames(seconds), buffer.count)
        guard count > 0 else { return }
        for step in 0..<count {
            let index = buffer.count - count + step
            buffer[index] *= Float(1 - Double(step + 1) / Double(count))
        }
    }

    /// A linear congruential generator, so the shutter is the same shutter on
    /// every launch and on every machine.
    private struct SeededNoise {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let bits = UInt32(truncatingIfNeeded: state >> 32)
            return Float(bits) / Float(UInt32.max) * 2 - 1
        }
    }

    /// Canonical 44-byte WAV header, written whole. Short length fields
    /// produce a file that exists and looks plausible but nothing will open.
    public static func wav(_ samples: [Float]) -> Data {
        let bytes = UInt32(samples.count * 2)
        let rate = UInt32(sampleRate)
        var data = Data(capacity: 44 + samples.count * 2)

        data.append(tag("RIFF"))
        data.append(little(36 + bytes))
        data.append(tag("WAVE"))

        data.append(tag("fmt "))
        data.append(little(16 as UInt32))       // chunk length
        data.append(little(1 as UInt16))        // uncompressed PCM
        data.append(little(1 as UInt16))        // one channel
        data.append(little(rate))
        data.append(little(rate * 2))           // bytes per second
        data.append(little(2 as UInt16))        // bytes per sample frame
        data.append(little(16 as UInt16))       // bits per sample

        data.append(tag("data"))
        data.append(little(bytes))
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            data.append(little(UInt16(bitPattern: Int16(clamped * 32_767))))
        }
        return data
    }

    private static func tag(_ text: String) -> Data {
        Data(text.utf8)
    }

    private static func little<T: FixedWidthInteger>(_ value: T) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
