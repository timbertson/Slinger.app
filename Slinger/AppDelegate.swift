import Cocoa
import ApplicationServices
import MASShortcut
import AXSwift

class ApplicationDelegate: NSObject, NSApplicationDelegate {
    
    private var status: Status?
    
    func applicationWillTerminate(_ notification: Notification) {
        status = nil
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Check that we have permission
        guard UIElement.isProcessTrusted(withPrompt: true) else {
            NSLog("No accessibility API permission, exiting")
            NSRunningApplication.current.terminate()
            return
        }
        
        let dispatchQueue = DispatchQueue.global(qos: .userInteractive)
        
        let slinger = try! Slinger.init(dispatchQueue: dispatchQueue)
        
        let keycodeMap = Keybinding.constructKeyCodeMap()
        MASShortcutValidator.shared().allowAnyShortcutWithOptionModifier = true
        
        let status = Status.init(dispatchQueue: dispatchQueue)
        
        func bind(_ pref: String, key: String, modifiers: NSEvent.ModifierFlags, slow: Bool, fn: @escaping (() -> ())) {
            let prefKey = "shortcut-\(pref)"
            if let keycodes = keycodeMap[key], !keycodes.isEmpty {
                let shortcut = MASShortcut(keyCode: UInt(keycodes[0]), modifierFlags: modifiers.rawValue)
                MASShortcutBinder.shared().registerDefaultShortcuts([ prefKey: shortcut as Any ])
                var action = fn
                if slow {
                    action = { () in status.asyncWithBusyIndicator(fn) }
                }
                MASShortcutBinder.shared().bindShortcut(withDefaultsKey: prefKey, toAction: action)
            }
        }
        
        func bind(action: String, key: String, modifiers: NSEvent.ModifierFlags, slow: Bool) {
            bind(action, key: key, modifiers: modifiers, slow: slow) { slinger.action(action) }
        }
        
        func bind(_ pref: String, key: String, modifiers: NSEvent.ModifierFlags, action: String, arguments: [Any], slow: Bool) {
            bind(pref, key: key, modifiers: modifiers, slow: slow) { slinger.action(action, arguments: arguments) }
        }

        bind("show", key: "a", modifiers: [.option], slow: false) { slinger.show(self) }
        bind("nextWindow", key: "j", modifiers: [.command], action: "selectWindow", arguments: [1], slow: true)
        bind("prevWindow", key: "k", modifiers: [.command], action: "selectWindow", arguments: [-1], slow: true)
        
        bind("swapNextWindow", key: "j", modifiers: [.command, .shift], action: "swapWindow", arguments: [1], slow: true)
        bind("swapPrevWindow", key: "k", modifiers: [.command, .shift], action: "swapWindow", arguments: [-1], slow: true)
        
        bind("moveRight", key: "l", modifiers: [.option], action: "moveAction", arguments: [1, "x"], slow: false)
        bind("moveLeft", key: "h", modifiers: [.option], action: "moveAction", arguments: [-1, "x"], slow: false)
        bind("moveUp", key: "i", modifiers: [.option], action: "moveAction", arguments: [-1, "y"], slow: false)
        bind("moveDown", key: "u", modifiers: [.option], action: "moveAction", arguments: [1, "y"], slow: false)

        bind("growHorizontal", key: "l", modifiers: [.option, .shift], action: "resizeAction", arguments: [1, "x"], slow: false)
        bind("shrinkHorizontal", key: "h", modifiers: [.option, .shift], action: "resizeAction", arguments: [-1, "x"], slow: false)
        bind("growVertical", key: "u", modifiers: [.option, .shift], action: "resizeAction", arguments: [1, "y"], slow: false)
        bind("shrinkVertical", key: "i", modifiers: [.option, .shift], action: "resizeAction", arguments: [-1, "y"], slow: false)
        
        bind("grow", key: "=", modifiers: [.option], action: "resizeAction", arguments: [1, NSNull.init()], slow: false)
        bind("shrink", key: "-", modifiers: [.option], action: "resizeAction", arguments: [-1, NSNull.init()], slow: false)

        /*
        Not implemented on OSX:
        (requires private APIs and a CGWindowID, which itself requires private APIs to get)
 
        bind("switchWorkspaceLeft", key: "-", modifiers: [.option, .command], action: "switchWorkspace", arguments: [-1])
        bind("switchWorkspaceRight", key: "-", modifiers: [.option, .command], action: "switchWorkspace", arguments: [1])
        
        bind("moveWindowWorkspaceLeft", key: "-", modifiers: [.option, .command, .shift], action: "moveWindowWorkspace", arguments: [-1])
        bind("moveWindowWorkspaceRight", key: "-", modifiers: [.option, .command, .shift], action: "moveWindowWorkspace", arguments: [1])
        */
        
        bind(action: "toggleMaximize", key: "z", modifiers: [.option], slow: false)
        bind(action: "minimize", key: "x", modifiers: [.option], slow: false)
        bind(action: "unminimize", key: "x", modifiers: [.option, .shift], slow: false)
        
        bind(action: "distribute", key: "8", modifiers: [.option, .shift], slow: true)

        NSLog("Slinger initialized")
        status.ready()
        self.status = status
    }
}
