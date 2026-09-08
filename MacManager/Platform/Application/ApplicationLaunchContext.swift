import AppKit
import Carbon.HIToolbox

enum ApplicationLaunchContext: Equatable {
    case manual
    case loginItem
}

enum ApplicationLaunchContextDetector {
    static func detect(arguments: [String] = ProcessInfo.processInfo.arguments) -> ApplicationLaunchContext {
        #if DEBUG
        if arguments.contains("--launched-at-login") {
            return .loginItem
        }
        #endif

        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication),
              event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil else {
            return .manual
        }
        return .loginItem
    }
}
