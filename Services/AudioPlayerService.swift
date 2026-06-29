import Foundation
import AVFoundation
import Combine

// MARK: - 오디오 재생 서비스 (싱글톤)
// Free Dictionary API의 mp3 발음 재생용

@MainActor
final class AudioPlayerService: ObservableObject {
    static let shared = AudioPlayerService()

    @Published private(set) var playingURL: URL?

    private var player: AVPlayer?
    private var playerItemObserver: NSObjectProtocol?

    private init() {}

    var isPlaying: Bool {
        playingURL != nil
    }

    func isPlaying(_ url: URL) -> Bool {
        playingURL == url
    }

    /// URL의 mp3를 재생. 같은 URL을 다시 누르면 중지.
    func play(_ url: URL) {
        // 같은 URL이 재생 중이면 중지
        if playingURL == url {
            stop()
            return
        }

        // 다른 게 재생 중이면 먼저 중지
        stop()

        // 오디오 세션 설정 (벨소리 모드여도 들리도록 .playback)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[AudioPlayer] 오디오 세션 설정 실패: \(error.localizedDescription)")
        }

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        self.player = newPlayer
        self.playingURL = url

        // 재생 완료 감지
        playerItemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }

        newPlayer.play()
        print("[AudioPlayer] 재생 시작: \(url.lastPathComponent)")
    }

    func stop() {
        player?.pause()
        player = nil
        playingURL = nil

        if let observer = playerItemObserver {
            NotificationCenter.default.removeObserver(observer)
            playerItemObserver = nil
        }
    }
}
