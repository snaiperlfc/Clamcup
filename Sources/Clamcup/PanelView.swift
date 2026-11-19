import AppKit
import ClamcupCore
import SwiftUI

/// Панель, которая открывается по щелчку на значок в строке меню.
struct PanelView: View {
    let model: StatusModel
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(headline: model.headline)
                .padding(.bottom, 14)

            if let kind = HelperCard.Kind(model.device.helper) {
                HelperCard(kind: kind, action: model.installHelper)
                    .padding(.bottom, 14)
            }

            StayAwakeRow(isOn: Binding(get: { model.stayAwake }, set: { model.setStayAwake($0) }))
                .disabled(!model.canChangeMode)

            Divider().padding(.vertical, 12)

            StatusList(device: model.device)

            Divider().padding(.vertical, 12)

            Toggle(
                "Launch at login",
                isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })
            )
            .toggleStyle(.checkbox)

            Divider().padding(.vertical, 12)

            FooterView(model: model)
        }
        .padding(16)
        .frame(width: 300)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .background(WindowHeightFitter(contentHeight: contentHeight))
        .onAppear { model.refresh() }
    }
}

/// Окно MenuBarExtra растёт вместе с содержимым, но само не сжимается. Когда пропадает
/// карточка службы, сверху оставалась пустая полоса. Подгоняем высоту окна под содержимое,
/// верхний край остаётся на месте под строкой меню.
private struct WindowHeightFitter: NSViewRepresentable {
    let contentHeight: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let height = contentHeight
        // Меняем окно после текущего прохода раскладки SwiftUI, а не посреди него
        Task { @MainActor [weak view] in
            guard height > 0, let window = view?.window else { return }
            var frame = window.frame
            let delta = height - window.contentRect(forFrameRect: frame).height
            guard abs(delta) > 0.5 else { return }
            frame.origin.y -= delta
            frame.size.height += delta
            window.setFrame(frame, display: true)
        }
    }
}

private struct HeaderView: View {
    let headline: Headline

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(symbolStyle)
                .frame(width: 36, height: 36)
                .background(Circle().fill(badgeStyle))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Clamcup")
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch headline {
        case .awake: "cup.and.heat.waves.fill"
        case .needsHelper, .helperStopped: "exclamationmark.triangle.fill"
        case .checking, .onBattery, .off, .applying: "cup.and.saucer.fill"
        }
    }

    private var badgeStyle: AnyShapeStyle {
        switch headline {
        case .awake: AnyShapeStyle(Color.orange)
        case .needsHelper, .helperStopped: AnyShapeStyle(Color.yellow)
        case .checking, .onBattery, .off, .applying: AnyShapeStyle(.quaternary)
        }
    }

    private var symbolStyle: AnyShapeStyle {
        switch headline {
        case .awake: AnyShapeStyle(Color.white)
        case .needsHelper, .helperStopped: AnyShapeStyle(Color.black.opacity(0.75))
        case .checking, .onBattery, .off, .applying: AnyShapeStyle(.secondary)
        }
    }

    private var subtitle: LocalizedStringKey {
        switch headline {
        case .checking: "Checking…"
        case .awake: "Stays awake, even with the lid closed"
        case .onBattery: "On battery: normal sleep"
        case .off: "Off: normal sleep"
        case .applying: "Applying…"
        case .needsHelper: "Helper required"
        case .helperStopped: "Helper isn't running"
        }
    }
}

private struct HelperCard: View {
    enum Kind {
        case install, update, reinstall

        init?(_ state: HelperState) {
            switch state {
            case .notInstalled: self = .install
            case .outdated: self = .update
            case .stopped: self = .reinstall
            case .checking, .running: return nil
            }
        }
    }

    let kind: Kind
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.5)))
    }

    private var title: LocalizedStringKey {
        switch kind {
        case .install: "Install the helper"
        case .update: "Update the helper"
        case .reinstall: "The helper isn't running"
        }
    }

    private var message: LocalizedStringKey {
        switch kind {
        case .install: "Only a system helper can turn off sleep. macOS will ask for an administrator password."
        case .update: "This version of Clamcup comes with a newer helper."
        case .reinstall: "Reinstalling it usually helps."
        }
    }

    private var buttonTitle: LocalizedStringKey {
        switch kind {
        case .install: "Install Helper…"
        case .update: "Update Helper…"
        case .reinstall: "Reinstall Helper…"
        }
    }
}

private struct StayAwakeRow: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Stay awake on power")
                Text("Even with the lid closed. On battery your Mac sleeps as usual.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("Stay awake on power", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct StatusList: View {
    let device: DeviceState

    var body: some View {
        VStack(spacing: 8) {
            StatusRow(
                symbol: device.onAC ? "powerplug.fill" : "battery.75percent",
                title: "Power",
                value: device.onAC ? "Adapter" : "Battery"
            )
            StatusRow(symbol: "laptopcomputer", title: "Lid", value: device.lidClosed ? "Closed" : "Open")
            StatusRow(symbol: "moon.zzz.fill", title: "Sleep", value: device.sleepDisabled ? "Turned off" : "Normal")
        }
    }
}

private struct StatusRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let value: LocalizedStringKey

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

private struct FooterView: View {
    let model: StatusModel

    var body: some View {
        HStack(spacing: 14) {
            Button("About Clamcup", action: model.showAbout)
            Spacer()
            Menu {
                Button("Open Log", action: model.openLog)
                if model.device.helper != .notInstalled {
                    Divider()
                    Button("Uninstall Helper…", role: .destructive, action: model.uninstallHelper)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel(Text("More"))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .font(.callout)
    }
}
