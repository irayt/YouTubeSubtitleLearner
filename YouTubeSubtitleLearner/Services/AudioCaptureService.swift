import Foundation
import ReplayKit
import AVFoundation

final class AudioCaptureService: NSObject {
    private var writer: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var isWriting = false
    private var didReceiveAudio = false

    func start() throws {
        let rec = RPScreenRecorder.shared()
        guard rec.isAvailable else { throw NSError(domain: "AudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "ReplayKit not available"]) }

        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        outputURL = out
        writer = try AVAssetWriter(outputURL: out, fileType: .m4a)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128_000
        ]
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        audioInput?.expectsMediaDataInRealTime = true
        if let input = audioInput, writer?.canAdd(input) == true { writer?.add(input) }
        isWriting = false
        didReceiveAudio = false

        rec.isMicrophoneEnabled = false
        rec.startCapture(handler: { [weak self] (sample, type, error) in
            guard error == nil else { return }
            // 一部OSでは .audioMic に混ざることがあるため両方受け付ける
            guard type == .audioApp || type == .audioMic else { return }
            self?.append(sample: sample)
        }, completionHandler: { err in })
    }

    private func append(sample: CMSampleBuffer) {
        guard let writer = writer, let input = audioInput else { return }
        if writer.status == .failed { return }
        if !isWriting {
            if writer.startWriting() {
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sample))
                isWriting = true
            }
        }
        if input.isReadyForMoreMediaData {
            input.append(sample)
            didReceiveAudio = true
        }
    }

    func stop() async throws -> URL {
        let rec = RPScreenRecorder.shared()
        // stopCapture は非同期コールバック。完了を待つ
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            rec.stopCapture { error in
                if let e = error { cont.resume(throwing: e) }
                else { cont.resume() }
            }
        }

        guard let writer = writer, let input = audioInput, let out = outputURL else {
            throw NSError(domain: "AudioCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "no writer"])
        }
        if writer.status == .writing {
            input.markAsFinished()
            await withCheckedContinuation { cont in
                writer.finishWriting { cont.resume() }
            }
        } else {
            // 収録が始まっていない（サンプル未受信）。呼び出し側で扱いやすいエラーを返す
            writer.cancelWriting()
            self.writer = nil; self.audioInput = nil
            throw NSError(domain: "AudioCapture", code: 3, userInfo: [NSLocalizedDescriptionKey: "音声が取得できませんでした。動画を再生してから停止してください。"])
        }
        self.writer = nil; self.audioInput = nil
        return out
    }
}
