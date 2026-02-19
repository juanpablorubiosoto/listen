import SwiftUI
import AppKit
import AVFoundation
import CoreGraphics
import CoreAudio

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

enum ModelSize: String, CaseIterable, Identifiable {
    case small = "small"
    case medium = "medium"
    var id: String { rawValue }
    var filename: String { "ggml-\(rawValue).bin" }
    var displayName: String { rawValue.capitalized }
}

enum Language: String, CaseIterable, Identifiable {
    case auto = "auto"
    case es = "es"
    case en = "en"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .es: return "Español"
        case .en: return "English"
        }
    }
}

final class AppState: ObservableObject {
    struct AudioDevice: Identifiable, Hashable {
        let id: String
        let index: Int
        let name: String
    }

    @Published var deviceIndex: String = ""
    @Published var status: String = "Listo."
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var lastAudioPath: String = ""
    @Published var lastTranscriptPath: String = ""
    @Published var baseName: String = ""
    @Published var appendDate: Bool = true
    @Published var selectedModel: ModelSize = .medium
    @Published var selectedLanguage: Language = .auto
    @Published var recordingProcess: Process? = nil
    @Published var downloadStatus: String = ""
    @Published var audioDevices: [AudioDevice] = []
    @Published var selectedDeviceId: String = ""
    @Published var includeMicrophone: Bool = false
    @Published var lastWhisperLog: String = ""
    @Published var useGpu: Bool = false
    @Published var showFilePicker: Bool = false
    @Published var hasDetectedDevices: Bool = false
    @Published var pendingMicSwitch: Bool = false
    @Published var micPermissionGranted: Bool = false
    @Published var screenPermissionGranted: Bool = false
    @Published var outputFolderPath: String = ""
    @Published var showFolderPicker: Bool = false
    @Published var selectedTab: String = "Principal"
    @Published var showSetupWizard: Bool = false

    func activeDeviceLabel() -> String {
        if let selected = audioDevices.first(where: { $0.id == selectedDeviceId }) {
            return "[\(selected.index)] \(selected.name)"
        }
        if let index = Int(deviceIndex) {
            return "[\(index)]"
        }
        return "No seleccionado"
    }

    func syncSelectionFromIndex() {
        guard let index = Int(deviceIndex) else { return }
        if let match = audioDevices.first(where: { $0.index == index }) {
            selectedDeviceId = match.id
        }
    }

