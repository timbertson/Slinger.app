import Foundation
import JavaScriptCore
import AXSwift

#if DEBUG
    func debug(_ msg: String) {
        NSLog("DEBUG: \(msg)")
    }
#else
    func debug(_ msg: @autoclosure () -> String) {
        // noop
    }
#endif

@objc protocol PointExport: JSExport {
    var x: Float { get }
    var y: Float { get }
}

class Point: NSObject, PointExport {
    let x: Float
    let y: Float
    init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
    
    static func ofNS(point: GPoint<Gnome,Workspace>) -> Point {
        return Point.init(x: Float(point.ns.x), y: Float(point.ns.y))
    }
    
    static func ofNS(size: NSSize) -> Point {
        return Point.init(x: Float(size.width), y: Float(size.height))
    }
    
    static func ofJS(_ point: JSValue) -> Point {
        return Point.init(
            x: Float(point.objectForKeyedSubscript("x").toNumber().floatValue),
            y: Float(point.objectForKeyedSubscript("y").toNumber().floatValue))
    }
    
    func toNSPoint() -> GPoint<Gnome,Workspace> {
        return GPoint<Gnome,Workspace>(ns: NSPoint.init(x: Int(x), y: Int(y)))
    }
    
    func toNSSize() -> NSSize {
        return NSSize.init(width: Int(x), height: Int(y))
    }
}


@objc protocol RectExport: JSExport {
    var pos: PointExport { get set }
    var size: PointExport { get set }
}

class Rect: NSObject, RectExport {
    var pos: PointExport
    var size: PointExport
    init(pos: Point, size: Point) {
        self.pos = pos
        self.size = size
    }
    static func ofNS(_ r: GRect<Gnome,Workspace>) -> Rect {
        return Rect.init(
            pos: Point.ofNS(point: r.origin),
            size: Point.ofNS(size: r.size)
        )
    }
    
    static func ofJS(_ r: JSValue) -> Rect {
        let pos: JSValue = r.objectForKeyedSubscript("pos")
        let size: JSValue = r.objectForKeyedSubscript("size")
        return Rect.init(pos: Point.ofJS(pos), size: Point.ofJS(size))
    }
    
    func toNS() -> GRect<Gnome,Workspace> {
        let pos = GPoint<Gnome,Workspace>(ns: NSPoint.init(x: Int(self.pos.x), y: Int(self.pos.y)))
        let size = NSSize.init(width: Int(self.size.x), height: Int(self.size.y))
        return GRect<Gnome,Workspace>(origin: pos, size: size)
    }
}

@objc protocol Connectable : JSExport {
    func connect(_ signal: String, _ fn: JSValue)
}

class WindowRef : NSObject {
    let app: NSRunningApplication
    let win: UIElement
    private var lastKnownFrame: GRect<Gnome,Global>? // for some reason, AXUIelements share gnome's coordinate system
    
    init(app: NSRunningApplication, win: UIElement) {
        self.app = app
        self.win = win
    }
    
    // because WindowRefs are stateless (i.e. not persisted between slinger actions), we can
    // get away with never invalidating the rect once we've accessed it
    func frame() -> GRect<Gnome,Global>? {
        if lastKnownFrame == nil {
            lastKnownFrame = logExceptionOpt(desc: "window.frame") {
                try ((win.attribute(.frame) as NSValue?)?.rectValue).map { rect in
                    GRect(origin: GPoint<Gnome,Global>(ns: rect.origin), size: rect.size)
                }
            }
        }
        return lastKnownFrame
    }
    
    func frameIfCached() -> GRect<Gnome,Global>? {
        return lastKnownFrame
    }
}

@objc protocol SystemExport: JSExport {
    func currentWindow() -> WindowRef?
    func windowRect(_ w: WindowRef) -> RectExport?
    func moveResize(_ win: WindowRef, _ rect: JSValue) -> ()
    func workspaceArea(_ win: WindowRef) -> PointExport?
    func unmaximize(_ win: WindowRef) -> ()
    func maximize(_ win: WindowRef) -> ()
    func getMaximized(_ win: WindowRef) -> Bool
    func visibleWindows() -> [Any] // actually (WindowRef, Array<WindowRef>) but JSExport doesn't allow it
    func minimizedWindows() -> Array<WindowRef>
    func activate(_ win: WindowRef) -> ()
    func minimize(_ win: WindowRef) -> ()
    func unminimize(_ win: WindowRef) -> ()
    func activateLater(_ win: WindowRef) -> ()
    func setWindowHidden(_ win: WindowRef, _ hidden: Bool) -> ()
    func stableSequence(_ win: WindowRef) -> Int
    func windowTitle(_ win: WindowRef) -> String?
    
