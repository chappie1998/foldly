import Foundation

// Original Foldly sound: a short airy gesture resolving into a soft glass chord.
// Offline generator; the app plays the bundled WAV without synthesizing at runtime.
let sampleRate = 48_000
let duration = 0.76
let count = Int(Double(sampleRate) * duration)
var left = [Double](repeating: 0, count: count)
var right = left
var noiseState: UInt64 = 0x464f4c444c59
var smoothNoise = 0.0
var slowNoise = 0.0

func tone(_ time: Double, frequency: Double, decay: Double) -> Double {
    guard time >= 0 else { return 0 }
    let envelope = (1 - exp(-time / 0.0035)) * exp(-time / decay)
    let phase = 2 * Double.pi * frequency * time
    let shimmer = 0.20 * exp(-time / 0.07) * sin(phase * 2.76)
    return envelope * (sin(phase + shimmer) + 0.10 * sin(phase * 2.01) + 0.025 * sin(phase * 4.09))
}

let notes: [(time: Double, frequency: Double, amplitude: Double, pan: Double)] = [
    (0.035, 783.99, 0.24, -0.22),
    (0.075, 1174.66, 0.16, 0.18),
    (0.115, 1567.98, 0.07, 0.30)
]
for i in 0..<count {
    let t = Double(i) / Double(sampleRate)
    noiseState = noiseState &* 6364136223846793005 &+ 1442695040888963407
    let noise = Double(noiseState >> 11) / Double(UInt64.max >> 11) * 2 - 1
    smoothNoise += 0.13 * (noise - smoothNoise)
    slowNoise += 0.018 * (noise - slowNoise)
    let air = (smoothNoise - slowNoise) * exp(-pow((t - 0.06) / 0.055, 2)) * 0.20
    let bodyEnvelope = (1 - exp(-t / 0.004)) * exp(-t / 0.035)
    let bodyPhase = 2 * Double.pi * (100 * t + 65 * 0.025 * (1 - exp(-t / 0.025)))
    let body = 0.18 * sin(bodyPhase) * bodyEnvelope
    left[i] = air + body
    right[i] = air + body
    for note in notes {
        let value = note.amplitude * tone(t - note.time, frequency: note.frequency, decay: 0.12)
        left[i] += value * sqrt((1 - note.pan) / 2)
        right[i] += value * sqrt((1 + note.pan) / 2)
        // A tiny, filtered stereo reflection gives space without a long alert tail.
        left[i] += note.amplitude * 0.10 * tone(t - note.time - 0.053, frequency: note.frequency, decay: 0.10)
        right[i] += note.amplitude * 0.10 * tone(t - note.time - 0.071, frequency: note.frequency, decay: 0.10)
    }
    let fade = min(1, max(0, (duration - t) / 0.10))
    let tail = 0.5 - 0.5 * cos(Double.pi * fade)
    left[i] *= tail; right[i] *= tail
}
let peak = max(left.map(abs).max()!, right.map(abs).max()!)
let gain = 0.48 / max(peak, 0.0001)
var output = Data()
func ascii(_ value: String) { output.append(contentsOf: value.utf8) }
func uint16(_ value: UInt16) { output.append(UInt8(value & 255)); output.append(UInt8(value >> 8)) }
func uint32(_ value: UInt32) { uint16(UInt16(value & 65535)); uint16(UInt16(value >> 16)) }
let payloadBytes = UInt32(count * 4)
ascii("RIFF"); uint32(36 + payloadBytes); ascii("WAVEfmt "); uint32(16)
uint16(1); uint16(2); uint32(UInt32(sampleRate)); uint32(UInt32(sampleRate * 4)); uint16(4); uint16(16)
ascii("data"); uint32(payloadBytes)
for i in 0..<count {
    for sample in [left[i], right[i]] {
        let pcm = Int16((max(-1, min(1, sample * gain)) * 32767).rounded())
        uint16(UInt16(bitPattern: pcm))
    }
}
guard CommandLine.arguments.count == 2 else { fatalError("Usage: GenerateFoldSound <output.wav>") }
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
try output.write(to: destination, options: .atomic)
print("Created original Foldly finish: \(duration)s, stereo 48 kHz, peak −6.4 dBFS")
