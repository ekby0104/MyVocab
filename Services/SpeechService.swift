import Foundation
import AVFoundation

@MainActor
final class SpeechService {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        
        // 음성 엔진 워밍업 (첫 호출 지연 방지)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let warmup = AVSpeechUtterance(string: " ")
            warmup.voice = AVSpeechSynthesisVoice(language: "en-US")
            warmup.volume = 0
            self.synthesizer.speak(warmup)
        }
    }

    /// 영어 단어 또는 문장 발음
    func speak(_ text: String, rate: Float = 0.45) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // 이전 발음 멈추기
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = rate              // 0.0 ~ 1.0 (기본 0.5)
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