    var Cairo : CairoExport { get }
    var Clutter : ClutterExport { get }
    
    // pull out constructors as functions, for simpler interface
    func newClutterColor(_ attrs: JSValue) -> ClutterColorExport
    func newClutterActor() -> ActorExport
    func newClutterCanvas() -> ClutterCanvasExport
}

class CocoaSystem: NSObject, SystemExport {
    let Clutter: ClutterExport = ClutterJS.init()
    let Cairo: CairoExport = CairoJS.init()
    var screen: NSScreen!
    private var jsError: JSValue?
    private let ctx: JSContext
    private var previousSizeCache: [(pid: pid_t, frame: GRect<Gnome,Global>)] // TODO: track per workspace?
    private let previousSizeCacheMax = 10
    private let ec: DispatchQueue
    
    init(_ ctx: JSContext, dispatchQueue: DispatchQueue) {
        self.ctx = ctx
        self.previousSizeCache = []
        self.ec = dispatchQueue
        super.init()
        ctx.exceptionHandler = { context, exception in
            self.jsError = exception
            //            NSLog("JS Error: \(exception?.description ?? "unknown error")")
        }
    }
    
    private func captureJSError(_ result: JSValue?) throws -> JSValue {
        if let error = jsError {
            jsError = nil
            var desc = String(describing: error)
            if let stack = error.forProperty("stack") {
                desc += "\n" + String(describing: stack)
            }
            throw RuntimeError.init(desc)
        }
        return result ?? JSValue.init(undefinedIn: ctx)
    }
    
    @discardableResult
    func callJS(_ fn: JSValue, arguments: [Any]!) throws -> JSValue {
        return try captureJSError(fn.call(withArguments: arguments))
    }
    
    @discardableResult
    func callJSMethod(_ obj: JSValue, fn: String, arguments: [Any]!) throws -> JSValue {
        return try captureJSError(obj.invokeMethod(fn, withArguments: arguments))
    }
    
    private func areaOf(size: NSSize) -> Int {
        return Int(size.width) * Int(size.height)
    }
    
    private func screenOf(windowFrame: GRect<Gnome,Global>?) -> NSScreen? {
        guard let windowFrame = windowFrame?.invert(from: NSScreen.globalSize().gnome) else {
            return nil
        }
        
        var bestMatch: NSScreen? = nil
        var bestVolume: Int = 0
        
        NSScreen.screens.forEach { screen in
            let screenFrame : GRect<Cocoa,Global> = screen.gFrame()
            let intersection = screenFrame.intersectionSize(windowFrame)
            debug("window \(windowFrame) vs screen \(screenFrame) :: \(intersection)")
            let volume = areaOf(size: intersection)
            if (volume > bestVolume) {
                bestVolume = volume
                bestMatch = screen
            }
        }
        debug("window \(windowFrame) is on screen \(String(describing: bestMatch))")
        return bestMatch
    }
    
    func moveResize(_ win: WindowRef, _ jsrect: JSValue) {
        let rect = Rect.ofJS(jsrect)
        guard let screen = NSScreen.main else {
            NSLog("moveResize: no main screen")
            return
        }
        let gnomeRect = rect.toNS()
        let workspaceRect = gnomeRect.invert(from: screen.workspaceSize().gnome)
        let screenRect = workspaceRect.move(screen.screenToWorkspaceOffset().reverse())
        let globalRect = screenRect.move(screen.globalToScreenOffset().reverse())
        moveResizeNS(win, globalRect.invert(from: NSScreen.globalSize().cocoa))
    }
    
    func moveResizeNS(_ win: WindowRef, _ rect: GRect<Gnome,Global>) {
        logException(desc: "moveResize -> \(rect)") {
            try win.win.setAttribute(.position, value: rect.origin.ns)
            try win.win.setAttribute(.size, value: rect.size)
        }
    }
    
    func workspaceArea(_ win: WindowRef) -> PointExport? {
        if let frame = workspaceAreaNS() {
            return Point.ofNS(size: frame.size)
        }
        return nil
    }
    
    func workspaceAreaNS() -> GRect<Cocoa,Global>? {
        return NSScreen.main?.gVisibleFrame()
    }
    
    private func pushPreviousSize(_ win: WindowRef) -> Void {
        previousSizeCache = previousSizeCache.filter { ps in ps.pid != win.app.processIdentifier }
        while(previousSizeCache.count > previousSizeCacheMax) {
            previousSizeCache.removeFirst()
        }
        if let frame = win.frame() {
            previousSizeCache.append((pid: win.app.processIdentifier, frame: frame))
        }
    }
    
