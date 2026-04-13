import Cocoa
import Carbon
import SwiftUI
import ServiceManagement

private func applicationSwitchedCallback(_ axObserver: AXObserver, axElement: AXUIElement, notification: CFString, userData: UnsafeMutableRawPointer?) {
    if let userData = userData {
        let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
        appDelegate.applicationSwitched()
    }
}

private func hasAccessibilityPermission() -> Bool {
    let promptFlag = kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString
    let myDict: CFDictionary = NSDictionary(dictionary: [promptFlag: false])
    return AXIsProcessTrustedWithOptions(myDict)
}

private func askForAccessibilityPermission() {
    let alert = NSAlert()
    alert.messageText = "SwitchKey 需要辅助功能权限。"
    alert.informativeText = "请在系统设置的“隐私与安全性 -> 辅助功能”中允许 SwitchKey 控制您的电脑。授权后请重新启动应用。"
    alert.addButton(withTitle: "去设置")
    alert.addButton(withTitle: "退出")
    alert.alertStyle = .warning

    if alert.runModal() == .alertFirstButtonReturn {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            let bundleIds = ["com.apple.systemsettings", "com.apple.systempreferences"]
            for bundleId in bundleIds {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                    app.activate(options: .activateIgnoringOtherApps)
                    break
                }
            }
        }
        NSApplication.shared.terminate(nil)
    } else {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Models and ViewModel

struct ConditionItem: Identifiable {
    let id = UUID()
    var applicationIdentifier: String
    var applicationName: String
    var applicationIcon: NSImage
    var inputSourceID: String
    var inputSourceIcon: NSImage
    var enabled: Bool
}

class SettingsViewModel: ObservableObject {
    static let shared = SettingsViewModel()
    
    @Published var conditionItems: [ConditionItem] = []
    @Published var launchAtStartup: Bool = SMAppService.mainApp.status == .enabled
    @Published var selectableInputSources: [InputSourceInfo] = []
    @Published var defaultInputSourceID: String = ""

    func toggleLaunchAtStartup() {
        do {
            if launchAtStartup {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchAtStartup = SMAppService.mainApp.status == .enabled
        } catch {
            print("Failed to change login item: \(error)")
        }
    }
    
    func addRunningAppIfNeeded(_ app: NSRunningApplication) {
        let bundleId = app.bundleIdentifier ?? ""
        guard !bundleId.isEmpty else { return }
        
        // Dispatch to main thread if not already, to update @Published properties
        DispatchQueue.main.async {
            if !self.conditionItems.contains(where: { $0.applicationIdentifier == bundleId }) {
                let inputSource = InputSource.current()
                let item = ConditionItem(
                    applicationIdentifier: bundleId,
                    applicationName: app.localizedName ?? "",
                    applicationIcon: app.icon ?? NSImage(),
                    inputSourceID: inputSource.inputSourceID(),
                    inputSourceIcon: inputSource.icon(),
                    enabled: false
                )
                self.conditionItems.append(item)
                self.saveConditions()
            }
        }
    }
    
    func addAppWithPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            let bundle = Bundle(url: url)
            let identifier = bundle?.bundleIdentifier ?? ""
            guard !identifier.isEmpty else { return }

            let name = FileManager.default.displayName(atPath: url.path)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            
            if let index = conditionItems.firstIndex(where: { $0.applicationIdentifier == identifier }) {
                conditionItems[index].inputSourceID = defaultInputSourceID
                if let isrc = InputSource.with(defaultInputSourceID) {
                    conditionItems[index].inputSourceIcon = isrc.icon()
                }
                saveConditions()
                return
            }

            let item = ConditionItem(
                applicationIdentifier: identifier,
                applicationName: name,
                applicationIcon: icon,
                inputSourceID: defaultInputSourceID,
                inputSourceIcon: InputSource.with(defaultInputSourceID)?.icon() ?? NSImage(),
                enabled: true
            )
            
            conditionItems.insert(item, at: 0)
            saveConditions()
        }
    }
    
    func removeCondition(at offsets: IndexSet) {
        conditionItems.remove(atOffsets: offsets)
        saveConditions()
    }
    
    func removeCondition(_ item: ConditionItem) {
        if let index = conditionItems.firstIndex(where: { $0.id == item.id }) {
            conditionItems.remove(at: index)
            saveConditions()
        }
    }

    func loadConditions() {
        self.selectableInputSources = InputSource.allSelectable()

        // 优先从持久化读取；若没有则用当前输入法兜底
        let saved = UserDefaults.standard.string(forKey: "DefaultInputSourceID") ?? ""
        if !saved.isEmpty && self.selectableInputSources.contains(where: { $0.id == saved }) {
            self.defaultInputSourceID = saved
        } else {
            let currentID = InputSource.current().inputSourceID()
            self.defaultInputSourceID = !currentID.isEmpty ? currentID : (self.selectableInputSources.first?.id ?? "")
        }

        if let conditions = UserDefaults.standard.array(forKey: "Conditions") as? [[String:Any]] {
            var items: [ConditionItem] = []
            for c in conditions {
                if let inputSource = InputSource.with(c["InputSourceID"] as! String) {
                    let appIconData = c["ApplicationIcon"] as? Data
                    let icon = appIconData != nil ? NSImage(data: appIconData!) ?? NSImage() : NSImage()
                    
                    let item = ConditionItem(
                        applicationIdentifier: c["ApplicationIdentifier"] as! String,
                        applicationName: c["ApplicationName"] as! String,
                        applicationIcon: icon,
                        inputSourceID: inputSource.inputSourceID(),
                        inputSourceIcon: inputSource.icon(),
                        enabled: c["Enabled"] as! Bool
                    )
                    items.append(item)
                }
            }
            self.conditionItems = items
        }
    }

    func saveConditions() {
        UserDefaults.standard.set(defaultInputSourceID, forKey: "DefaultInputSourceID")
        var conditions: [[String: Any]] = []
        for item in conditionItems {
            var c:[String:Any] = [:]
            c["ApplicationIdentifier"] = item.applicationIdentifier
            c["InputSourceID"] = item.inputSourceID
            c["Enabled"] = item.enabled
            c["ApplicationName"] = item.applicationName
            
            if let cgRef = item.applicationIcon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let pngData = NSBitmapImageRep(cgImage: cgRef)
                pngData.size = item.applicationIcon.size
                if let data = pngData.representation(using: .png, properties: [:]) {
                    c["ApplicationIcon"] = data
                }
            }
            conditions.append(c)
        }
        UserDefaults.standard.set(conditions, forKey: "Conditions")
    }
}

