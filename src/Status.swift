
import Foundation
import Cocoa

class Status {
    let item: NSStatusItem
    let button: NSButton
    let standardIcon: NSImage
    let busyIcon: NSImage
    private var busyCount: Int = 0
    private let dispatchQueue: DispatchQueue
    
    init(dispatchQueue: DispatchQueue) {
        self.dispatchQueue = dispatchQueue
        let bar = NSStatusBar.system
        
        item = bar.statusItem(withLength: NSStatusItem.squareLength)
        
        func makeIcon(_ name: String) -> NSImage {
            let bundle = Bundle.main
            let path = bundle.path(forResource: "Slinger_Slinger.bundle/\(name)", ofType: "png")
            if path == nil {
                fatalError("Couldn't find image `\(name)`")
            }

            let iconOpt = NSImage.init(contentsOfFile: path!)
            if iconOpt == nil {
                fatalError("Couldn't load image `\(name)`")
            }
            let icon = iconOpt!
            icon.isTemplate = true
            icon.size = NSSize.init(width: 18, height: 18)
            return icon
        }
        
        standardIcon = makeIcon("icon")
        busyIcon = makeIcon("icon-fade")
        
        button = item.button!
        button.image = busyIcon
        
        item.highlightMode = true
        let menu = NSMenu.init()
        let quitItem = NSMenuItem.init(title: "Quit", action: #selector(self.quit(_:)), keyEquivalent: "")
        quitItem.target = self
        quitItem.isEnabled = true
        
        menu.addItem(quitItem)
        item.menu = menu
    }
    
    func ready() {
        if busyCount == 0 {
            button.image = standardIcon
        }
    }
    
    func asyncWithBusyIndicator(_ fn: @escaping () -> Void) -> Void {
        if(busyCount == 0) {
            button.image = busyIcon
        }
        busyCount += 1
        
        // if we perform on the main thread, the icon change never takes effect
        dispatchQueue.async {
            fn()
            
            // decrement on main thread to avoid races
            DispatchQueue.main.async {
                self.busyCount -= 1
                if(self.busyCount == 0) {
                    self.button.image = self.standardIcon
                }
            }
        }
    }
    
    @objc
    func quit(_: Any) {
        NSRunningApplication.current.terminate()
    }
}
