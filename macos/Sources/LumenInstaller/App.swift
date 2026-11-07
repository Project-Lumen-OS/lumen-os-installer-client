import SwiftUI
import AppKit


struct LumenInstallerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Lumen Installer") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1040, minHeight: 680)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

struct RootView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        ZStack {
            SkyBackground()
            if m.mode == nil {
                WelcomeView()
            } else {
                HStack(spacing: 0) {
                    SidebarView().frame(width: 248)
                    Divider().overlay(Theme.line)
                    ScrollView {
                        Group {
                            switch m.step {
                            case .prepare: PrepareStepView()
                            case .device: DeviceStepView()
                            case .system: SystemStepView()
                            case .google: GoogleStepView()
                            case .install: InstallStepView()
                            }
                        }
                        .frame(maxWidth: 860)
                        .padding(.horizontal, 40).padding(.top, 44).padding(.bottom, 40)
                        .frame(maxWidth: .infinity)
                    }
                    if m.mode == .demo {
                        Divider().overlay(Theme.line)
                        DemoProjectorPanel().frame(width: 290)
                    }
                }
            }
            if let b = m.busy { BusyOverlay(text: b, progress: m.busyProgress) }
        }
        .id(m.lang)
        .environment(\.openURL, OpenURLAction { url in NSWorkspace.shared.open(url); return .handled })
        .sheet(item: $m.prompt) { p in PromptSheet(prompt: p).environmentObject(m) }
        .alert(L("Ошибка"), isPresented: Binding(get: { m.error != nil }, set: { if !$0 { m.error = nil } })) {
            Button("OK") { m.error = nil }
        } message: { Text(m.error ?? "") }
    }
}

struct BusyOverlay: View {
    let text: String
    let progress: Double?
    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                if let progress { ProgressBar(value: progress).frame(width: 320) } else { ProgressView().controlSize(.large) }
                Text(text).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.08, green: 0.1, blue: 0.22)))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.line2))
        }
    }
}
