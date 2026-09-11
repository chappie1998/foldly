import AppKit

@MainActor
final class FoldSound {
    private let sound: NSSound?

    init(bundle: Bundle = .main) {
        sound = bundle.url(forResource: "fold-finish", withExtension: "wav")
            .flatMap { NSSound(contentsOf: $0, byReference: false) }
        sound?.volume = 0.65
    }

    func play() {
        sound?.stop()
        sound?.play()
    }
}