    private func popPreviousSize(_ win: WindowRef) -> GRect<Gnome,Global>? {
        if let idx = previousSizeCache.index(where: { pair in pair.pid == win.app.processIdentifier }) {
            let result = previousSizeCache[idx]
            previousSizeCache.remove(at: idx)
            return result.frame
        } else {
            NSLog("Can't find previous frame for \(win.app) in \(previousSizeCache)")
            return nil
        }
    }
    
    func maximize(_ win: WindowRef) {
        // not a real maximize, but nobody likes that anyway
        if let rect = workspaceAreaNS() {
            pushPreviousSize(win)
            moveResizeNS(win, rect.invert(from: NSScreen.globalSize().cocoa))
        }
    }
    
    func unmaximize(_ win: WindowRef) {
        logException(desc: "unmaximize") {
            try win.win.setAttribute(.fullScreen, value: false)
        }
        if let frame = popPreviousSize(win) {
            NSLog("Restoring previous frame: \(frame)")
            moveResizeNS(win, frame)
        }
    }
    
    func getMaximized(_ win: WindowRef) -> Bool {
        let fullscreen = logExceptionOpt(desc: "getMaximized") { try win.win.attribute(.fullScreen) as Bool? }
        if (fullscreen == true) {
            return true
        }
        
        guard let workspaceRect = workspaceAreaNS() else { return false }
        guard let windowRect = win.frame() else { return false }
        
        // this is a bit loose, but mostly works
        let workspaceArea = areaOf(size: workspaceRect.size)
        let windowArea = areaOf(size: windowRect.size)
        let tolerance = Int(0.05 * Double(workspaceArea))
        let difference = abs(workspaceArea - windowArea)
        
        let isMaximized = difference < tolerance
        debug("isMaximized: \(isMaximized) ( diff = \(difference), tolerance = \(tolerance) )")
        return isMaximized
    }
    
    private func allApplications() -> Array<NSRunningApplication> {
        return NSWorkspace.shared.runningApplications
    }
    
    private func isNormalWindow(_ win: UIElement) -> Bool {
        do {
            if let role = try win.attribute(.role) as String?, role != kAXWindowRole {
                return false
            }
            if let subrole = try win.attribute(.subrole) as String?, subrole != kAXStandardWindowSubrole {
                return false
            }
            return true
        } catch {
            return false
        }
    }
    
    private func windowsFromApp(_ app: Application, runningApp: NSRunningApplication) throws -> [WindowRef]? {
        if let windows = try app.windows() {
            return windows
                .filter(isNormalWindow)
                .map { win in WindowRef.init(app: runningApp, win: win) }
        } else {
            return nil
        }
    }
    
    private func window(_ window: WindowRef, isOnScreen screen: NSScreen) -> Bool {
        debug("getting screen of \(window)")
        return screenOf(windowFrame: window.frame()) == screen
    }
    
    private func windowsFromVisibleApps(filter: (WindowRef) throws -> Bool) rethrows -> Array<WindowRef> {
        var result: Array<WindowRef> = []
        guard let screen = NSScreen.main else {
            return result
        }
        debug("getting windows on \(screen)")
        allApplications().forEach { runningApp in
            if !runningApp.isHidden {
                swallowException {
                    if let app = Application.init(runningApp) {
                        if let windows = try windowsFromApp(app, runningApp: runningApp) {
                            result.append(contentsOf: windows.filter { win in
                                do {
                                    return try filter(win) && window(win, isOnScreen: screen)
                                } catch {
                                    return false
                                }
                            })
                        }
                    }
                }
            }
        }
        // NSLog("retrieved \(result.count) windows")
        return result
    }
    
    private func isMinimized(_ win: WindowRef) throws -> Bool {
        return try win.win.attribute(.minimized) as Bool? ?? false
    }
    
    func visibleWindowsTyped() -> (WindowRef?, [WindowRef]) {
        return logException(desc: "visibleWindows") {
            let visible = try windowsFromVisibleApps(filter: { win in try !isMinimized(win) })
            
            var current: WindowRef? = nil
            if let frontmostApp = NSWorkspace.shared.frontmostApplication {
                current = visible.first(where: { win in
                    win.app == frontmostApp && isMain(window: win.win)
                })
            }
            return (current, visible)
        } ?? (nil, [])
    }
    
    func visibleWindows() -> [Any] {
        let (current, all) = visibleWindowsTyped()
        return [current as Any, all]
    }
    
    func minimizedWindows() -> Array<WindowRef> {
        return logException(desc: "minimizedWindows") {
            try windowsFromVisibleApps(filter: { win in try isMinimized(win) })
        } ?? []
    }
    
