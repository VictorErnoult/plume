import AVFoundation
import FluidAudio
import Foundation

public enum AudioIO {
    /// Charge n'importe quel fichier audio (wav, m4a, mp3, caf…) en mono 16 kHz.
    public static func loadSamples(_ url: URL) throws -> [Float] {
        try AudioConverter().resampleAudioFile(url)
    }

    /// Encode des échantillons mono 16 kHz en AAC (.m4a), ~14 Mo par heure.
    public static func writeM4A(_ samples: [Float], to url: URL) throws {
        let sampleRate = Double(SpeechEngine.sampleRate)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(
            forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = 16_000 * 10
        var offset = 0
        while offset < samples.count {
            let n = min(chunk, samples.count - offset)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else {
                throw CocoaError(.fileWriteUnknown)
            }
            buffer.frameLength = AVAudioFrameCount(n)
            samples.withUnsafeBufferPointer { source in
                buffer.floatChannelData![0].update(from: source.baseAddress! + offset, count: n)
            }
            try file.write(from: buffer)
            offset += n
        }
    }
}

/// Écrit un WAV mono 16 bits au fil de l'eau : en cas de plantage pendant une longue
/// réunion, l'audio déjà capté reste lisible (l'en-tête est remis à jour régulièrement).
public final class WavWriter: @unchecked Sendable {
    public let url: URL
    private let handle: FileHandle
    private let queue = DispatchQueue(label: "plume.wav-writer")
    private var dataBytes: UInt32 = 0
    private var bytesSinceHeader: UInt32 = 0
    private var closed = false
    private let sampleRate: UInt32

    public init(url: URL, sampleRate: Int = SpeechEngine.sampleRate) throws {
        self.url = url
        self.sampleRate = UInt32(sampleRate)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: header(dataBytes: 0))
    }

    private func header(dataBytes: UInt32) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataBytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))  // PCM
        append(UInt16(1))  // mono
        append(sampleRate)
        append(sampleRate * 2)
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(dataBytes)
        return data
    }

    public func append(_ samples: [Float]) {
        queue.async { [self] in
            // Un dernier tampon peut arriver après la fermeture : on l'ignore.
            guard !closed else { return }
            var pcm = [Int16](repeating: 0, count: samples.count)
            for i in 0..<samples.count {
                pcm[i] = Int16(max(-1, min(1, samples[i])) * 32767)
            }
            let data = pcm.withUnsafeBufferPointer { Data(buffer: $0) }
            guard (try? handle.write(contentsOf: data)) != nil else { return }
            dataBytes += UInt32(data.count)
            bytesSinceHeader += UInt32(data.count)
            // Toutes les ~5 s d'audio, on rend le fichier valide jusqu'ici.
            if bytesSinceHeader > sampleRate * 2 * 5 {
                patchHeader()
            }
        }
    }

    private func patchHeader() {
        bytesSinceHeader = 0
        guard let end = try? handle.offset() else { return }
        try? handle.seek(toOffset: 0)
        try? handle.write(contentsOf: header(dataBytes: dataBytes))
        try? handle.seek(toOffset: end)
    }

    public func close() {
        queue.sync {
            guard !closed else { return }
            patchHeader()
            try? handle.close()
            closed = true
        }
    }
}
