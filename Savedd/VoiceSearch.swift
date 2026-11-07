import SwiftUI
import Speech
import AVFoundation

/// Owns one short dictation session. Late permission/recognition callbacks cannot
/// restart the microphone after dismissal or interfere with a newer session.
@MainActor
final class VoiceSearch: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var isPreparing = false
    @Published private(set) var usesOnDeviceRecognition = false
    @Published private(set) var errorMessage: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var sessionID: UUID?
    private var tapInstalled = false
    private var previousAudioConfiguration: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
    private var timeout: Task<Void, Never>?

    func start(language: String) {
        stop()
        transcript = ""
        usesOnDeviceRecognition = false
        errorMessage = nil
        isPreparing = true
        let id = UUID()
        sessionID = id
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self, self.sessionID == id else { return }
                guard status == .authorized else {
                    self.fail("Speech recognition is unavailable or not allowed. You can enable it in Settings → Privacy & Security → Speech Recognition.")
                    return
                }
                AVAudioApplication.requestRecordPermission { [weak self] allowed in
                    Task { @MainActor in
                        guard let self, self.sessionID == id else { return }
                        guard allowed else {
                            self.fail("Microphone access is off. Enable it in Settings → Savedd, or type your search instead.")
                            return
                        }
                        self.beginRecognition(language: language, id: id)
                    }
                }
            }
        }
    }

    private func beginRecognition(language: String, id: UUID) {
        let locales = SFSpeechRecognizer.supportedLocales()
        let current = Locale.current
        // "Any language" is a search-result filter; dictation still needs a spoken locale.
        let recognitionLanguage = language.isEmpty
            ? (current.language.languageCode?.identifier ?? "en") : language
        let locale = locales.first(where: {
            $0.identifier == current.identifier && $0.language.languageCode?.identifier == recognitionLanguage
        }) ?? locales.sorted(by: { $0.identifier < $1.identifier }).first(where: {
            $0.language.languageCode?.identifier == recognitionLanguage
        })
        guard let locale, let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            fail("Speech recognition isn’t available for your selected language right now. Please try again later or type your search.")
            return
        }
        self.recognizer = recognizer
        let audioSession = AVAudioSession.sharedInstance()
        do {
            previousAudioConfiguration = (audioSession.category, audioSession.mode, audioSession.categoryOptions)
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .search
            usesOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            request.requiresOnDeviceRecognition = usesOnDeviceRecognition
            self.request = request
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                fail("No microphone is available. Please connect a microphone or type your search.")
                return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.sessionID == id else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if result?.isFinal == true {
                        self.stop()
                    } else if error != nil {
                        self.fail(self.transcript.isEmpty
                            ? "Couldn’t hear a search. Try again, check your connection, or type instead."
                            : "Dictation stopped. You can use the words below or try again.")
                    }
                }
            }
            engine.prepare()
            try engine.start()
            isPreparing = false
            isListening = true
            // Bound microphone use even if Apple never returns a final result.
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(55)) } catch { return }
                self?.stop()
            }
        } catch {
            fail("Couldn’t start the microphone. Please try again or type your search.")
        }
    }

    func stop() {
        sessionID = nil
        timeout?.cancel()
        timeout = nil
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        isListening = false
        isPreparing = false
        if let previous = previousAudioConfiguration {
            let audioSession = AVAudioSession.sharedInstance()
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            try? audioSession.setCategory(previous.0, mode: previous.1, options: previous.2)
            previousAudioConfiguration = nil
        }
    }

    private func fail(_ message: String) {
        stop()
        errorMessage = message
    }
}

struct VoiceSearchView: View {
    let language: String
    let onUseText: (String) -> Void
    @StateObject private var voice = VoiceSearch()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: voice.isListening ? "waveform" : "mic.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(SaveddBrand.gold)
                        .frame(height: 80)
                        .accessibilityHidden(true)
                    Text(voice.isPreparing ? "Getting ready…" : (voice.isListening ? "Listening…" : "Voice search"))
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(voice.transcript.isEmpty ? "Say a search or website address." : voice.transcript)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .accessibilityLabel(voice.transcript.isEmpty ? "No words recognized yet" : voice.transcript)
                    if let error = voice.errorMessage {
                        Text(error).font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Text(voice.usesOnDeviceRecognition
                         ? "Speech is processed on this device."
                         : "Uses Apple speech recognition. Audio may be sent to Apple for processing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        if voice.isListening || voice.isPreparing {
                            voice.stop()
                        } else {
                            voice.start(language: language)
                        }
                    } label: {
                        Label(voice.isListening || voice.isPreparing ? "Stop listening" : "Try again",
                              systemImage: voice.isListening || voice.isPreparing ? "stop.fill" : "mic.fill")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    Button("Use text") {
                        let text = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        voice.stop()
                        onUseText(text)
                        dismiss()
                    }
                    .buttonStyle(GoldButtonStyle())
                    .disabled(voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("You can edit the text in the address bar before searching.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
            .navigationTitle("Voice search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { voice.stop(); dismiss() }
                }
            }
            .tint(SaveddBrand.gold)
        }
        .onAppear { voice.start(language: language) }
        .onDisappear { voice.stop() }
        .onChange(of: scenePhase) {
            if scenePhase == .background || (scenePhase == .inactive && voice.isListening) { voice.stop() }
        }
    }
}
