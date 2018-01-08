
import Foundation
import Cocoa

extension NSImage.Name {
    static let StatusIcon = NSImage.Name("StatusIcon")
}

class Status {
    let item: NSStatusItem
    
    init() {
        let bar = NSStatusBar.system
        
        item = bar.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage.init(named: .StatusIcon)!
        icon.isTemplate = true
        icon.size = NSSize.init(width: 18, height: 18)
        
        if let button = item.button {
            // button.title = "Slinger"
            button.image = icon
        }
        
        item.highlightMode = true
        let menu = NSMenu.init()
        let quitItem = NSMenuItem.init(title: "Quit", action: #selector(self.quit(_:)), keyEquivalent: "")
        quitItem.target = self
        quitItem.isEnabled = true
        
        menu.addItem(quitItem)
        item.menu = menu
    }
    
    @objc
    func quit(_: Any) {
        NSRunningApplication.current.terminate()
    }
}
