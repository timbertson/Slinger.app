import Cocoa
import JavaScriptCore
import ApplicationServices

class WindowRef : NSObject {
    let win: UIElement
    init(_ win: UIElement) {
        self.win = win
    }
}

@objc protocol ActorExport : JSExport {
    set_position(_ x: NSNumber, _ y: NSNumber)
}

class Actor : NSObject, ActorExport {
    init(win: NSWindow)
}

@objc protocol SystemExport: JSExport {
    func currentWindow() -> WindowRef?
    func actorOfWin(win: WindowRef) -> Actor
    func windowRect(_ w: WindowRef) -> Rect?
    func workspaceRect() -> Rect?
    func workspaceOrigin() -> Point
}

class Point: NSObject {
    let x: Float
    let y: Float
    init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
    
    static func ofNS(point: NSPoint) -> Point {
        return Point.init(x: Float(point.x), y: Float(point.y))
    }

    static func ofNS(size: NSSize) -> Point {
        return Point.init(x: Float(size.width), y: Float(size.height))
    }
}

class Rect: NSObject {
    let pos: Point
    let size: Point
    init(pos: Point, size: Point) {
        self.pos = pos
        self.size = size
    }
    static func ofNS(_ r: NSRect) -> Rect {
        return Rect.init(pos: Point.ofNS(point: r.origin), size: Point.ofNS(size: r.size))
    }
}

@discardableResult
func logException<T>(desc: String, _ block: () throws -> T) -> T? {
    do {
        return try block()
    } catch let error {
        NSLog("Exception thrown in `\(desc): \(error)")
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

class ExtensionSystem: NSObject, SystemExport {
    func currentWindow() -> WindowRef? {
        if let application = NSWorkspace.shared.frontmostApplication {
            let uiApp = Application(application)!
            if let wins = logExceptionOpt(desc: "uiApp.windows()", { try uiApp.windows() }) {
                let frontmostOpt = logExceptionOpt(desc: "frontmost", {
                    try wins.first(where: {win in try win.attribute(.main) ?? false})
                })
                if let frontmost = frontmostOpt {
                    return WindowRef.init(frontmost)
                }
            }
            
//            if let win: AXUIElement = try! uiApp.attribute(.mainWindow) {
//                print(try! UIElement.init(win).attribute(.role) ?? "(no role)")
//                return WindowRef.init(UIElement.init(win))
//            }

// XXX .focusedWindow or mainWindow ought to do it, but returns an unknown type which isn't an AXUIElement...
//            if let win: AXUIElement = try! uiApp.attribute(.focusedWindow) {
//                print(try! UIElement.init(win).attribute(.role) ?? "(no role)")
//                return WindowRef.init(UIElement.init(win))
//            }
        }
        return nil
    }
    
    func windowRect(_ w: WindowRef) -> Rect? {
        let frame: NSValue? = logExceptionOpt(desc: "frame") { try w.win.attribute(.frame) }
        return frame.map { rect in Rect.ofNS(rect.rectValue) }
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

class Slinger {
    private var ext: JSValue
    private let ctx: JSContext
    private var jsError: JSValue?
    private var window: NSWindow?

    private func captureJSError(_ result: JSValue?) throws -> JSValue {
        if let error = jsError {
            jsError = nil
            throw RuntimeError.init(String(describing: error))
        }
        return result ?? JSValue.init(undefinedIn: ctx)
    }
    
    @discardableResult
    private func callJS(_ fn: JSValue, arguments: [Any]!) throws -> JSValue {
        return try captureJSError(fn.call(withArguments: arguments))
    }
    
    @discardableResult
    private func callJSMethod(_ obj: JSValue, fn: String, arguments: [Any]!) throws -> JSValue {
        return try captureJSError(obj.invokeMethod(fn, withArguments: arguments))
    }
    
    init() throws {
        let vm = JSVirtualMachine()
        ctx = JSContext(virtualMachine: vm)!
        ext = JSValue.init(nullIn: ctx)
        ctx.exceptionHandler = { context, exception in
            self.jsError = exception
//            NSLog("JS Error: \(exception?.description ?? "unknown error")")
        }
        
        let system = ExtensionSystem.init()
        
        let log: @convention(block) (String) -> Void = { msg in
            NSLog(msg)
        }
        
        // init globals
        ctx.setObject(log, forKeyedSubscript: "log" as NSString)
        
        let path = Bundle.main.path(forResource: "cocoa_impl", ofType: "js")!
        let source = try String(contentsOfFile: path, encoding: String.Encoding.utf8)

        ctx.evaluateScript(source)
        ext = try callJS(ctx.objectForKeyedSubscript("makeExtension"), arguments: [system])
        NSLog("Slinger initialized: \(String(describing: ext))")
    }
    
    func hide() {
        if let window = self.window {
            window.close()
            self.window = nil
        }
    }
    
    func show() {
        hide()
        if let workspaceRect = NSScreen.main?.visibleFrame {
            let window = NSWindow.init(contentRect: workspaceRect, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = NSColor.init(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5)
            window.makeKeyAndOrderFront(self)
            self.window = window // prevent GC
        } else {
            NSLog("unable to get main screen dimensions")
        }
        
        logException(desc: "show") {
            try callJSMethod(ext, fn: "show_ui", arguments: [])
        }
    }
}
