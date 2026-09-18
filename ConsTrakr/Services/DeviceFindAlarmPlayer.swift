//
//  DeviceFindAlarmPlayer.swift
//  ConsTrakr
//

import AVFoundation
import Foundation

@MainActor
final class DeviceFindAlarmPlayer {
    static let shared = DeviceFindAlarmPlayer()

    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    func playFor(seconds: TimeInterval = 12) {
        stop()
        guard let url = Bundle.main.url(forResource: "find_device_buzzer", withExtension: "mp3") else {
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.numberOfLoops = -1
            audio.volume = 1
            audio.prepareToPlay()
            audio.play()
            player = audio
            stopTask = Task {
                try? await Task.sleep(for: .seconds(seconds))
                stop()
            }
        } catch {
            player = nil
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
