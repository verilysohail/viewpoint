import Foundation
import AVFoundation
import AppKit

class AudioRecorder: NSObject {
    private var audioEngine: AVAudioEngine!
    private var inputNode: AVAudioInputNode!
    private var audioBuffer: AVAudioPCMBuffer?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private let callback: ((Data) -> Void)?

    private var isRecording = false

    init(callback: ((Data) -> Void)? = nil) {
        self.callback = callback
        super.init()
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        // On macOS, AVAudioEngine will automatically trigger the permission dialog
        // when we try to access the input node. We just need to check if it was
        // previously denied.
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            // Request permission explicitly first
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            // Permission was previously denied, need to open System Settings
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    func openSystemSettings() {
        // Open System Settings to Privacy & Security > Microphone
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func startRecording() -> Bool {
        guard !isRecording else { return false }

        do {
            // Create audio engine
            audioEngine = AVAudioEngine()
            inputNode = audioEngine.inputNode

            // Configure audio format (16kHz mono for Whisper)
            let recordingFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            )!

            // Create temporary file URL
            recordingURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("wav")

            // Create audio file
            audioFile = try AVAudioFile(
                forWriting: recordingURL!,
                settings: recordingFormat.settings
            )

            // Install tap on input node
            inputNode.installTap(
                onBus: 0,
                bufferSize: 4096,
                format: inputNode.outputFormat(forBus: 0)
            ) { [weak self] buffer, time in
                guard let self = self, let audioFile = self.audioFile else { return }

                // Convert to recording format if needed
                if let convertedBuffer = self.convert(buffer: buffer, to: recordingFormat) {
                    do {
                        try audioFile.write(from: convertedBuffer)
                    } catch {
                        Logger.shared.error("Error writing audio: \(error)")
                    }
                }
            }

            // Start the engine
            try audioEngine.start()
            isRecording = true

            Logger.shared.info("Recording started")
            return true

        } catch {
            Logger.shared.error("Failed to start recording: \(error)")
            return false
        }
    }

    func stopRecording() -> Data? {
        guard isRecording else { return nil }

        // Stop the engine
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        isRecording = false

        // Close the audio file
        audioFile = nil

        // Read the audio file data
        guard let url = recordingURL else { return nil }

        defer {
            // Clean up temporary file
            try? FileManager.default.removeItem(at: url)
        }

        do {
            let data = try Data(contentsOf: url)
            Logger.shared.info("Recording stopped, audio size: \(data.count) bytes")
            return data
        } catch {
            Logger.shared.error("Failed to read audio file: \(error)")
            return nil
        }
    }

    private func convert(buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            return nil
        }

        let capacity = AVAudioFrameCount(
            Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate
        )

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: capacity
        ) else {
            return nil
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            Logger.shared.error("Conversion error: \(error)")
            return nil
        }

        return convertedBuffer
    }
}
