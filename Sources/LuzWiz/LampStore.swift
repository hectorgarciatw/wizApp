import SwiftUI
import AppKit
import ServiceManagement

@MainActor @Observable
final class LampStore {
    enum Mode: String, CaseIterable, Identifiable {
        case white = "Blanco", color = "Color", scenes = "Escenas"
        var id: Self { self }
    }

    private(set) var lamps: [Lamp] = []
    private(set) var selectedID: String?
    private(set) var reachable = true
    private(set) var searching = false

    // The light as shown in the panel; refreshed from the lamp, changed by the controls.
    private(set) var isOn = false
    private(set) var brightness = 100.0
    private(set) var temperature = 2700.0
    private(set) var hue = 0.08
    private(set) var saturation = 1.0
    private(set) var sceneId = 11
    private(set) var speed = 100.0
    private(set) var mode = Mode.white
    private(set) var rssi: Int?

    private(set) var favorites: [Favorite] = []
    private(set) var sleepAt: Date?
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    var renaming = false
    var panelOpen = false

    @ObservationIgnored private var pending: [String: Any] = [:]
    @ObservationIgnored private var sending = false
    @ObservationIgnored private var lastInteraction = Date.distantPast
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "lamps"), let saved = try? JSONDecoder().decode([Lamp].self, from: data) {
            lamps = saved
        }
        if let data = defaults.data(forKey: "favorites"),
           let saved = try? JSONDecoder().decode([Favorite].self, from: data) {
            favorites = saved
        }
        selectedID = defaults.string(forKey: "selected") ?? lamps.first?.id
        start()
    }

    var selectedLamp: Lamp? { lamps.first { $0.id == selectedID } }

    var currentScene: LightScene? { Scenes.scene(sceneId) }

    /// The colour the light is giving off, for the icon and the header.
    var displayColor: Color {
        switch mode {
        case .white: WhiteLight.color(temperature)
        case .color: RGB(hue: hue, saturation: saturation).color
        case .scenes: currentScene?.tint ?? .yellow
        }
    }

    var statusText: String {
        guard selectedLamp != nil else { return "Sin lámpara" }
        guard reachable else { return "No responde" }
        var text = isOn ? "Encendida · \(Int(brightness))%" : "Apagada"
        if let sleepAt { text += " · se apaga a las \(sleepAt.formatted(date: .omitted, time: .shortened))" }
        return text
    }

    var signalText: String {
        guard let rssi else { return "—" }
        let quality = switch rssi {
        case (-60)...: "excelente"
        case (-70)...: "buena"
        case (-80)...: "débil"
        default: "muy débil"
        }
        return "\(quality) (\(rssi) dBm)"
    }

    // MARK: - Polling and discovery

    private func start() {
        pollTask = Task { [weak self] in
            await self?.bootstrap()
            while !Task.isCancelled {
                let interval: Double = self?.panelOpen == true ? 4 : 30
                try? await Task.sleep(for: .seconds(interval))
                await self?.refresh()
            }
        }
    }

    private func bootstrap() async {
        if lamps.isEmpty {
            await discover()
        } else {
            await refresh(force: true)
        }
    }

    func panelAppeared() {
        panelOpen = true
        Task { await refresh() }
    }

    /// Reads the lamp's state, unless the user is moving a control (the reply would make the slider jump).
    func refresh(force: Bool = false) async {
        guard let lamp = selectedLamp else { return }
        if !force && (sending || Date().timeIntervalSince(lastInteraction) < 2.5) { return }
        let reply = Wiz.result(await Wiz.send(Wiz.message("getPilot"), to: lamp.ip))
        guard let reply else {
            reachable = false
            failures += 1
            // Two misses in a row: the router may have given the lamp a new IP, so look for it by MAC.
            if failures >= 2 && !searching { await discover() }
            return
        }
        reachable = true
        failures = 0
        // The first lookup can fail while macOS is still asking for local network access.
        if lamp.firmware == nil { await addOrUpdate(mac: lamp.id, ip: lamp.ip) }
        if !force && (sending || Date().timeIntervalSince(lastInteraction) < 2.5) { return }
        apply(Pilot(reply))
    }

    func discover() async {
        guard !searching else { return }
        searching = true
        defer { searching = false }
        let replies = await Wiz.discover(Wiz.message("getPilot"))
        for (ip, data) in replies {
            guard let result = Wiz.result(data), let mac = result["mac"] as? String else { continue }
            await addOrUpdate(mac: mac, ip: ip)
        }
        if selectedLamp == nil { select(lamps.first?.id) }
        if !replies.isEmpty {
            failures = 0
            await refresh(force: true)
        }
    }

    /// Adds a lamp typed in by hand; returns false when nothing at that IP answers like a WiZ lamp.
    func addManual(_ ip: String) async -> Bool {
        let ip = ip.trimmingCharacters(in: .whitespaces)
        guard let result = Wiz.result(await Wiz.send(Wiz.message("getPilot"), to: ip)),
              let mac = result["mac"] as? String else { return false }
        await addOrUpdate(mac: mac, ip: ip)
        select(mac)
        return true
    }

    private func addOrUpdate(mac: String, ip: String) async {
        if let index = lamps.firstIndex(where: { $0.id == mac }) {
            lamps[index].ip = ip
        } else {
            lamps.append(Lamp(id: mac, ip: ip, name: lamps.isEmpty ? "Lámpara" : "Lámpara \(lamps.count + 1)"))
        }
        if let index = lamps.firstIndex(where: { $0.id == mac }), lamps[index].firmware == nil,
           let config = Wiz.result(await Wiz.send(Wiz.message("getSystemConfig"), to: ip)) {
            lamps[index].firmware = config["fwVersion"] as? String
            lamps[index].module = config["moduleName"] as? String
        }
        saveLamps()
    }

    func select(_ id: String?) {
        selectedID = id
        UserDefaults.standard.set(id, forKey: "selected")
        rssi = nil
        Task { await refresh(force: true) }
    }

    func rename(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let index = lamps.firstIndex(where: { $0.id == selectedID }) else { return }
        lamps[index].name = name
        saveLamps()
    }

    func forgetSelected() {
        lamps.removeAll { $0.id == selectedID }
        saveLamps()
        select(lamps.first?.id)
    }

    private func saveLamps() {
        UserDefaults.standard.set(try? JSONEncoder().encode(lamps), forKey: "lamps")
    }

    private func apply(_ pilot: Pilot) {
        isOn = pilot.isOn
        brightness = Double(pilot.dimming)
        if let value = pilot.rssi { rssi = value }
        if let rgb = pilot.rgb, pilot.sceneId == 0 {
            mode = .color
            (hue, saturation) = rgb.hueSaturation
        } else if pilot.sceneId != 0 {
            mode = .scenes
            sceneId = pilot.sceneId
            if let value = pilot.speed { speed = Double(value) }
        } else if let kelvin = pilot.temp {
            mode = .white
            temperature = Double(kelvin)
        }
    }

    // MARK: - Controls

    func setPower(_ on: Bool) {
        isOn = on
        send(["state": on])
    }

    func setBrightness(_ value: Double) {
        brightness = min(max(value.rounded(), 10), 100)
        send(["dimming": Int(brightness)])
    }

    func setTemperature(_ kelvin: Double) {
        temperature = min(max((kelvin / 50).rounded() * 50, WhiteLight.range.lowerBound), WhiteLight.range.upperBound)
        mode = .white
        send(["temp": Int(temperature), "dimming": Int(brightness)])
    }

    func setColor(hue: Double, saturation: Double) {
        self.hue = min(max(hue, 0), 1)
        self.saturation = min(max(saturation, 0), 1)
        mode = .color
        let rgb = RGB(hue: self.hue, saturation: self.saturation)
        send(["r": rgb.r, "g": rgb.g, "b": rgb.b, "dimming": Int(brightness)])
    }

    func pickScene(_ id: Int) {
        sceneId = id
        mode = .scenes
        var params: [String: Any] = ["sceneId": id, "dimming": Int(brightness)]
        if currentScene?.dynamic == true { params["speed"] = Int(speed) }
        send(params)
    }

    func setSpeed(_ value: Double) {
        speed = min(max(value.rounded(), 10), 200)
        send(["sceneId": sceneId, "speed": Int(speed)])
    }

    /// Switching tabs puts the light in that mode right away, with the values the tab shows.
    func setMode(_ newMode: Mode) {
        switch newMode {
        case .white: setTemperature(temperature)
        case .color: setColor(hue: hue, saturation: saturation)
        case .scenes: pickScene(sceneId)
        }
    }

    /// Queues setPilot parameters and sends them at most every 60 ms, so a dragged slider
    /// doesn't flood the lamp but its last position always arrives.
    private func send(_ params: [String: Any]) {
        lastInteraction = Date()
        // Only one of white, colour or scene can be active; drop queued keys of the others.
        if params["temp"] != nil { ["r", "g", "b", "sceneId", "speed"].forEach { pending[$0] = nil } }
        if params["r"] != nil { ["temp", "sceneId", "speed"].forEach { pending[$0] = nil } }
        if params["sceneId"] != nil {
            ["temp", "r", "g", "b"].forEach { pending[$0] = nil }
            if params["speed"] == nil { pending["speed"] = nil }
        }
        pending.merge(params) { $1 }
        if params["state"] == nil {
            pending["state"] = true
            isOn = true
        }
        guard !sending else { return }
        sending = true
        Task { await flush() }
    }

    private func flush() async {
        while !pending.isEmpty, let lamp = selectedLamp {
            let params = pending
            pending = [:]
            let reply = await Wiz.send(Wiz.message("setPilot", params), to: lamp.ip)
            reachable = reply != nil
            try? await Task.sleep(for: .milliseconds(60))
        }
        pending = [:]
        sending = false
        lastInteraction = Date()
    }

    // MARK: - Favorites

    func saveFavorite() {
        guard favorites.count < 8 else { return }
        var params = ["dimming": Int(brightness)]
        let name: String
        switch mode {
        case .white:
            params["temp"] = Int(temperature)
            name = "Blanco \(Int(temperature)) K"
        case .color:
            let rgb = RGB(hue: hue, saturation: saturation)
            params["r"] = rgb.r
            params["g"] = rgb.g
            params["b"] = rgb.b
            name = "Color"
        case .scenes:
            params["sceneId"] = sceneId
            if currentScene?.dynamic == true { params["speed"] = Int(speed) }
            name = currentScene?.name ?? "Escena"
        }
        favorites.append(Favorite(name: "\(name) · \(Int(brightness))%", params: params))
        saveFavorites()
    }

    func applyFavorite(_ favorite: Favorite) {
        var result: [String: Any] = favorite.params
        result["state"] = true
        apply(Pilot(result))
        send(favorite.params)
    }

    func removeFavorite(_ favorite: Favorite) {
        favorites.removeAll { $0.id == favorite.id }
        saveFavorites()
    }

    func color(for favorite: Favorite) -> Color {
        let p = favorite.params
        if let r = p["r"], let g = p["g"], let b = p["b"] { return RGB(r: r, g: g, b: b).color }
        if let id = p["sceneId"] { return Scenes.scene(id)?.tint ?? .yellow }
        return WhiteLight.color(Double(p["temp"] ?? 2700))
    }

    private func saveFavorites() {
        UserDefaults.standard.set(try? JSONEncoder().encode(favorites), forKey: "favorites")
    }

    // MARK: - Sleep timer and login item

    func sleep(afterMinutes minutes: Int?) {
        sleepTask?.cancel()
        sleepAt = nil
        guard let minutes else { return }
        sleepAt = Date().addingTimeInterval(Double(minutes * 60))
        sleepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(minutes * 60)))
            guard !Task.isCancelled else { return }
            self?.setPower(false)
            self?.sleepAt = nil
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Luz WiZ: could not change login item: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
