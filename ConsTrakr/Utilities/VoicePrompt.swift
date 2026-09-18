//
//  VoicePrompt.swift
//  ConsTrakr
//

import AVFoundation
import Foundation

@MainActor
final class VoicePrompt {
    static let shared = VoicePrompt()

    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpoken: String?

    func speakScanner(_ text: String) {
        speak(text, force: true)
    }

    func speakEnrollment(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isEnrollmentSilent(trimmed) else { return }
        speak(trimmed, force: false)
    }

    func resetSpeech() {
        lastSpoken = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func speak(_ text: String, force: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !force, trimmed == lastSpoken { return }
        lastSpoken = trimmed

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        synthesizer.stopSpeaking(at: .word)
        synthesizer.speak(utterance)
    }

    private func isEnrollmentSilent(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("uploading")
            || lower.contains("saving employee")
            || lower.contains("adjust your face")
    }
}
