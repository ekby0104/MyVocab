import Foundation
import AVFoundation

@MainActor
final class SpeechService {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()
    /// voice는 한 번만 생성해서 재사용 (매번 만들면 오버헤드)
    private let englishVoice: AVSpeechSynthesisVoice?

    private init() {
        // voice 미리 캐싱
        self.englishVoice = AVSpeechSynthesisVoice(language: "en-US")

        // 오디오 세션 설정
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.mixWithOthers, .duckOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true, options: [])

        // 즉시 워밍업 (0.5초 딜레이 제거)
        // 무음 utterance를 빠르게 처리해서 엔진 초기화
        let warmup = AVSpeechUtterance(string: " ")
        warmup.voice = englishVoice
        warmup.volume = 0
        warmup.rate = 1.0
        synthesizer.speak(warmup)
    }

    /// 영어 단어 또는 문장 발음
    func speak(_ text: String, rate: Float = 0.45) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 이전 발음 즉시 멈추기
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = englishVoice    // 캐싱된 voice 재사용
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        // 시작 전/후 딜레이 0으로 명시
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
