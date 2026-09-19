import AppKit
import Carbon.HIToolbox

enum ApplicationLaunchContext: Equatable {
    case manual
    case loginItem
}

enum ApplicationLaunchContextDetector {
    static func detect(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        event: NSAppleEventDescriptor? = NSAppleEventManager.shared().currentAppleEvent
    ) -> ApplicationLaunchContext {
        #if DEBUG
        if arguments.contains("--launched-at-login") {
            return .loginItem
        }
        #endif

        guard let event,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication),
              event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == keyAELaunchedAsLogInItem else {
            return .manual
        }
        return .loginItem
    }
}
