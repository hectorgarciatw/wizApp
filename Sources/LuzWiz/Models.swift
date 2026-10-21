import SwiftUI
import AppKit

struct Lamp: Codable, Identifiable, Hashable {
    /// The lamp's MAC address; stays the same when the router hands out a new IP.
    let id: String
    var ip: String
    var name: String
    var firmware: String?
    var module: String?
    /// The lamp's own dim-to-warm curve from getUserConfig, as [kelvin, dimming %] pairs.
    var warmCurve: [[Int]]?
}

struct RGB: Equatable {
    var r: Int
    var g: Int
    var b: Int

    init(r: Int, g: Int, b: Int) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hue: Double, saturation: Double) {
        let color = NSColor(hue: hue, saturation: saturation, brightness: 1, alpha: 1).usingColorSpace(.sRGB)
            ?? .white
        r = Int((color.redComponent * 255).rounded())
        g = Int((color.greenComponent * 255).rounded())
        b = Int((color.blueComponent * 255).rounded())
    }

    var hueSaturation: (hue: Double, saturation: Double) {
        let color = NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return (Double(h), Double(s))
    }

    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
}

/// What getPilot reports: the light as it is right now.
struct Pilot {
    var isOn = false
    var dimming = 100
    var temp: Int?
    var rgb: RGB?
    /// Cool and warm white LEDs mixed into a colour (0…255).
    var cool = 0
    var warm = 0
    var sceneId = 0
    var speed: Int?
    var rssi: Int?

    init(_ result: [String: Any]) {
        isOn = result["state"] as? Bool ?? false
        dimming = result["dimming"] as? Int ?? 100
        temp = result["temp"] as? Int
        if let r = result["r"] as? Int, let g = result["g"] as? Int, let b = result["b"] as? Int {
            rgb = RGB(r: r, g: g, b: b)
        }
        cool = result["c"] as? Int ?? 0
        warm = result["w"] as? Int ?? 0
        sceneId = result["sceneId"] as? Int ?? 0
        speed = result["speed"] as? Int
        rssi = result["rssi"] as? Int
    }
}

struct Favorite: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// setPilot parameters: dimming plus temp, r/g/b or sceneId (and speed).
    var params: [String: Int]
}

struct LightScene: Identifiable {
    let id: Int
    let name: String
    let symbol: String
    let tint: Color
    /// Animated scenes accept a speed; static ones (whites, night light, focus…) don't.
    var dynamic: Bool { !(9...19).contains(id) }
}

enum Scenes {
    static let all: [LightScene] = [
        LightScene(id: 11, name: "Blanco cálido", symbol: "lightbulb.fill", tint: .orange),
        LightScene(id: 12, name: "Luz de día", symbol: "sun.max.fill", tint: .yellow),
        LightScene(id: 13, name: "Blanco frío", symbol: "snowflake", tint: .cyan),
        LightScene(id: 14, name: "Luz nocturna", symbol: "moon.stars.fill", tint: .indigo),
        LightScene(id: 15, name: "Concentración", symbol: "scope", tint: .blue),
        LightScene(id: 16, name: "Relax", symbol: "leaf.fill", tint: .orange),
        LightScene(id: 17, name: "Colores reales", symbol: "eyedropper.full", tint: .white),
        LightScene(id: 18, name: "Hora de TV", symbol: "tv.fill", tint: .purple),
        LightScene(id: 19, name: "Plantas", symbol: "camera.macro", tint: .pink),
        LightScene(id: 9, name: "Despertar", symbol: "alarm.fill", tint: .yellow),
        LightScene(id: 10, name: "A dormir", symbol: "bed.double.fill", tint: .orange),
        LightScene(id: 29, name: "Vela", symbol: "flame", tint: .orange),
        LightScene(id: 5, name: "Fogata", symbol: "flame.fill", tint: .red),
        LightScene(id: 6, name: "Acogedor", symbol: "cup.and.saucer.fill", tint: .brown),
        LightScene(id: 3, name: "Atardecer", symbol: "sun.horizon.fill", tint: .orange),
        LightScene(id: 30, name: "Blanco dorado", symbol: "sun.min.fill", tint: .yellow),
        LightScene(id: 2, name: "Romance", symbol: "heart.fill", tint: .pink),
        LightScene(id: 1, name: "Océano", symbol: "water.waves", tint: .blue),
        LightScene(id: 23, name: "Profundidad", symbol: "drop.fill", tint: .teal),
        LightScene(id: 7, name: "Bosque", symbol: "tree.fill", tint: .green),
        LightScene(id: 24, name: "Selva", symbol: "pawprint.fill", tint: .green),
        LightScene(id: 25, name: "Mojito", symbol: "wineglass.fill", tint: .mint),
        LightScene(id: 8, name: "Pastel", symbol: "paintpalette.fill", tint: .pink),
        LightScene(id: 20, name: "Primavera", symbol: "sparkles", tint: .mint),
        LightScene(id: 21, name: "Verano", symbol: "sun.dust.fill", tint: .yellow),
        LightScene(id: 22, name: "Otoño", symbol: "wind", tint: .orange),
        LightScene(id: 4, name: "Fiesta", symbol: "party.popper.fill", tint: .purple),
        LightScene(id: 26, name: "Club", symbol: "music.note", tint: .purple),
        LightScene(id: 31, name: "Pulso", symbol: "waveform.path.ecg", tint: .red),
        LightScene(id: 32, name: "Steampunk", symbol: "gearshape.2.fill", tint: .brown),
        LightScene(id: 27, name: "Navidad", symbol: "gift.fill", tint: .red),
        LightScene(id: 28, name: "Halloween", symbol: "theatermasks.fill", tint: .orange),
    ]

