import AVFoundation
import Foundation

/// Helpers for turning AVAudioEngine input buffers into the mono Int16 PCM
/// frames that Eagle's profiler / recognizer expect.
///
/// Eagle requires:
///  - mono
///  - 16-bit signed PCM
///  - sample rate == `Eagle.sampleRate` (16 kHz at the time of writing)
///
/// AVAudioEngine's input node usually produces Float32 PCM at the device's
/// hardware sample rate (often 44.1 / 48 kHz), so we need to mix-down to
/// mono, resample, and convert.
enum PCMConverter {

    /// Resamples (if necessary) and converts an AVAudioPCMBuffer to mono Int16
    /// samples at `targetSampleRate`. The conversion uses AVAudioConverter
    /// for best quality and avoids hand-rolled DSP.
    static func convertToMonoInt16(
        buffer: AVAudioPCMBuffer,
        targetSampleRate: Double
    ) -> [Int16]? {
        guard let inputFormat = buffer.format as AVAudioFormat? else { return nil }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            return nil
        }

        // Fast path: same rate, mono, already Int16.
        if inputFormat.sampleRate == targetSampleRate,
           inputFormat.channelCount == 1,
           inputFormat.commonFormat == .pcmFormatInt16,
           let int16Data = buffer.int16ChannelData {
            let count = Int(buffer.frameLength)
            let pointer = int16Data[0]
            return Array(UnsafeBufferPointer(start: pointer, count: count))
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return nil
        }

        // Estimate output capacity based on sample-rate ratio. Add a small
        // pad to absorb rounding.
        let ratio = targetSampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputCapacity
        ) else {
            return nil
        }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil,
              let int16Data = outputBuffer.int16ChannelData else {
            return nil
        }

        let frameCount = Int(outputBuffer.frameLength)
        guard frameCount > 0 else { return [] }

        let pointer = int16Data[0]
        return Array(UnsafeBufferPointer(start: pointer, count: frameCount))
    }

    /// Convenience: clamp + scale a single Float sample to Int16. Kept here
    /// in case callers need to bypass AVAudioConverter.
    static func floatToInt16(_ value: Float) -> Int16 {
        let clamped = max(-1.0, min(1.0, value))
        let scaled = clamped * Float(Int16.max)
        return Int16(scaled)
    }
}
