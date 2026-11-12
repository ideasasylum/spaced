import AVFoundation
import SpacedCore

/// Reads speech items aloud with the system voice. Only one tab speaks at a time.
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    struct Handlers {
        /// The block and character range (within that block's plain text) now being spoken.
        let onWord: (Int, Range<Int>?) -> Void
        let onFinish: () -> Void
        /// Another tab took over, or speech was stopped from outside.
        let onInterrupt: () -> Void
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var items: [ObjectIdentifier: SpeechItem] = [:]
    private var lastUtterance: ObjectIdentifier?
    private var handlers: Handlers?
    private weak var owner: AnyObject?

    /// `defaults write dev.spaced.Spaced speechVolume 0.5` turns the voice down without touching system volume.
    private var volume: Float {
        UserDefaults.standard.object(forKey: "speechVolume") == nil ? 1 : UserDefaults.standard.float(forKey: "speechVolume")
    }

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ newItems: [SpeechItem], for newOwner: AnyObject, handlers newHandlers: Handlers) {
        let interrupted = owner === newOwner ? nil : handlers
        reset()
        interrupted?.onInterrupt()
        owner = newOwner
        handlers = newHandlers
        for item in newItems {
            let utterance = AVSpeechUtterance(string: item.text)
            utterance.postUtteranceDelay = 0.15
            utterance.volume = volume
            items[ObjectIdentifier(utterance)] = item
            lastUtterance = ObjectIdentifier(utterance)
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        reset()
    }

    private func reset() {
        handlers = nil
        items = [:]
        lastUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let string = utterance.speechString
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let item = self.items[id] else { return }
                var range: Range<Int>?
                if let offset = item.offsetInBlock, let spoken = Range(characterRange, in: string) {
                    let start = offset + string.distance(from: string.startIndex, to: spoken.lowerBound)
                    range = start..<(start + string.distance(from: spoken.lowerBound, to: spoken.upperBound))
                }
                self.handlers?.onWord(item.block, range)
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard id == self.lastUtterance, let handlers = self.handlers else { return }
                self.handlers = nil
                self.items = [:]
                self.lastUtterance = nil
                handlers.onFinish()
            }
        }
    }
}
