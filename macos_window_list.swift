// Lists on-screen windows as JSON so a caller can find a Unity Player's CGWindowID and hand it
// to `screencapture -l<id>`, which captures that one window instead of the whole display.
//
// Why this exists rather than a Python/Quartz equivalent: pyobjc is not installed on this
// machine, and `swiftc` ships with the Xcode toolchain the iOS builds already require. Compiling
// it costs ~1s and is cached.
//
// Windows are matched by owner PID, never by title. `kCGWindowName` is withheld unless the
// caller holds Screen Recording permission, so a title-based match would break exactly on the
// machines where the permission has not been granted yet — while the PID is always readable.
//
// Usage:
//   window-list                 all windows
//   window-list --pid 1234      only windows owned by that process
//   window-list --pid 1234 --largest   the biggest such window (the Player's game window, not
//                                      its status/dialog windows), as a single object

import CoreGraphics
import Foundation

struct WindowInfo: Encodable {
    let windowId: UInt32
    let ownerPid: Int32
    let ownerName: String?
    let title: String?
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let layer: Int
    let onScreen: Bool
    var area: Int { width * height }
}

func parseArgs() -> (pid: Int32?, largest: Bool) {
    var pid: Int32?
    var largest = false
    var index = 1
    let args = CommandLine.arguments
    while index < args.count {
        switch args[index] {
        case "--pid":
            index += 1
            if index < args.count { pid = Int32(args[index]) }
        case "--largest":
            largest = true
        default:
            break
        }
        index += 1
    }
    return (pid, largest)
}

let (filterPid, wantLargest) = parseArgs()

// .optionAll rather than .optionOnScreenOnly: a Player window that is behind another window is
// still a valid capture target, and excluding it would make captures fail intermittently
// depending on what the developer happened to have in front.
guard let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] else {
    FileHandle.standardError.write("could not read the window list\n".data(using: .utf8)!)
    exit(2)
}

var windows: [WindowInfo] = []
for entry in raw {
    guard let windowId = entry[kCGWindowNumber as String] as? UInt32,
          let ownerPid = entry[kCGWindowOwnerPID as String] as? Int32,
          let bounds = entry[kCGWindowBounds as String] as? [String: Any] else { continue }

    if let filterPid, ownerPid != filterPid { continue }

    let layer = entry[kCGWindowLayer as String] as? Int ?? 0
    // Layer 0 is the normal application layer. Anything above it is a panel, menu or overlay,
    // never the game window we want to photograph.
    if layer != 0 { continue }

    let width = Int(bounds["Width"] as? Double ?? 0)
    let height = Int(bounds["Height"] as? Double ?? 0)
    if width <= 1 || height <= 1 { continue }

    windows.append(WindowInfo(
        windowId: windowId,
        ownerPid: ownerPid,
        ownerName: entry[kCGWindowOwnerName as String] as? String,
        title: entry[kCGWindowName as String] as? String,
        x: Int(bounds["X"] as? Double ?? 0),
        y: Int(bounds["Y"] as? Double ?? 0),
        width: width,
        height: height,
        layer: layer,
        onScreen: entry[kCGWindowIsOnscreen as String] as? Bool ?? false
    ))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

if wantLargest {
    guard let biggest = windows.max(by: { $0.area < $1.area }) else {
        FileHandle.standardError.write("no matching window\n".data(using: .utf8)!)
        exit(1)
    }
    print(String(data: try encoder.encode(biggest), encoding: .utf8)!)
} else {
    print(String(data: try encoder.encode(windows.sorted { $0.area > $1.area }), encoding: .utf8)!)
}
