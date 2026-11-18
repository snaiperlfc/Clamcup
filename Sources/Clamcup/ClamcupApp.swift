import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = StatusModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) {
            Snapshot.render(to: URL(fileURLWithPath: arguments[index + 1]))
            exit(0)
        }
        model.start()
    }
}

@main
struct ClamcupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: appDelegate.model)
        } label: {
            MenuBarIcon(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Отдельное представление, чтобы значок перерисовывался при смене состояния модели.
private struct MenuBarIcon: View {
    let model: StatusModel

    var body: some View {
        Image(systemName: model.menuBarSymbol)
            .accessibilityLabel(Text(verbatim: "Clamcup"))
    }
}
