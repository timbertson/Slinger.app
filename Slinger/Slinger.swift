import Cocoa
import JavaScriptCore
import ApplicationServices
import AXSwift

@discardableResult
func logException<T>(desc: String, _ block: () throws -> T) -> T? {
    do {
        return try block()
    } catch let error {
        NSLog("Exception thrown in `\(desc): \(error)")
        return nil
    }
}

func swallowException<T>(_ block: () throws -> T) -> T? {
    do {
        return try block()
    } catch {
        return nil
    }
}

func logExceptionOpt<T>(desc: String, _ block: () throws -> T?) -> T? {
    do {
        return try block()
    } catch let error {
        NSLog("Exception thrown in `\(desc): \(error)")
        return nil
    }
}


struct RuntimeError: Error {
    let message: String
    
    init(_ message: String) {
        self.message = message
    }
    
    public var localizedDescription: String {
        return message
    }
}

class SlingerWindow : NSWindow {
    override var canBecomeKey: Bool { get { return true } }
}

class Slinger {
    private var ext: JSValue
    private var windowActions: JSValue
    private let ctx: JSContext
    private let Sys: CocoaSystem
    private var window: NSWindow?

    init(dispatchQueue: DispatchQueue) throws {
        let vm = JSVirtualMachine()
        ctx = JSContext(virtualMachine: vm)!
        ext = JSValue.init(nullIn: ctx)
        Sys = CocoaSystem.init(ctx, dispatchQueue: dispatchQueue)
        
        let log: @convention(block) (String) -> Void = { msg in
            NSLog(msg)
        }
        
        // init globals
        ctx.setObject(log, forKeyedSubscript: "log" as NSString)
        
        let path = Bundle.main.path(forResource: "cocoa_impl", ofType: "js")!
        let source = try String(contentsOfFile: path, encoding: String.Encoding.utf8)

        ctx.evaluateScript(source)
        ext = try Sys.callJS(ctx.objectForKeyedSubscript("makeExtension"), arguments: [Sys as SystemExport])
        windowActions = ext.objectForKeyedSubscript("actions")
    }
    
    func hide() {
        NSLog("hiding")
        if let window = self.window {
            window.close()
            self.window = nil
        }
    }
    
    func show(_ appDelegate: NSApplicationDelegate) {
        hide()
        debug(" --- ")
        debug("*** Showing")
        
        guard let screen = NSScreen.main else {
            NSLog("unable to get main screen")
            return
        }
        Sys.screen = screen
        let primaryScreen = NSScreen.primaryScreen()
        
        let mouseLocation = GPoint<Cocoa,Global>(ns: NSEvent.mouseLocation)
        let screenLocation = mouseLocation.move(screen.globalToScreenOffset())
        let workspaceLocation = screenLocation.move(screen.screenToWorkspaceOffset())
        let gnomeLocation = workspaceLocation.invert(from: screen.workspaceSize().cocoa)

        let contentView = ClutterView.init()
        let parent = Actor.init(Sys: self.Sys, view: contentView)
        debug("menu origin = \(gnomeLocation)")
        
        let window = SlingerWindow.init(contentRect: screen.visibleFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = contentView
        
        let ui : JSValue? = logException(desc: "show") {
            try Sys.callJSMethod(ext, fn: "show_ui", arguments: [parent, Point.ofNS(point: gnomeLocation)])
        }?.nonNull()
        guard let _ = ui?.toObject() else {
            NSLog("no menu created")
            return
        }
        
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.ignoresMouseEvents = false

#if DEBUG
        func dumpChildren(view: NSView, indent: String) {
            NSLog("\(indent)view \(view) @ \(view.frame)")
            view.subviews.reversed().forEach { (view) in
                dumpChildren(view: view, indent: indent+"  ")
            }
        }
        dumpChildren(view: contentView, indent: "")
#endif

        NSApp.activate(ignoringOtherApps: true)
        NSLog("app activated")
        window.makeKeyAndOrderFront(appDelegate)
        NSLog("window: key and ordered front, FR = \(String(describing: window.firstResponder))")

        // prevent autorelease, double-release
        self.window = window
        window.isReleasedWhenClosed = false
    }
    
    func action(_ name: String) -> Void {
        logException(desc: name) {
            try Sys.callJS(windowActions.objectForKeyedSubscript(name), arguments: [])
        }
    }
    
    func action(_ name: String, arguments: [Any]) -> Void {
        NSLog("invoking action \(name)")
        logException(desc: name) {
            // this could be cached if I weren't so lazy...
            let fn = try Sys.callJSMethod(windowActions, fn: name, arguments: arguments)
            try Sys.callJS(fn, arguments: [])
        }
    }
    
    func convertCallback<A1>(_ fn: JSValue) -> ((A1) throws -> JSValue) {
        @discardableResult
        func f(_ a: A1) throws -> JSValue {
            return try Sys.callJS(fn, arguments: [a])
        }
        return f
    }
}
