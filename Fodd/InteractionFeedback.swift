import Foundation
import SwiftUI
import UIKit
import AVFoundation

extension Notification.Name {
    static let foddMomentDidPublish = Notification.Name("foddMomentDidPublish")
}

@MainActor
final class FoddFeedbackManager: ObservableObject {
    static let shared = FoddFeedbackManager()

    enum Sound: String, CaseIterable {
        case send = "fodd_send"
        case receive = "fodd_receive"
        case reaction = "fodd_reaction"
        case success = "fodd_success"
        case checkin = "fodd_checkin"
    }

    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: Self.soundKey) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: Self.hapticsKey) }
    }

    private static let soundKey = "fodd.feedback.soundEnabled"
    private static let hapticsKey = "fodd.feedback.hapticsEnabled"
    private var players: [Sound: AVAudioPlayer] = [:]

    private init() {
        let defaults = UserDefaults.standard
        soundEnabled = defaults.object(forKey: Self.soundKey) == nil ? true : defaults.bool(forKey: Self.soundKey)
        hapticsEnabled = defaults.object(forKey: Self.hapticsKey) == nil ? true : defaults.bool(forKey: Self.hapticsKey)
        prepareAudioSession()
        preloadSounds()
    }

    func tap() {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.62)
    }

    func selection() {
        guard hapticsEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func reaction() {
        if hapticsEnabled { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.85) }
        play(.reaction)
    }

    func messageSent() {
        if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.72) }
        play(.send)
    }

    func messageReceived() {
        if hapticsEnabled { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.65) }
        play(.receive)
    }

    func checkIn() {
        if hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
        play(.checkin)
    }

    func success() {
        if hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        play(.success)
    }

    private func play(_ sound: Sound) {
        guard soundEnabled else { return }
        guard let player = player(for: sound) else { return }
        player.currentTime = 0
        player.play()
    }

    private func player(for sound: Sound) -> AVAudioPlayer? {
        if let existing = players[sound] { return existing }
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") else { return nil }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.42
            player.prepareToPlay()
            players[sound] = player
            return player
        } catch {
            return nil
        }
    }

    private func preloadSounds() {
        Sound.allCases.forEach { _ = player(for: $0) }
    }

    private func prepareAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Sound effects are optional; Fodd continues normally if the session cannot be activated.
        }
    }
}

struct PressScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct FoddToast: View {
    let icon: String
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.14)).frame(width: 38, height: 38)
                Image(systemName: icon).foregroundStyle(.orange).font(.headline)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                if let subtitle, !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 6)
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.primary.opacity(0.06)))
        .shadow(color: Color.black.opacity(0.08), radius: 14, y: 7)
    }
}