    func modelExists() -> Bool {
        let fileName = selectedModel.filename
        let target = modelFolderURL().appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: target.path)
    }

    func refreshPermissions() {
        micPermissionGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        screenPermissionGranted = CGPreflightScreenCaptureAccess()
    }

    func refreshRecordingState() {
        isRecording = (recordingProcess != nil)
    }

    func saveOutputFolderPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: "outputFolderPath")
    }

    func loadOutputFolderPath() -> String {
        UserDefaults.standard.string(forKey: "outputFolderPath") ?? ""
    }

    func outputFolderURL() -> URL {
        let folder: URL
        if !outputFolderPath.isEmpty {
            folder = URL(fileURLWithPath: outputFolderPath)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            folder = home.appendingPathComponent("Downloads/Transcripts")
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func modelFolderURL() -> URL {
        let folder = outputFolderURL().appendingPathComponent("models")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func bundledBinary(_ name: String) -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("bin/")
            .appendingPathComponent(name)
    }

    func detectBlackHole() {
        guard let ffmpeg = bundledBinary("ffmpeg") else {
            status = "No se encontró ffmpeg dentro de la app."
            return
        }
        status = "Detectando dispositivos..."
        DispatchQueue.global(qos: .userInitiated).async {
            let output = self.runProcess(executable: ffmpeg, args: [
                "-f", "avfoundation",
                "-list_devices", "true",
                "-i", ""
            ])
            let devices = self.parseAudioDevices(output: output)
            let index = devices.first(where: { $0.name.contains("BlackHole 2ch") })?.index
            DispatchQueue.main.async {
                self.audioDevices = devices
                if let selected = devices.first(where: { $0.index == index }) {
                    self.selectedDeviceId = selected.id
                }
                if self.includeMicrophone {
                    self.switchDeviceForMic(enabled: true)
                }
                if !devices.isEmpty {
                    self.hasDetectedDevices = true
                }
                if let index = index {
                    self.deviceIndex = String(index)
                    self.status = "BlackHole 2ch encontrado en índice \(index)."
                } else {
                    self.status = "No encontré BlackHole 2ch. Revisa Audio MIDI Setup."
                }
            }
        }
    }

    func listAudioDevices() {
        guard let ffmpeg = bundledBinary("ffmpeg") else {
            status = "No se encontró ffmpeg dentro de la app."
            return
        }
        status = "Listando dispositivos..."
        DispatchQueue.global(qos: .userInitiated).async {
            let output = self.runProcess(executable: ffmpeg, args: [
                "-f", "avfoundation",
                "-list_devices", "true",
                "-i", ""
            ])
            let devices = self.parseAudioDevices(output: output)
            DispatchQueue.main.async {
                self.audioDevices = devices
                if let first = devices.first {
                    self.selectedDeviceId = first.id
                }
                if self.includeMicrophone {
                    self.switchDeviceForMic(enabled: true)
                }
                if self.pendingMicSwitch {
                    self.pendingMicSwitch = false
                    self.switchDeviceForMic(enabled: self.includeMicrophone)
                }
                if !devices.isEmpty {
                    self.hasDetectedDevices = true
                }
                self.status = devices.isEmpty ? "No pude listar dispositivos." : "Dispositivos listados."
            }
        }
    }

    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.micPermissionGranted = granted
                self.status = granted ? "Permiso de micrófono concedido." : "Permiso de micrófono denegado."
            }
        }
    }

    func requestScreenRecordingPermission() {
        let hasAccess = CGPreflightScreenCaptureAccess()
        if hasAccess {
            screenPermissionGranted = true
            status = "Permiso de grabación de pantalla ya concedido."
            return
        }
        let granted = CGRequestScreenCaptureAccess()
        screenPermissionGranted = granted
        status = granted ? "Permiso de grabación de pantalla concedido." : "Permiso de grabación de pantalla denegado."
        if !granted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func startRecording() {
        guard let ffmpeg = bundledBinary("ffmpeg") else {
            status = "No se encontró ffmpeg dentro de la app."
            return
        }
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let safeBase = sanitizeBaseName(baseName.isEmpty ? "meeting" : baseName)
        let name = appendDate ? "\(safeBase)-\(timestamp)" : safeBase
        let audioURL = outputFolderURL().appendingPathComponent("\(name).wav")
        lastAudioPath = audioURL.path

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-f", "avfoundation",
            "-i", ":\(deviceIndex)",
            "-ar", "16000",
            "-ac", "1",
            audioURL.path
        ]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        do {
            try process.run()
            recordingProcess = process
            isRecording = true
            status = "Grabando..."
        } catch {
            status = "Error al iniciar grabación: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        if let process = recordingProcess {
            process.terminate()
        }
        recordingProcess = nil
        isRecording = false
        status = "Grabación detenida."
    }

    func transcribeLastAudio() {
        guard let whisper = bundledBinary("whisper-cli") else {
            status = "No se encontró whisper-cli dentro de la app."
            return
        }
        let modelURL = modelFolderURL().appendingPathComponent(selectedModel.filename)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            status = "Modelo no encontrado. Usa 'Descargar modelo'."
            return
        }
        let baseNamePath = URL(fileURLWithPath: lastAudioPath).deletingPathExtension().path
        let outputBase = baseNamePath + "-transcript"
        lastTranscriptPath = outputBase + ".txt"

        var args = [
            "-m", modelURL.path,
            "-f", lastAudioPath,
            "-otxt",
            "-of", outputBase
        ]
        if !useGpu {
            args.append("-ng")
        }
        if selectedLanguage != .auto {
            args += ["-l", selectedLanguage.rawValue]
        }

        isTranscribing = true
        status = "Transcribiendo..."
        DispatchQueue.global(qos: .userInitiated).async {
            let output = self.runProcess(executable: whisper, args: args)
            DispatchQueue.main.async {
                self.isTranscribing = false
                self.lastWhisperLog = output.isEmpty ? "Sin salida de whisper." : output
                self.status = "Transcripción lista."
            }
        }
    }

    func downloadModel() {
        let fileName = selectedModel.filename
        let target = modelFolderURL().appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: target.path) {
            downloadStatus = "El modelo ya existe: \(fileName)"
            return
        }

        guard let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)") else {
            downloadStatus = "URL inválida para descargar el modelo."
            return
        }

        downloadStatus = "Descargando \(fileName)..."
        let task = URLSession.shared.downloadTask(with: url) { tempURL, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.downloadStatus = "Error: \(error.localizedDescription)"
                    return
                }
                guard let tempURL = tempURL else {
                    self.downloadStatus = "Descarga falló."
                    return
                }
                do {
                    try FileManager.default.moveItem(at: tempURL, to: target)
                    self.downloadStatus = "Modelo listo: \(fileName)"
                } catch {
                    self.downloadStatus = "No pude guardar el modelo: \(error.localizedDescription)"
                }
            }
        }
        task.resume()
    }

    func openOutputFolder() {
        NSWorkspace.shared.open(outputFolderURL())
    }

    func isBlackHoleInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver")
    }

    func hasCoreAudioDevice(matching keywords: [String]) -> Bool {
        let names = coreAudioDeviceNames()
        return names.contains { name in
            keywords.contains { name.localizedCaseInsensitiveContains($0) }
        }
    }

    func openBundledBlackHoleInstaller() {
        if let url = Bundle.main.url(forResource: "BlackHole2ch", withExtension: "pkg") {
            NSWorkspace.shared.open(url)
            status = "Abriendo instalador de BlackHole..."
        } else {
            status = "No encontré BlackHole2ch.pkg dentro de la app."
        }
    }

    func openDonate() {
        if let url = URL(string: "https://www.paypal.com/donate/?hosted_button_id=4MGT8CYJ4BJZG") {
            NSWorkspace.shared.open(url)
        }
    }

    func runProcess(executable: URL, args: [String]) -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func parseBlackHoleIndex(output: String) -> Int? {
        let lines = output.split(separator: "\n")
        for line in lines {
            if line.contains("BlackHole 2ch") {
                let pattern = "\\[(\\d+)\\]"
                if let match = line.range(of: pattern, options: .regularExpression) {
                    let value = String(line[match])
                    let digits = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    return Int(digits)
                }
            }
        }
        return nil
    }

    func parseAudioDevices(output: String) -> [AudioDevice] {
        let lines = output.split(separator: "\n")
        var inAudioSection = false
        var devices: [AudioDevice] = []
        for lineSub in lines {
            let line = String(lineSub)
            if line.contains("AVFoundation audio devices") {
                inAudioSection = true
                continue
            }
            if line.contains("AVFoundation video devices") {
                inAudioSection = false
                continue
            }
            if inAudioSection {
                let pattern = "\\[(\\d+)\\] (.+)$"
                if let range = line.range(of: pattern, options: .regularExpression) {
                    let match = String(line[range])
                    let parts = match.split(separator: "]", maxSplits: 1, omittingEmptySubsequences: true)
                    if parts.count == 2 {
                        let indexString = parts[0].replacingOccurrences(of: "[", with: "")
                        let name = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " "))
                        if let index = Int(indexString) {
                            let id = "\(index)-\(name)"
                            devices.append(AudioDevice(id: id, index: index, name: name))
                        }
                    }
                }
            }
        }
        return devices
    }

    func switchDeviceForMic(enabled: Bool) {
        if audioDevices.isEmpty {
            return
        }
        if enabled {
            let candidates = audioDevices.filter {
                let name = $0.name.lowercased()
                return name.contains("aggregate") || (name.contains("mic") && name.contains("blackhole")) || name.contains("mic & blackhole")
            }
            if let aggregate = candidates.first {
                selectedDeviceId = aggregate.id
                deviceIndex = String(aggregate.index)
                status = "Micrófono ON: usando \(aggregate.name)."
                return
            }
            status = "No encontré Aggregate Device. Crea uno en Audio MIDI Setup."
        } else {
            if let blackhole = audioDevices.first(where: { $0.name.lowercased().contains("blackhole 2ch") }) {
                selectedDeviceId = blackhole.id
                deviceIndex = String(blackhole.index)
                status = "Micrófono OFF: usando BlackHole 2ch."
                return
            }
            status = "No encontré BlackHole 2ch."
        }
    }

    func sanitizeBaseName(_ input: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = input
            .lowercased()
            .map { String($0.unicodeScalars.allSatisfy { allowed.contains($0) } ? $0 : "-") }
            .joined()
        let collapsed = cleaned.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
    }

    private func coreAudioDeviceNames() -> [String] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        if status != noErr || dataSize == 0 {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array<AudioDeviceID>(repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        if status != noErr {
            return []
        }

        var names: [String] = []
        for id in deviceIDs {
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let nameStatus = withUnsafeMutablePointer(to: &name) { namePtr in
                namePtr.withMemoryRebound(to: UInt8.self, capacity: Int(nameSize)) { rawPtr in
                    AudioObjectGetPropertyData(
                        id,
                        &nameAddress,
                        0,
                        nil,
                        &nameSize,
                        rawPtr
                    )
                }
            }
            if nameStatus == noErr {
                names.append(name as String)
            }
        }
        return names
    }
}

