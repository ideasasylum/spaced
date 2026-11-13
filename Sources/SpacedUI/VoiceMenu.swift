import AppKit
import AVFoundation

/// Which system voice reads aloud. macOS hands apps the basic voice for the user's language by default
/// and doesn't expose the System Voice setting, so Spaced picks the best installed voice itself.
@MainActor
enum Voices {
    private static let key = "speechVoice"

    /// Installed voices in the user's language (any region), best quality first.
    static var available: [AVSpeechSynthesisVoice] {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let base = language.split(separator: "-").first.map(String.init) ?? language
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(base) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { first, second in
                if first.quality != second.quality { return first.quality.rawValue > second.quality.rawValue }
                let firstLocal = first.language == language, secondLocal = second.language == language
                if firstLocal != secondLocal { return firstLocal }
                return first.name < second.name
            }
    }

    static var chosenIdentifier: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// The voice to speak with: the user's choice if it is still installed, otherwise the best available.
    static var current: AVSpeechSynthesisVoice? {
        if let identifier = chosenIdentifier, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        return available.first
    }
}

/// Fills the Voice submenu each time it opens, so newly downloaded voices appear without a restart.
@MainActor
final class VoiceMenu: NSObject, NSMenuDelegate {
    static let shared = VoiceMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let voices = Voices.available
        let best = NSMenuItem(title: "Best Available" + (voices.first.map { " (\($0.name))" } ?? ""),
                              action: #selector(choose(_:)), keyEquivalent: "")
        best.target = self
        best.state = Voices.chosenIdentifier == nil ? .on : .off
        menu.addItem(best)
        menu.addItem(.separator())
        for voice in voices {
            let region = Locale.current.localizedString(forRegionCode: String(voice.language.suffix(2))) ?? voice.language
            let item = NSMenuItem(title: "\(voice.name), \(region)", action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = voice.identifier
            item.state = Voices.chosenIdentifier == voice.identifier ? .on : .off
            menu.addItem(item)
        }
    }

    @objc private func choose(_ sender: NSMenuItem) {
        Voices.chosenIdentifier = sender.representedObject as? String
    }
}
