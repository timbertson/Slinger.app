import Cocoa
import ApplicationServices

import MASShortcut
import AXSwift

class ApplicationDelegate: NSObject, NSApplicationDelegate {
    
    private var status: Status?
    
    func applicationWillTerminate(_ notification: Notification) {
        status = nil
    }
    
    private func run() {
      let dispatchQueue = DispatchQueue.global(qos: .userInteractive)
      
      let slinger = try! Slinger.init(dispatchQueue: dispatchQueue)
      
      let keycodeMap = Keybinding.constructKeyCodeMap()
      MASShortcutValidator.shared().allowAnyShortcutWithOptionModifier = true
      
      let status = Status.init(dispatchQueue: dispatchQueue)
      
      let binder = MASShortcutBinder.shared()!
      
      func bind(_ pref: String, key: String, modifiers: NSEvent.ModifierFlags, slow: Bool, fn: @escaping (() -> ())) {
          // Compiler treats swift String and NSString identically, but using a swift string causes a segfault(!)
          // https://stackoverflow.com/questions/24208594/swift-string-manipulation-causing-exc-bad-access
          let prefKey = NSString.init(string: "shortcut-\(pref)")
          if let keycodes = keycodeMap[key], !keycodes.isEmpty {
              let shortcut = MASShortcut(keyCode: Int(keycodes[0]), modifierFlags: modifiers)
              binder.registerDefaultShortcuts([ prefKey: shortcut ])
              var action = fn
              if slow {
                  action = { () in status.asyncWithBusyIndicator(fn) }
              }
              binder.bindShortcut(withDefaultsKey: prefKey as String, toAction: action)
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
      
      // bind("swapNextWindow", key: "j", modifiers: [.command, .shift], action: "swapWindow", arguments: [1], slow: true)
      // bind("swapPrevWindow", key: "k", modifiers: [.command, .shift], action: "swapWindow", arguments: [-1], slow: true)
      
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
      bind(action: "fillAvailableSpace", key: "8", modifiers: [.option], slow: true)

      NSLog("Slinger initialized")
      status.ready()
      self.status = status
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
      if UIElement.isProcessTrusted(withPrompt: true) {
        NSLog("Accessibility API already granted, launching")
        self.run()
      } else {
        NSLog("No accessibility API permission, waiting ...")
        let notificationCenter = DistributedNotificationCenter.default()
        var observer: Any? = nil
        observer = notificationCenter.addObserver(forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: nil) { _ in
          NSLog("accessibility API permissions changed re-checking...")
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if UIElement.isProcessTrusted(withPrompt: false) {
              NSLog("Accessibility API permission granted, starting up")
              notificationCenter.removeObserver(observer!)
              self.run()
            } else {
              NSLog("Still no access, waiting...")
            }
          }
        }
        return
      }
    }
}