@main
struct ListenTranscriberApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 520, minHeight: 400)
        }
        MenuBarExtra("Listen Transcriber", systemImage: "mic.fill") {
            MenuPopoverView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuPopoverView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Listen Transcriber")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            HStack(spacing: 10) {
                statusDot(isOn: appState.includeMicrophone, label: "Mic")
                statusDot(isOn: appState.micPermissionGranted && appState.screenPermissionGranted, label: "Permisos")
                statusDot(isOn: appState.isRecording, label: "Grabando")
            }
            Divider()
            TextField("Nombre (ej: reunion-cliente)", text: $appState.baseName)
                .textFieldStyle(.roundedBorder)
            Toggle("Agregar fecha", isOn: $appState.appendDate)
                .toggleStyle(.switch)
            Toggle("Incluir micrófono", isOn: $appState.includeMicrophone)
                .toggleStyle(.switch)
                .onChange(of: appState.includeMicrophone) { newValue in
                    if appState.audioDevices.isEmpty {
                        appState.pendingMicSwitch = true
                        appState.listAudioDevices()
                    } else {
                        appState.switchDeviceForMic(enabled: newValue)
                    }
                }
                .disabled(!appState.hasDetectedDevices)
            if !appState.hasDetectedDevices {
                Text("Primero toca “Detectar BlackHole 2ch”.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
            Picker("Idioma", selection: $appState.selectedLanguage) {
                ForEach(Language.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 200)

            HStack {
                Button {
                    if appState.isRecording {
                        appState.stopRecording()
                    } else {
                        appState.startRecording()
                    }
                } label: {
                    if appState.isRecording {
                        Label("Detener", systemImage: "stop.fill")
                    } else {
                        Label("Grabar", systemImage: "mic.fill")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25)))
                .disabled(appState.deviceIndex.isEmpty)
            }
            Button("Detectar BlackHole 2ch") {
                appState.detectBlackHole()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25)))
            Divider()
            Button("Abrir ventana") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25)))
            Button("Salir") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25)))
        }
        .padding(12)
        .frame(width: 240)
        .foregroundColor(.white)
        .tint(.white)
    }

    private func statusDot(isOn: Bool, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isOn ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
        }
    }
}

