import Foundation
import Testing
@testable import KaptureKit

@Suite("SoundCue")
struct SoundCueTests {
    private func rms(_ buffer: [Float], from: Double, to: Double) -> Float {
        let rate = SoundCue.sampleRate
        let start = Int(from * rate), end = min(Int(to * rate), buffer.count)
        guard start < end else { return 0 }
        let total = buffer[start..<end].reduce(Float(0)) { $0 + $1 * $1 }
        return (total / Float(end - start)).squareRoot()
    }

    @Test("every cue runs for the length it advertises", arguments: CaptureCue.allCases)
    func duration(cue: CaptureCue) {
        let expected = Int((SoundCue.duration(of: cue) * SoundCue.sampleRate).rounded())
        #expect(SoundCue.samples(for: cue).count == expected)
    }

    /// One normalization for all three, so nothing clips converting to 16-bit
    /// and the chime does not arrive at twice the shutter's volume.
    @Test("every cue is normalized to the same peak", arguments: CaptureCue.allCases)
    func peak(cue: CaptureCue) {
        let loudest = SoundCue.samples(for: cue).map { abs($0) }.max() ?? 0
        #expect(abs(loudest - SoundCue.peak) < 0.001)
    }

    /// A buffer that stops mid-swing clicks when the player stops it, which
    /// would put a fourth sound in an app that has three.
    @Test("every cue starts and ends in silence", arguments: CaptureCue.allCases)
    func silentEnds(cue: CaptureCue) {
        let buffer = SoundCue.samples(for: cue)
        #expect(abs(buffer[0]) < 0.01)
        #expect(buffer.last == 0)
        let end = SoundCue.duration(of: cue)
        #expect(rms(buffer, from: end - 0.001, to: end) < 0.01)
    }

    /// The one with teeth. This is what fails the day someone reaches for
    /// `Float.random` inside the shutter's noise.
    @Test("a cue is the same bytes every time", arguments: CaptureCue.allCases)
    func deterministic(cue: CaptureCue) {
        #expect(SoundCue.samples(for: cue) == SoundCue.samples(for: cue))
        #expect(SoundCue.wav(for: cue) == SoundCue.wav(for: cue))
    }

    /// A shutter is two clicks. One is a tap on a desk; the gap is what reads
    /// as a camera, so the second burst is asserted rather than assumed.
    @Test("the shutter fires twice, with a gap")
    func shutterHasTwoClicks() {
        let buffer = SoundCue.samples(for: .shutter)
        let gap = rms(buffer, from: 0.040, to: 0.050)
        let second = rms(buffer, from: 0.056, to: 0.066)
        #expect(rms(buffer, from: 0, to: 0.005) > gap)
        #expect(second > gap * 4)
    }

    @Test("the chime is still ringing after the second note enters")
    func chimeHasTwoNotes() {
        let buffer = SoundCue.samples(for: .finished)
        #expect(rms(buffer, from: 0.125, to: 0.145) > rms(buffer, from: 0.100, to: 0.118))
    }

    // MARK: - Container

    /// A header whose lengths are short gives a file that exists, has a
    /// plausible size, and that nothing will open.
    @Test("the WAV header names the format and the real lengths")
    func wavHeader() {
        let samples = SoundCue.samples(for: .tick)
        let data = SoundCue.wav(samples)

        func text(_ range: Range<Int>) -> String { String(decoding: data[range], as: UTF8.self) }
        func length(at offset: Int) -> UInt32 {
            data[offset..<(offset + 4)].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        }

        #expect(text(0..<4) == "RIFF")
        #expect(text(8..<12) == "WAVE")
        #expect(text(12..<16) == "fmt ")
        #expect(text(36..<40) == "data")

        #expect(data.count == 44 + samples.count * 2)
        #expect(length(at: 4) == UInt32(data.count - 8))
        #expect(length(at: 40) == UInt32(samples.count * 2))
        #expect(length(at: 24) == UInt32(SoundCue.sampleRate))
    }

    @Test("samples are written 16-bit little-endian")
    func wavSamples() {
        let data = SoundCue.wav([0, 1, -1])
        #expect(data.count == 50)
        #expect(Array(data[44..<50]) == [0x00, 0x00, 0xFF, 0x7F, 0x01, 0x80])
    }
}
