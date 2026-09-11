import AppKit
import Darwin

@main
enum BendyMain {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--diagnose") {
            let reading = LidAngleSensor().diagnose()
            if let angle = reading.angle {
                print("Foldly lid sensor available: \(Int(angle))°")
                print(reading.detail)
                exit(EXIT_SUCCESS)
            }
            fputs("Foldly lid sensor unavailable: \(reading.detail)\n", stderr)
            exit(EXIT_FAILURE)
        }
        if arguments.contains("--self-test") { exit(BendySelfTest.run() ? EXIT_SUCCESS : EXIT_FAILURE) }

        let application = NSApplication.shared
        let coordinator = AppCoordinator()
        application.delegate = coordinator
        application.run()
    }
}
