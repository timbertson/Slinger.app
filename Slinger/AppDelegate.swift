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
        
        let slinger = try! Slinger.init()
        
        let keycodeMap = Keybinding.constructKeyCodeMap()
        MASShortcutValidator.shared().allowAnyShortcutWithOptionModifier = true
        
        func bind(_ pref: String, key: String, modifiers: NSEvent.ModifierFlags, fn: @escaping (() -> ())) {
            let prefKey = "shortcut-\(pref)"
            if let keycodes = keycodeMap[key], !keycodes.isEmpty {
                let shortcut = MASShortcut(keyCode: UInt(keycodes[0]), modifierFlags: modifiers.rawValue)
                MASShortcutBinder.shared().registerDefaultShortcuts([ prefKey: shortcut as Any ])
                MASShortcutBinder.shared().bindShortcut(withDefaultsKey: prefKey, toAction: fn)
            }
        }
        
        func bind(action: String, key: String, modifiers: NSEvent.ModifierFlags) {
            bind(action, key: key, modifiers: modifiers) { slinger.action(action) }
        }
        
        func bind(_ pref: String, key: String, modifiers: NSEvent.ModifierFlags, action: String, arguments: [Any]) {
            bind(pref, key: key, modifiers: modifiers) { slinger.action(action, arguments: arguments) }
        }

        bind("show", key: "a", modifiers: [.option]) { slinger.show(self) }
        bind("nextWindow", key: "j", modifiers: [.command], action: "selectWindow", arguments: [1])
        bind("prevWindow", key: "k", modifiers: [.command], action: "selectWindow", arguments: [-1])
        
        bind("swapNextWindow", key: "j", modifiers: [.command, .shift], action: "swapWindow", arguments: [1])
        bind("swapPrevWindow", key: "k", modifiers: [.command, .shift], action: "swapWindow", arguments: [-1])
        
        bind("moveRight", key: "l", modifiers: [.option], action: "moveAction", arguments: [1, "x"])
        bind("moveLeft", key: "h", modifiers: [.option], action: "moveAction", arguments: [-1, "x"])
        bind("moveUp", key: "i", modifiers: [.option], action: "moveAction", arguments: [-1, "y"])
        bind("moveDown", key: "u", modifiers: [.option], action: "moveAction", arguments: [1, "y"])

        bind("growHorizontal", key: "l", modifiers: [.option, .shift], action: "resizeAction", arguments: [1, "x"])
        bind("shrinkHorizontal", key: "h", modifiers: [.option, .shift], action: "resizeAction", arguments: [-1, "x"])
        bind("growVertical", key: "i", modifiers: [.option, .shift], action: "resizeAction", arguments: [-1, "y"])
        bind("shrinkVertical", key: "u", modifiers: [.option, .shift], action: "resizeAction", arguments: [1, "y"])
        
        bind("grow", key: "=", modifiers: [.option], action: "resizeAction", arguments: [1, NSNull.init()])
        bind("shrink", key: "-", modifiers: [.option], action: "resizeAction", arguments: [-1, NSNull.init()])

        /*
        Not implemented on OSX:
        (requires private APIs and a CGWindowID, which itself requires private APIs to get)
 
        bind("switchWorkspaceLeft", key: "-", modifiers: [.option, .command], action: "switchWorkspace", arguments: [-1])
        bind("switchWorkspaceRight", key: "-", modifiers: [.option, .command], action: "switchWorkspace", arguments: [1])
        
        bind("moveWindowWorkspaceLeft", key: "-", modifiers: [.option, .command, .shift], action: "moveWindowWorkspace", arguments: [-1])
        bind("moveWindowWorkspaceRight", key: "-", modifiers: [.option, .command, .shift], action: "moveWindowWorkspace", arguments: [1])
        */
        
        bind(action: "toggleMaximize", key: "z", modifiers: [.option])
        bind(action: "minimize", key: "x", modifiers: [.option])
        bind(action: "unminimize", key: "x", modifiers: [.option, .shift])
        
        bind(action: "distribute", key: "8", modifiers: [.option, .shift])
        
        status = Status.init()
        
        NSLog("Slinger initialized")
    }
}
