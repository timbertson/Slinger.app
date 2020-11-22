import Cocoa

protocol CoordinateSystem {}
protocol CoordinateOrigin {}

enum Gnome : CoordinateSystem {}
enum Cocoa : CoordinateSystem {}

enum Global : CoordinateOrigin {}
enum Screen : CoordinateOrigin {}
enum Workspace : CoordinateOrigin {}

struct GRect<System: CoordinateSystem, Origin: CoordinateOrigin> {
    let origin: GPoint<System,Origin>
    let size: NSSize
    
    func move<DestOrigin>(_ offset: CoordinateOffset<System,Origin,DestOrigin>) -> GRect<System,DestOrigin>
    {
        let newOrigin: GPoint<System,DestOrigin> = origin.move(offset)
        // debug("Moved rect at \(self) by \(offset) -> \(newOrigin)")
        return GRect<System,DestOrigin>(origin: newOrigin, size: size)
    }
    
    private func ns() -> NSRect {
        return NSRect.init(origin: origin.ns, size: size)
    }
    
    func intersectionSize(_ other: GRect<System,Origin>) -> NSSize {
        return ns().intersection(other.ns()).size
    }
    
    func invert<DestSystem>(from inversion: InvertYAxis<System, DestSystem,Origin>) -> GRect<DestSystem,Origin> {
        return inversion.apply(self)
    }
}

struct GPoint<System: CoordinateSystem, Origin: CoordinateOrigin> {
    let x: Int
    let y: Int
    var ns: NSPoint { return NSPoint.init(x: x, y: y) }
    
    init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
    
    init(ns: NSPoint) {
        self.init(x: Int(ns.x), y: Int(ns.y))
    }
    
    func move<DestOrigin>(_ offset: CoordinateOffset<System,Origin,DestOrigin>) -> GPoint<System,DestOrigin> {
        let result = GPoint<System,DestOrigin>(x: x - offset.x, y: y - offset.y)
        // debug("Moved point at \(self) by \(offset) -> \(result)")
        return result
    }
    
    func invert<DestSystem>(from inversion: InvertYAxis<System, DestSystem,Origin>) -> GPoint<DestSystem,Origin> {
        return inversion.apply(self)
    }
}

struct CoordinateOffset<System: CoordinateSystem, From: CoordinateOrigin, To: CoordinateOrigin> {
    let x: Int
    let y: Int
    
    func reverse() -> CoordinateOffset<System,To,From> {
        return CoordinateOffset<System,To,From>(x: -x, y: -y)
    }
}

struct CoordinateSize<Origin: CoordinateOrigin> {
    let y: Int
    var cocoa: InvertYAxis<Cocoa,Gnome,Origin> {
        return InvertYAxis(size: self)
    }
    var gnome: InvertYAxis<Gnome,Cocoa,Origin> {
        return InvertYAxis(size: self)
    }
}

struct InvertYAxis<Source: CoordinateSystem, Dest:CoordinateSystem, Origin: CoordinateOrigin> {
    let size: CoordinateSize<Origin>
    
    func apply(_ source: GPoint<Source,Origin>) -> GPoint<Dest,Origin> {
        let result = GPoint<Dest,Origin>(x: source.x, y: size.y - source.y)
        // debug("inverting point \(source) in coordinate space \(size) -> \(result)")
        return result
    }
    
    func apply(_ source: GRect<Source,Origin>) -> GRect<Dest,Origin> {
        // when inverting a rect, we swap the origin too (i.e. reference from topleft instead of bottomleft)
        let oppositeCorner = GPoint<Source,Origin>(x: source.origin.x, y: source.origin.y + Int(source.size.height))
        let result = GRect(origin: self.apply(oppositeCorner), size: source.size)
        // debug("inverting rect \(source) in coordinate space \(size) -> \(result)")
        return result
    }
    
    // just for aligning types - the reverse of a point inversion is itself
    func reverse() -> InvertYAxis<Dest,Source,Origin> {
        return InvertYAxis<Dest,Source,Origin>(size: self.size)
    }
    
    static func fromCocoa<Origin>(_ size: CoordinateSize<Origin>) -> InvertYAxis<Cocoa, Gnome, Origin> {
        return InvertYAxis<Cocoa,Gnome,Origin>(size: size)
    }
    
    static func fromGnome<Origin>(_ size: CoordinateSize<Origin>) -> InvertYAxis<Gnome, Cocoa, Origin> {
        return InvertYAxis<Gnome,Cocoa,Origin>(size: size)
    }
}

extension NSScreen {
    // TODO we could probably access `frame` less often if it's slow
    
    func gFrame() -> GRect<Cocoa,Global> {
        let frame = self.frame
        return GRect(origin: GPoint(ns: frame.origin), size: frame.size)
    }
    
    func gVisibleFrame() -> GRect<Cocoa,Global> {
        let frame = self.visibleFrame
        return GRect(origin: GPoint(ns: frame.origin), size: frame.size)
    }
    
    private func offsetRect<System,From,To>(from: NSPoint, to: NSPoint) -> CoordinateOffset<System,From,To> {
        return CoordinateOffset<System,From,To>(x: Int(to.x) - Int(from.x), y: Int(to.y) - Int(from.y))
    }
    
    func screenToWorkspaceOffset() -> CoordinateOffset<Cocoa,Screen,Workspace> {
        return offsetRect(from: self.frame.origin, to: self.visibleFrame.origin)
    }
    
    func globalToScreenOffset() -> CoordinateOffset<Cocoa,Global,Screen> {
        return offsetRect(from: NSScreen.primaryScreen().frame.origin, to: self.frame.origin)
    }
    
    static func globalSize() -> CoordinateSize<Global> {
        return CoordinateSize(y: Int(primaryScreen().frame.size.height))
    }
    func screenSize() -> CoordinateSize<Screen> {
        return CoordinateSize(y: Int(frame.size.height))
    }
    func workspaceSize() -> CoordinateSize<Workspace> {
        return CoordinateSize(y: Int(visibleFrame.size.height))
    }
    
    static func primaryScreen() -> NSScreen {
        return NSScreen.screens[0]
    }
    
    private func cocoaWorkspaceOffset() -> NSPoint {
        let visible = visibleFrame.origin
        let screen = frame.origin
        return NSPoint.init(x: visible.x - screen.x, y: visible.y - screen.y)
    }
}
