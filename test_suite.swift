import Cocoa

print("=== Desktop Scratchpad Verification Suite ===")

let binaryPath = FileManager.default.fileExists(atPath: "./Scratchpad.app/Contents/MacOS/Scratchpad")
    ? "./Scratchpad.app/Contents/MacOS/Scratchpad"
    : (FileManager.default.fileExists(atPath: "./Scratchpad") ? "./Scratchpad" : "./DesktopNotepad")

let shortcutProcess = Process()
shortcutProcess.executableURL = URL(fileURLWithPath: binaryPath)
shortcutProcess.arguments = ["--test-key-equivalents"]
try shortcutProcess.run()
shortcutProcess.waitUntilExit()
guard shortcutProcess.terminationStatus == 0 else {
    fputs("FAIL: ScratchpadTextView key-equivalent checks failed\n", stderr)
    exit(1)
}
print("[1] Command-A/C/V/X/Z/Shift-Z key equivalents passed")

// 2. Launch in background
let process = Process()
process.executableURL = URL(fileURLWithPath: binaryPath)
process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let testStorageURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("DesktopNotepad-\(UUID().uuidString).txt")
process.environment = ProcessInfo.processInfo.environment.merging([
    "DESKTOP_NOTEPAD_STORAGE_PATH": testStorageURL.path
]) { _, testValue in testValue }

func cleanUp() {
    if process.isRunning {
        process.terminate()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }
    try? FileManager.default.removeItem(at: testStorageURL)
}

func fail(_ message: String) -> Never {
    cleanUp()
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

do {
    try process.run()
} catch {
    fail("Could not launch \(binaryPath): \(error)")
}
defer { cleanUp() }

let pid = process.processIdentifier
print("[2] Launched \(binaryPath) (PID: \(pid))")
Thread.sleep(forTimeInterval: 0.25)

var foundWindow = false
var windowLayer: Int = 0
var windowBounds: CGRect = .zero
var isOnscreen = false

let deadline = Date().addingTimeInterval(5)
repeat {
    if let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: AnyObject]] {
        for win in list where (win[kCGWindowOwnerPID as String] as? pid_t) == pid {
            let layer = win[kCGWindowLayer as String] as? Int ?? 0
            if let bounds = win[kCGWindowBounds as String] as? [String: CGFloat],
               let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.width >= 280 {
                foundWindow = true
                windowLayer = layer
                windowBounds = rect
                isOnscreen = (win[kCGWindowIsOnscreen as String] as? Bool) ?? false
                if isOnscreen { break }
            }
        }
    }
    if !isOnscreen { Thread.sleep(forTimeInterval: 0.1) }
} while !isOnscreen && Date() < deadline

guard foundWindow else {
    fail("Window was not found in WindowServer list")
}

print("[3] Found Desktop-Pinned Window: layer = \(windowLayer), bounds = \(windowBounds)")
if windowLayer != -1 { fail("Window layer mismatch: expected -1, got \(windowLayer)") }
if !isOnscreen { fail("WindowServer still reports the scratchpad as offscreen after 5 seconds") }
print("    ✓ Window is renderable below standard application windows")

if !FileManager.default.fileExists(atPath: testStorageURL.path) {
    fail("Scratchpad did not initialize its isolated storage file")
}
print("[4] Isolated storage initialized; ~/.desktop_notes.txt was not used")

cleanUp()
print("[5] Terminated process cleanly")
print("=== ALL SMOKE CHECKS PASSED ===")
