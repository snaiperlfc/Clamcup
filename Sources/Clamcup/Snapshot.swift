import AppKit
import ClamcupCore
import SwiftUI

/// Рендер панели в PNG для README и визуальной проверки без снимка экрана:
/// `Clamcup --snapshot <каталог>`. Язык задаётся как обычно: `-AppleLanguages '(ru)'`.
@MainActor
enum Snapshot {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let language = Bundle.main.preferredLocalizations.first ?? "en"

        let scenarios: [(name: String, state: DeviceState)] = [
            ("awake", DeviceState(onAC: true, lidClosed: false, sleepDisabled: true, mode: .auto, helper: .running)),
            ("battery", DeviceState(onAC: false, lidClosed: false, sleepDisabled: false, mode: .auto, helper: .running)),
            ("setup", DeviceState(onAC: true, lidClosed: false, sleepDisabled: false, mode: .auto, helper: .notInstalled)),
        ]
        let appearances: [(name: String, appearance: NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

        for scenario in scenarios {
            for look in appearances {
                let model = StatusModel(preview: scenario.state, launchAtLogin: true)
                let view = PanelView(model: model).background(Color(nsColor: .windowBackgroundColor))
                let url = directory.appendingPathComponent("panel-\(scenario.name)-\(language)-\(look.name).png")
                write(view, appearance: look.appearance, to: url)
            }
        }
    }

    /// Окно не на экране и не ключевое, поэтому переключатели и кнопки выходят серыми,
    /// как в неактивном окне. Для живых цветов нужен настоящий снимок экрана.
    private static func write(_ view: some View, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: appearance)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)

        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