    func stableSequence(_ win: WindowRef) -> Int {
        // Cocoa doesn't give us one without stupid amounts of effort.
        // Currently only used to differentiate windows with identical frames,
        // so pid+titleHash should be good enough

        let title = windowTitle(win)
        NSLog("getting stableSequence for window \(String(describing: title))")
        return Int(win.app.processIdentifier) + (title?.hashValue ?? 0)
    }
    
    func windowTitle(_ win: WindowRef) -> String? {
        return logExceptionOpt(desc: "windowTitle") {
            return try win.win.attribute(.title) as String?
        }
    }
    
    func activate(_ win: WindowRef) {
        logException(desc: "activate") {
            let pid = try win.win.pid()
            guard let app: NSRunningApplication = NSRunningApplication.init(processIdentifier: pid) else {
                NSLog("Unable to get app \(pid)")
                return
            }
            
            let success = app.activate(options: [.activateAllWindows,.activateIgnoringOtherApps])
            if (!success) {
                NSLog("NSRunningApplication.activate() failed")
                return
            }
            
            debug("Activating window of app \(win.app) with rect \(String(describing: win.frameIfCached()))")
            try win.win.setAttribute(Attribute.main, value: true)
        }
    }
    
    func minimize(_ win: WindowRef) {
        logException(desc: "minimize") {
            try win.win.setAttribute(.minimized, value: true)
        }
    }
    
    func unminimize(_ win: WindowRef) {
        logException(desc: "unminimize") {
            try win.win.setAttribute(.minimized, value: false)
        }
    }
    
    func activateLater(_ win: WindowRef) {
        activate(win)
    }
    
    func setWindowHidden(_ win: WindowRef, _ hidden: Bool) {
        ec.async { logException(desc: "setWindowHidden") {
            try win.win.setAttribute(.hidden, value: hidden)
        }}
    }
    
    private func isMain(window: UIElement) -> Bool {
        return logExceptionOpt(desc: "isMain") { try window.attribute(.main) } ?? false
    }

    func currentWindow() -> WindowRef? {
        if let application = NSWorkspace.shared.frontmostApplication {
            let uiApp = Application(application)!
            if let wins = logExceptionOpt(desc: "uiApp.windows()", { try uiApp.windows() }) {
                let frontmostOpt = wins.first(where: { win in isMain(window: win) })
                if let frontmost = frontmostOpt {
                    return WindowRef.init(app: application, win: frontmost)
                }
            }

            // XXX .focusedWindow or mainWindow ought to do it, but returns an unknown type which isn't an AXUIElement:
            
            //            if let win: AXUIElement = try! uiApp.attribute(.mainWindow) {
            //                print(try! UIElement.init(win).attribute(.role) ?? "(no role)")
            //                return WindowRef.init(UIElement.init(win))
            //            }

            //            if let win: AXUIElement = try! uiApp.attribute(.focusedWindow) {
            //                print(try! UIElement.init(win).attribute(.role) ?? "(no role)")
            //                return WindowRef.init(UIElement.init(win))
            //            }
        }
        return nil
    }
    
    func windowRect(_ w: WindowRef) -> RectExport? {
        return w.frame().flatMap { rect in
            (NSScreen.main).map { screen in
                // XXX this could definitely be more efficeint
                let cocoaRect = rect.invert(from: NSScreen.globalSize().gnome)
                let screenRect = cocoaRect.move(screen.globalToScreenOffset())
                let workspaceRect = screenRect.move(screen.screenToWorkspaceOffset())
                let convertedRect = workspaceRect.invert(from: screen.workspaceSize().cocoa)
                return Rect.ofNS(convertedRect)
            }
        }
    }
    
    func newClutterColor(_ attrs: JSValue) -> ClutterColorExport {
        func component(_ name: String) -> Int {
            return attrs.objectForKeyedSubscript(name)?.toNumber()?.intValue ?? 0
        }
        return ClutterColor.init(
            red: component("red"),
            green: component("green"),
            blue: component("blue"),
            alpha: component("alpha")
        )
    }
    
    func newClutterActor() -> ActorExport {
        return Actor.init(Sys: self)
    }
    
    func newClutterCanvas() -> ClutterCanvasExport {
        return ClutterCanvas.init(Sys: self)
    }
    
}

extension JSExport {
    func nonNull() -> Self? {
        if let _ = self as? NSNull {
            return nil
        }
        return self
    }
}

extension JSValue {
    func nonNull() -> Self? {
        if (self.isNull || self.isUndefined) {
            return nil
        }
        return self
    }
}

