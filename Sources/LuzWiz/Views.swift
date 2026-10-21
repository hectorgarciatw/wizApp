import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(LampStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HeaderView()
            if store.selectedLamp == nil {
                EmptyStateView()
            } else {
                if !store.reachable { UnreachableBanner() }
                VStack(alignment: .leading, spacing: 14) {
                    BrightnessRow()
                    Picker("Modo", selection: Binding(get: { store.mode }, set: { store.setMode($0) })) {
                        ForEach(LampStore.Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    switch store.mode {
                    case .white: WhiteSection()
                    case .color: ColorSection()
                    case .scenes: ScenesSection()
                    }
                    FavoritesRow()
                }
                .opacity(store.isOn ? 1 : 0.6)
            }
            Divider()
            FooterView()
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { store.panelAppeared() }
        .onDisappear { store.panelOpen = false }
    }
}

// MARK: - Header

struct HeaderView: View {
    @Environment(LampStore.self) private var store
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(store.isOn ? store.displayColor : Color.secondary.opacity(0.15))
                    .shadow(color: store.isOn ? store.displayColor.opacity(0.7) : .clear, radius: 8)
                Image(systemName: store.isOn ? "lightbulb.fill" : "lightbulb")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(store.isOn ? Color.black.opacity(0.65) : Color.secondary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                if store.renaming {
                    TextField("Nombre", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .onAppear { draft = store.selectedLamp?.name ?? "" }
                        .onSubmit {
                            store.rename(draft)
                            store.renaming = false
                        }
                        .onExitCommand { store.renaming = false }
                } else if store.lamps.count > 1 {
                    Menu {
                        ForEach(store.lamps) { lamp in
                            Button(lamp.name) { store.select(lamp.id) }
                        }
                    } label: {
                        Text(store.selectedLamp?.name ?? "Lámpara").font(.headline)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                } else {
                    Text(store.selectedLamp?.name ?? "Luz WiZ")
                        .font(.headline)
                        .onTapGesture(count: 2) { if store.selectedLamp != nil { store.renaming = true } }
                        .help("Doble clic para renombrar")
                }
                Text(store.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Encendida", isOn: Binding(get: { store.isOn }, set: { store.setPower($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(store.selectedLamp == nil)
                .help(store.isOn ? "Apagar" : "Encender")
        }
    }
}

struct UnreachableBanner: View {
    @Environment(LampStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("La lámpara no responde. ¿Tiene corriente?")
                .font(.caption)
            Spacer()
            Button("Reintentar") { Task { await store.refresh(force: true) } }
                .controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.12)))
    }
}

struct EmptyStateView: View {
    @Environment(LampStore.self) private var store
    @State private var ip = ""
    @State private var failed = false

    var body: some View {
        VStack(spacing: 10) {
            if store.searching {
                ProgressView().controlSize(.small)
                Text("Buscando lámparas…").font(.callout).foregroundStyle(.secondary)
            } else {
                Image(systemName: "lightbulb.slash")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text("No encontré lámparas WiZ").font(.headline)
                Text("Revisá que estén con corriente y en la misma red Wi-Fi que esta Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Buscar de nuevo") { Task { await store.discover() } }
                    .buttonStyle(.borderedProminent)
                HStack {
                    TextField("o ingresá la IP, ej. 192.168.1.94", text: $ip)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Agregar", action: add).disabled(ip.isEmpty)
                }
                if failed {
                    Text("Nada respondió en esa IP.").font(.caption).foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func add() {
        Task { failed = !(await store.addManual(ip)) }
    }
}

// MARK: - Controls

struct BrightnessRow: View {
    @Environment(LampStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.min").foregroundStyle(.secondary)
            GradientSlider(value: (store.brightness - 10) / 90,
                           colors: [Color(white: 0.25), store.displayColor]) { store.setBrightness(10 + $0 * 90) }
            Image(systemName: "sun.max.fill").foregroundStyle(.secondary)
            Text("\(Int(store.brightness))%")
                .font(.callout.monospacedDigit())
                .frame(width: 40, alignment: .trailing)
        }
        .help("Brillo")
    }
}

struct WhiteSection: View {
    @Environment(LampStore.self) private var store
    private let span = WhiteLight.range.upperBound - WhiteLight.range.lowerBound

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GradientSlider(value: (store.temperature - WhiteLight.range.lowerBound) / span,
                               colors: WhiteLight.gradient) {
                    store.setTemperature(WhiteLight.range.lowerBound + $0 * span)
                }
                Text("\(Int(store.temperature)) K")
                    .font(.callout.monospacedDigit())
                    .frame(width: 58, alignment: .trailing)
            }
            HStack(spacing: 6) {
                ForEach(WhiteLight.presets, id: \.kelvin) { preset in
                    Chip(title: preset.name, color: WhiteLight.color(preset.kelvin),
                         selected: abs(store.temperature - preset.kelvin) < 60) {
                        store.setTemperature(preset.kelvin)
                    }
                }
            }
        }
    }
}