// MARK: - SwiftUI Views

struct ContentView: View {
    @StateObject private var viewModel = SettingsViewModel.shared

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.conditionItems.isEmpty {
                Text("尚未添加任何应用映射")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 60)
            } else {
                // 列标题行
                HStack(spacing: 4) {
                    Color.clear.frame(width: 20)
                    Text("程序名称")
                        .font(.caption)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("输入法")
                        .font(.caption)
                        .foregroundColor(.primary)
                        .frame(width: 90, alignment: .leading)
                    Color.clear.frame(width: 46)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach($viewModel.conditionItems) { $item in
                            HStack(spacing: 4) {
                                Image(nsImage: item.applicationIcon)
                                    .resizable()
                                    .frame(width: 18, height: 18)

                                Text(item.applicationName)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Picker("", selection: Binding(
                                    get: { item.inputSourceID },
                                    set: { newID in
                                        item.inputSourceID = newID
                                        if let isrc = InputSource.with(newID) {
                                            item.inputSourceIcon = isrc.icon()
                                        }
                                        viewModel.saveConditions()
                                    }
                                )) {
                                    ForEach(viewModel.selectableInputSources) { source in
                                        Text(source.name).tag(source.id)
                                    }
                                }
                                .labelsHidden()
                                .controlSize(.small)
                                .frame(width: 90)

                                Toggle("", isOn: Binding(
                                    get: { item.enabled },
                                    set: { newValue in
                                        item.enabled = newValue
                                        viewModel.saveConditions()
                                    }
                                ))
                                .labelsHidden()
                                .scaleEffect(0.8)
                                .frame(width: 26)

                                Button(action: {
                                    viewModel.removeCondition(item)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)

                            Divider()
                                .padding(.horizontal, 10)
                        }
                    }
                }
                .frame(height: 260)
                .background(Color(NSColor.controlBackgroundColor))
            }

            Divider()

            HStack {
                Text("默认输入法")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: Binding(
                    get: { viewModel.defaultInputSourceID },
                    set: { newVal in
                        viewModel.defaultInputSourceID = newVal
                        UserDefaults.standard.set(newVal, forKey: "DefaultInputSourceID")
                    }
                )) {
                    ForEach(viewModel.selectableInputSources) { source in
                        Text(source.name).tag(source.id)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 90)

                Button(action: {
                    viewModel.addAppWithPicker()
                }) {
                    Text("添加")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderless)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(5)

                Spacer()

                Toggle("开机自启", isOn: Binding(
                    get: { viewModel.launchAtStartup },
                    set: { _ in viewModel.toggleLaunchAtStartup() }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.caption)
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(width: 320)
    }
}

// MARK: - App Entry Point

@main
struct SwitchKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra("SwitchKey", image: "StatusIcon") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var applicationObservers:[pid_t:AXObserver] = [:]
    private var currentPid:pid_t = getpid()
    private var pendingSwitchTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if !hasAccessibilityPermission() {
            askForAccessibilityPermission()
        }

        SettingsViewModel.shared.loadConditions()

        let workspace = NSWorkspace.shared
        workspace.notificationCenter.addObserver(self, selector: #selector(applicationLaunched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: workspace)
        workspace.notificationCenter.addObserver(self, selector: #selector(applicationTerminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: workspace)

        for application in workspace.runningApplications {
            if application.activationPolicy == .regular {
                SettingsViewModel.shared.addRunningAppIfNeeded(application)
            }
            registerForAppSwitchNotification(application.processIdentifier)
        }

        applicationSwitched()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for (_, observer) in applicationObservers {
            CFRunLoopRemoveSource(RunLoop.current.getCFRunLoop(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
    }

    fileprivate func applicationSwitched() {
        pendingSwitchTask?.cancel()
        pendingSwitchTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                return
            }
            
            guard !Task.isCancelled else { return }
            
            if let application = NSWorkspace.shared.frontmostApplication {
                let switchedPid:pid_t = application.processIdentifier
                if (switchedPid != self.currentPid && switchedPid != getpid()) {
                    for condition in SettingsViewModel.shared.conditionItems {
                        if !condition.enabled {
                            continue
                        }
                        if condition.applicationIdentifier == application.bundleIdentifier {
                            if let inputSource = InputSource.with(condition.inputSourceID) {
                                inputSource.activate()
                            }
                            break
                        }
                    }
                    self.currentPid = switchedPid
                }
            }
        }
    }

    @objc private func applicationLaunched(_ notification: NSNotification) {
        let pid = notification.userInfo!["NSApplicationProcessIdentifier"] as! pid_t
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
            SettingsViewModel.shared.addRunningAppIfNeeded(app)
        }
        registerForAppSwitchNotification(pid)
        applicationSwitched()
    }

    @objc private func applicationTerminated(_ notification: NSNotification) {
        let pid = notification.userInfo!["NSApplicationProcessIdentifier"] as! pid_t
        if let observer = applicationObservers[pid] {
            CFRunLoopRemoveSource(RunLoop.current.getCFRunLoop(), AXObserverGetRunLoopSource(observer), .defaultMode)
            applicationObservers.removeValue(forKey: pid)
        }
    }

    private func registerForAppSwitchNotification(_ pid: pid_t) {
        if pid != getpid() {
            if applicationObservers[pid] == nil {
                var observer: AXObserver!
                guard AXObserverCreate(pid, applicationSwitchedCallback, &observer) == .success else {
                    return
                }
                CFRunLoopAddSource(RunLoop.current.getCFRunLoop(), AXObserverGetRunLoopSource(observer), .defaultMode)

                let element = AXUIElementCreateApplication(pid)
                let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
                AXObserverAddNotification(observer, element, NSAccessibility.Notification.applicationActivated.rawValue as CFString, selfPtr)
                applicationObservers[pid] = observer
            }
        }
    }
}