    static func scene(_ id: Int) -> LightScene? { all.first { $0.id == id } }
}

enum WhiteLight {
    static let range: ClosedRange<Double> = 2200...6500

    static let presets: [(name: String, kelvin: Double)] = [
        ("Vela", 2200), ("Cálida", 2700), ("Neutra", 4000), ("Día", 5000), ("Fría", 6500),
    ]

    private static let stops: [(kelvin: Double, r: Double, g: Double, b: Double)] = [
        (2200, 1.00, 0.62, 0.25), (2700, 1.00, 0.76, 0.48), (4000, 1.00, 0.92, 0.82),
        (5000, 0.97, 0.97, 1.00), (6500, 0.78, 0.87, 1.00),
    ]

    /// An approximate on-screen colour for a white temperature.
    static func color(_ kelvin: Double) -> Color {
        let k = min(max(kelvin, range.lowerBound), range.upperBound)
        let upper = stops.firstIndex { $0.kelvin >= k } ?? stops.count - 1
        let lower = max(upper - 1, 0)
        let a = stops[lower], b = stops[upper]
        let t = b.kelvin == a.kelvin ? 0 : (k - a.kelvin) / (b.kelvin - a.kelvin)
        return Color(red: a.r + (b.r - a.r) * t, green: a.g + (b.g - a.g) * t, blue: a.b + (b.b - a.b) * t)
    }

    static var gradient: [Color] { stops.map { Color(red: $0.r, green: $0.g, blue: $0.b) } }

    /// What WiZ ships as its dim-to-warm curve, for lamps that don't report one.
    static let defaultWarmCurve = [[1800, 1], [1800, 10], [2700, 50], [4200, 90], [4200, 100]]

    /// The white temperature a dim-to-warm curve gives at `dimming` %, clamped to what the lamp can show.
    static func warmTemperature(at dimming: Double, curve: [[Int]]) -> Double {
        let points = curve.compactMap { $0.count == 2 ? (kelvin: Double($0[0]), dimming: Double($0[1])) : nil }
            .sorted { $0.dimming < $1.dimming }
        guard let first = points.first, let last = points.last else { return 2700 }
        var kelvin = dimming <= first.dimming ? first.kelvin : last.kelvin
        for (a, b) in zip(points, points.dropFirst()) where dimming > a.dimming && dimming <= b.dimming {
            let t = b.dimming == a.dimming ? 1 : (dimming - a.dimming) / (b.dimming - a.dimming)
            kelvin = a.kelvin + (b.kelvin - a.kelvin) * t
            break
        }
        return min(max(kelvin, range.lowerBound), range.upperBound)
    }
}
