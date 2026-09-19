// Run with swiftc MacManager/Platform/Application/ApplicationLaunchContext.swift
// scripts/test-login-launch.swift -o /tmp/macmanager-login-test && /tmp/macmanager-login-test
import AppKit
import Carbon.HIToolbox

@main
struct LoginLaunchTests {
    static func main() {
        func event(id: AEEventID = AEEventID(kAEOpenApplication)) -> NSAppleEventDescriptor {
            NSAppleEventDescriptor(
                eventClass: AEEventClass(kCoreEventClass), eventID: id,
                targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
                transactionID: AETransactionID(kAnyTransactionID)
            )
        }
        precondition(ApplicationLaunchContextDetector.detect(arguments: [], event: nil) == .manual)
        precondition(ApplicationLaunchContextDetector.detect(arguments: [], event: event()) == .manual)
        let login = event()
        login.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: AEKeyword(keyAEPropData))
        precondition(ApplicationLaunchContextDetector.detect(arguments: [], event: login) == .loginItem)
        let service = event()
        service.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsServiceItem), forKeyword: AEKeyword(keyAEPropData))
        precondition(ApplicationLaunchContextDetector.detect(arguments: [], event: service) == .manual)
        let reopen = event(id: AEEventID(kAEReopenApplication))
        reopen.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: AEKeyword(keyAEPropData))
        precondition(ApplicationLaunchContextDetector.detect(arguments: [], event: reopen) == .manual)
        print("Passed 5 launch-event checks")
    }
}