struct ColorSection: View {
    @Environment(LampStore.self) private var store
    private let swatches: [(hue: Double, saturation: Double)] = [
        (0, 1), (0.07, 1), (0.13, 1), (0.33, 1), (0.5, 1), (0.62, 1), (0.77, 1), (0.9, 0.8),
        (0.97, 0.45), (0.08, 0.5), (0.55, 0.4), (0, 0),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "paintpalette").foregroundStyle(.secondary).frame(width: 18)
                GradientSlider(value: store.hue,
                               colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6).map {
                                   Color(hue: $0, saturation: 1, brightness: 1)
                               }) { store.setColor(hue: $0, saturation: store.saturation) }
            }
            .help("Tono")
            HStack {
                Image(systemName: "drop.halffull").foregroundStyle(.secondary).frame(width: 18)
                GradientSlider(value: store.saturation,
                               colors: [.white, Color(hue: store.hue, saturation: 1, brightness: 1)]) {
                    store.setColor(hue: store.hue, saturation: $0)
                }
            }
            .help("Intensidad del color")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 8) {
                ForEach(swatches.indices, id: \.self) { index in
                    let swatch = swatches[index]
                    let selected = store.mode == .color
                        && abs(store.hue - swatch.hue) < 0.01 && abs(store.saturation - swatch.saturation) < 0.01
                    Button {
                        store.setColor(hue: swatch.hue, saturation: swatch.saturation)
                    } label: {
                        Circle()
                            .fill(RGB(hue: swatch.hue, saturation: swatch.saturation).color)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.9 : 0.15),
                                                           lineWidth: selected ? 2.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ScenesSection: View {
    @Environment(LampStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(Scenes.all) { scene in
                        SceneTile(scene: scene, selected: store.sceneId == scene.id) { store.pickScene(scene.id) }
                    }
                }
                .padding(2)
            }
            .frame(height: 216)
            if store.currentScene?.dynamic == true {
                HStack {
                    Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                    GradientSlider(value: (store.speed - 10) / 190,
                                   colors: [Color(white: 0.3), store.displayColor]) { store.setSpeed(10 + $0 * 190) }
                    Image(systemName: "hare.fill").foregroundStyle(.secondary)
                }
                .help("Velocidad de la animación")
            }
        }
    }
}

struct SceneTile: View {
    let scene: LightScene
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: scene.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(scene.tint)
                Text(scene.name)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 9).fill(scene.tint.opacity(selected ? 0.3 : 0.1)))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(selected ? scene.tint : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct FavoritesRow: View {
    @Environment(LampStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Favoritos").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(store.favorites) { favorite in
                    Button { store.applyFavorite(favorite) } label: {
                        Circle()
                            .fill(store.color(for: favorite))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                    .help(favorite.name)
                    .contextMenu {
                        Button("Eliminar “\(favorite.name)”", role: .destructive) { store.removeFavorite(favorite) }
                    }
                }
                if store.favorites.count < 8 {
                    Button { store.saveFavorite() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [3])))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Guardar la luz actual como favorito (clic derecho en uno para borrarlo)")
                }
            }
        }
    }
}

// MARK: - Footer

struct FooterView: View {
    @Environment(LampStore.self) private var store

    var body: some View {
        HStack {
            Menu {
                ForEach([15, 30, 60, 120], id: \.self) { minutes in
                    Button(minutes < 60 ? "En \(minutes) minutos" : "En \(minutes / 60) h") {
                        store.sleep(afterMinutes: minutes)
                    }
                }
                if store.sleepAt != nil {
                    Divider()
                    Button("Cancelar temporizador") { store.sleep(afterMinutes: nil) }
                }
            } label: {
                Label(store.sleepAt.map { "Se apaga \($0.formatted(date: .omitted, time: .shortened))" } ?? "Apagar en…",
                      systemImage: "timer")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(store.selectedLamp == nil)

            Spacer()

            if store.searching { ProgressView().controlSize(.small) }

            Menu {
                Button("Buscar lámparas") { Task { await store.discover() } }
                Button("Renombrar lámpara") { store.renaming = true }
                    .disabled(store.selectedLamp == nil)
                Button("Olvidar esta lámpara") { store.forgetSelected() }
                    .disabled(store.selectedLamp == nil)
                Toggle("Abrir al iniciar sesión",
                       isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                Divider()
                Section("Lámpara") {
                    Toggle("Más cálida al bajar el brillo",
                           isOn: Binding(get: { store.dimToWarm }, set: { store.setDimToWarm($0) }))
                    Toggle("Encendido y apagado suaves",
                           isOn: Binding(get: { store.softFade }, set: { store.setSoftFade($0) }))
                    Toggle("Colores suaves con LED blanco",
                           isOn: Binding(get: { store.softWhites }, set: { store.setSoftWhites($0) }))
                }
                if let lamp = store.selectedLamp {
                    Divider()
                    Text("IP: \(lamp.ip)")
                    Text("Señal Wi-Fi: \(store.signalText)")
                    Text("Firmware: \(lamp.firmware ?? "—")")
                    Text("MAC: \(lamp.id)")
                }
                Divider()
                Button("Salir de Luz WiZ") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

// MARK: - Building blocks

/// A capsule slider whose track is a gradient; `onChange` fires only for the user's drags,
/// so state read back from the lamp moves the thumb without sending anything.
struct GradientSlider: View {
    let value: Double
    let colors: [Color]
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .frame(width: height - 4, height: height - 4)
                    .offset(x: 2 + CGFloat(min(max(value, 0), 1)) * (width - height))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                onChange(min(max((drag.location.x - height / 2) / (width - height), 0), 1))
            })
        }
        .frame(height: 20)
    }
}

struct Chip: View {
    let title: String
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(title).font(.system(size: 11))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Color.primary.opacity(selected ? 0.16 : 0.06)))
            .overlay(Capsule().strokeBorder(selected ? Color.primary.opacity(0.5) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