struct SetupWizardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setup Wizard")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            GroupBox("1) BlackHole 2ch") {
                VStack(alignment: .leading, spacing: 6) {
                    statusLine(appState.isBlackHoleInstalled(), "BlackHole 2ch instalado")
                    Button("Abrir instalador BlackHole") {
                        appState.openBundledBlackHoleInstaller()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25)))
                }
                .padding(.vertical, 6)
            }

            GroupBox("2) Audio MIDI Setup") {
                VStack(alignment: .leading, spacing: 6) {
                    statusLine(appState.hasCoreAudioDevice(matching: ["Multi-Output", "Multi-Output Device"]), "Multi-Output Device creado")
                    statusLine(appState.hasCoreAudioDevice(matching: ["Aggregate", "Mic & Blackhole", "Mic & BlackHole", "Mic & BlackHole 2ch"]), "Aggregate Device creado (opcional)")
                    HStack {
                        Button("Abrir Audio MIDI Setup") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Utilities/Audio MIDI Setup.app"))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25)))

                        Button("Actualizar verificación") {
                            appState.listAudioDevices()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25)))
                    }
                }
                .padding(.vertical, 6)
            }

            GroupBox("3) Permisos") {
                VStack(alignment: .leading, spacing: 6) {
                    statusLine(appState.micPermissionGranted, "Micrófono permitido")
                    statusLine(appState.screenPermissionGranted, "Grabación de pantalla permitida")
                    HStack {
                        Button("Pedir micrófono") {
                            appState.requestMicrophonePermission()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25)))

                        Button("Pedir pantalla") {
                            appState.requestScreenRecordingPermission()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25)))
                    }
                }
                .padding(.vertical, 6)
            }

            Divider()
            HStack {
                Spacer()
                Button("Cerrar") { dismiss() }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.2)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25)))
            }
        }
        .padding(16)
        .frame(width: 460)
        .foregroundColor(.white)
        .tint(.white)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .onAppear {
            appState.refreshPermissions()
            appState.listAudioDevices()
        }
    }

    private func statusLine(_ ok: Bool, _ text: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ok ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption)
        }
    }

}

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            VStack(spacing: 0) {
            if appState.selectedTab == "Principal" {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Listen Transcriber")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)

                HStack(spacing: 16) {
                    statusDot(isOn: appState.includeMicrophone, label: "Mic")
                    statusDot(isOn: appState.micPermissionGranted && appState.screenPermissionGranted, label: "Permisos")
                    statusDot(isOn: appState.isRecording, label: "Grabando")
                }
                .padding(.vertical, 4)

                GroupBox("1) Dispositivo (rápido)") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle("Incluir micrófono", isOn: $appState.includeMicrophone)
                                .toggleStyle(.switch)
                                .onChange(of: appState.includeMicrophone) { newValue in
                                    if appState.audioDevices.isEmpty {
                                        appState.pendingMicSwitch = true
                                        appState.listAudioDevices()
                                    } else {
                                        appState.switchDeviceForMic(enabled: newValue)
                                    }
                                }
                                .disabled(!appState.hasDetectedDevices)
                            Button("Detectar BlackHole 2ch") {
                                appState.detectBlackHole()
                            }
                        }
                        Text("Activo: \(appState.activeDeviceLabel())")
                            .font(.caption)
                        if !appState.hasDetectedDevices {
                            Text("Primero toca “Detectar BlackHole 2ch”.")
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("2) Grabación") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Nombre (ej: reunion-cliente)", text: $appState.baseName)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 280)
                            Toggle("Agregar fecha", isOn: $appState.appendDate)
                                .toggleStyle(.switch)
                        }
                        HStack {
                            Button {
                                appState.startRecording()
                            } label: {
                                if appState.isRecording {
                                    Label("Grabando...", systemImage: "mic.fill")
                                } else {
                                    Label("Iniciar grabación", systemImage: "mic.fill")
                                }
                            }
                            .disabled(appState.isRecording || appState.deviceIndex.isEmpty)

                            Button {
                                appState.stopRecording()
                            } label: {
                                Label("Detener", systemImage: "stop.fill")
                            }
                            .disabled(!appState.isRecording)
                        }
                        if !appState.lastAudioPath.isEmpty {
                            Text("Audio: \(appState.lastAudioPath)")
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("3) Transcripción") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Picker("Idioma", selection: $appState.selectedLanguage) {
                                ForEach(Language.allCases) { lang in
                                    Text(lang.displayName).tag(lang)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 260)
                        }
                    HStack {
                        Button(appState.isTranscribing ? "Transcribiendo..." : "Transcribir último audio") {
                            appState.transcribeLastAudio()
                        }
                            .disabled(appState.isTranscribing || appState.lastAudioPath.isEmpty)

                            Button("Elegir audio...") {
                                appState.showFilePicker = true
                            }

                    }
                    if !appState.downloadStatus.isEmpty {
                        Text(appState.downloadStatus)
                            .font(.caption)
                        }
                        if !appState.lastTranscriptPath.isEmpty {
                            Text("Texto: \(appState.lastTranscriptPath)")
                                .font(.caption)
                        }
                        if !appState.lastWhisperLog.isEmpty {
                            Text("Log: \(appState.lastWhisperLog)")
                                .font(.caption)
                                .lineLimit(3)
                        }
                    }
                    .padding(.vertical, 4)
                }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onAppear {
                    appState.refreshPermissions()
                    appState.refreshRecordingState()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Settings")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)

                GroupBox("Dispositivo") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Índice de dispositivo (ej: 2)", text: $appState.deviceIndex)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 200)
                                .onChange(of: appState.deviceIndex) { _ in
                                    appState.syncSelectionFromIndex()
                                }
                            Button("Actualizar lista") {
                                appState.listAudioDevices()
                            }
                        }
                        if !appState.audioDevices.isEmpty {
                            Picker("Dispositivo", selection: $appState.selectedDeviceId) {
                                ForEach(appState.audioDevices) { device in
                                    Text("[\(device.index)] \(device.name)").tag(device.id)
                                }
                            }
                            .onChange(of: appState.selectedDeviceId) { newValue in
                                if let selected = appState.audioDevices.first(where: { $0.id == newValue }) {
                                    appState.deviceIndex = String(selected.index)
                                }
                            }
                            .frame(maxWidth: 520)
                        }
                        Text("Usa BlackHole 2ch (solo salida) o tu Aggregate (si incluyes mic).")
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Permisos") {
                    HStack {
                        Button("Solicitar permiso de micrófono") {
                            appState.requestMicrophonePermission()
                        }
                        Button("Solicitar permiso de grabación de pantalla") {
                            appState.requestScreenRecordingPermission()
                        }
                        Button("Setup Wizard") {
                            appState.showSetupWizard = true
                        }
                        Button("Donate") {
                            appState.openDonate()
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Rendimiento") {
                    HStack {
                        Toggle("Usar GPU", isOn: $appState.useGpu)
                            .toggleStyle(.switch)
                        Text("Si falla, apágalo.")
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Modelo") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Modelo", selection: $appState.selectedModel) {
                            ForEach(ModelSize.allCases) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)

                        Button("Descargar modelo") {
                            appState.downloadModel()
                        }
                        .disabled(appState.modelExists())
                        if !appState.downloadStatus.isEmpty {
                            Text(appState.downloadStatus)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Carpeta de salida") {
                    HStack(alignment: .top) {
                        Text(appState.outputFolderPath.isEmpty ? "~/Downloads/Transcripts" : appState.outputFolderPath)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Cambiar...") {
                            appState.showFolderPicker = true
                        }
                        Button("Abrir carpeta") {
                            appState.openOutputFolder()
                        }
                    }
                    .padding(.vertical, 2)
                }

                GroupBox("Estado") {
                    Text(appState.status)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 2)
                }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onAppear {
                    if appState.outputFolderPath.isEmpty {
                        appState.outputFolderPath = appState.loadOutputFolderPath()
                    }
                    appState.refreshRecordingState()
                }
            }

            Divider()
            HStack(spacing: 12) {
                Spacer()
                Button {
                    appState.selectedTab = "Principal"
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "house.fill")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(appState.selectedTab == "Principal" ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button {
                    appState.selectedTab = "Settings"
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(appState.selectedTab == "Settings" ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(.white)
        .foregroundColor(.white)
        .background(Color.clear)
        .environment(\.colorScheme, .dark)
        .background(WindowAccessor())
        .fileImporter(
            isPresented: $appState.showFilePicker,
            allowedContentTypes: [.audio, .wav],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    appState.lastAudioPath = url.path
                    appState.status = "Archivo seleccionado: \(url.lastPathComponent)"
                }
            case .failure(let error):
                appState.status = "Error al seleccionar archivo: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $appState.showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    appState.outputFolderPath = url.path
                    appState.saveOutputFolderPath(appState.outputFolderPath)
                    appState.status = "Carpeta de salida actualizada."
                }
            case .failure(let error):
                appState.status = "Error al seleccionar carpeta: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $appState.showSetupWizard) {
            SetupWizardView()
                .environmentObject(appState)
        }
    }

    private func statusDot(isOn: Bool, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isOn ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption)
        }
    }
}
