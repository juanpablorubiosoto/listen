import SwiftUI
import AppKit
import AVFoundation
import CoreGraphics

@main
struct ListenTranscriberApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 640, minHeight: 520)
        }
    }
}

struct ContentView: View {
    struct AudioDevice: Identifiable, Hashable {
        let id: String
        let index: Int
        let name: String
    }
    @State private var deviceIndex: String = ""
    @State private var status: String = "Listo."
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var lastAudioPath: String = ""
    @State private var lastTranscriptPath: String = ""
    @State private var baseName: String = ""
    @State private var appendDate: Bool = true
    @State private var selectedModel: ModelSize = .medium
    @State private var selectedLanguage: Language = .auto
    @State private var recordingProcess: Process? = nil
    @State private var downloadStatus: String = ""
    @State private var audioDevices: [AudioDevice] = []
    @State private var selectedDeviceId: String = ""
    @State private var includeMicrophone: Bool = false
    @State private var lastWhisperLog: String = ""
    @State private var useGpu: Bool = false
    @State private var showFilePicker: Bool = false

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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Listen Transcriber")
                .font(.system(size: 28, weight: .bold))

            GroupBox("1) Dispositivo de audio") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Índice de dispositivo (ej: 2)", text: $deviceIndex)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                        Button("Detectar BlackHole 2ch") {
                            detectBlackHole()
                        }
                        Button("Actualizar lista") {
                            listAudioDevices()
                        }
                    }
                    HStack {
                        Toggle("Incluir micrófono", isOn: $includeMicrophone)
                            .toggleStyle(.switch)
                            .onChange(of: includeMicrophone) { newValue in
                                switchDeviceForMic(enabled: newValue)
                            }
                    }
                    if !audioDevices.isEmpty {
                        Picker("Dispositivo", selection: $selectedDeviceId) {
                            ForEach(audioDevices) { device in
                                Text("[\(device.index)] \(device.name)").tag(device.id)
                            }
                        }
                        .onChange(of: selectedDeviceId) { newValue in
                            if let selected = audioDevices.first(where: { $0.id == newValue }) {
                                deviceIndex = String(selected.index)
                            }
                        }
                        .frame(maxWidth: 520)
                    }
                    HStack {
                        Button("Solicitar permiso de micrófono") {
                            requestMicrophonePermission()
                        }
                        Button("Solicitar permiso de grabación de pantalla") {
                            requestScreenRecordingPermission()
                        }
                    }
                    Text("Usa BlackHole 2ch (solo salida) o tu Aggregate (si incluyes mic).")
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }

            GroupBox("2) Grabación") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Nombre (ej: reunion-cliente)", text: $baseName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                        Toggle("Agregar fecha", isOn: $appendDate)
                            .toggleStyle(.switch)
                    }
                    HStack {
                        Button(isRecording ? "Grabando..." : "Iniciar grabación") {
                            startRecording()
                        }
                        .disabled(isRecording || deviceIndex.isEmpty)

                        Button("Detener") {
                            stopRecording()
                        }
                        .disabled(!isRecording)
                    }
                    if !lastAudioPath.isEmpty {
                        Text("Audio: \(lastAudioPath)")
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("3) Transcripción") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("Modelo", selection: $selectedModel) {
                            ForEach(ModelSize.allCases) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)

                        Picker("Idioma", selection: $selectedLanguage) {
                            ForEach(Language.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    }
                    HStack {
                        Toggle("Usar GPU", isOn: $useGpu)
                            .toggleStyle(.switch)
                        Text("Si falla, apágalo.")
                            .font(.caption)
                    }

                    HStack {
                        Button(isTranscribing ? "Transcribiendo..." : "Transcribir último audio") {
                            transcribeLastAudio()
                        }
                        .disabled(isTranscribing || lastAudioPath.isEmpty)

                        Button("Elegir audio...") {
                            showFilePicker = true
                        }

                        Button("Descargar modelo") {
                            downloadModel()
                        }
                    }
                    if !downloadStatus.isEmpty {
                        Text(downloadStatus)
                            .font(.caption)
                    }
                    if !lastTranscriptPath.isEmpty {
                        Text("Texto: \(lastTranscriptPath)")
                            .font(.caption)
                    }
                    if !lastWhisperLog.isEmpty {
                        Text("Log: \(lastWhisperLog)")
                            .font(.caption)
                            .lineLimit(3)
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Carpeta de salida") {
                HStack {
                    Text("~/Downloads/Transcripts")
                        .font(.caption)
                    Spacer()
                    Button("Abrir carpeta") {
                        openOutputFolder()
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Estado") {
                Text(status)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            Spacer()
        }
        .padding(20)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio, .wav],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    lastAudioPath = url.path
                    status = "Archivo seleccionado: \(url.lastPathComponent)"
                }
            case .failure(let error):
                status = "Error al seleccionar archivo: \(error.localizedDescription)"
            }
        }
    }

    private func outputFolderURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folder = home.appendingPathComponent("Downloads/Transcripts")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func modelFolderURL() -> URL {
        let folder = outputFolderURL().appendingPathComponent("models")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func bundledBinary(_ name: String) -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("bin/")
            .appendingPathComponent(name)
    }

    private func detectBlackHole() {
        guard let ffmpeg = bundledBinary("ffmpeg") else {
            status = "No se encontró ffmpeg dentro de la app."
            return
        }
        status = "Detectando dispositivos..."
        DispatchQueue.global(qos: .userInitiated).async {
            let output = runProcess(executable: ffmpeg, args: [
                "-f", "avfoundation",
                "-list_devices", "true",
                "-i", ""
            ])
            let devices = parseAudioDevices(output: output)
            let index = devices.first(where: { $0.name.contains("BlackHole 2ch") })?.index
            DispatchQueue.main.async {
                audioDevices = devices
                if let selected = devices.first(where: { $0.index == index }) {
                    selectedDeviceId = selected.id
                }
                // Si ya estaba activado "Incluir micrófono", respeta Aggregate si existe
                if includeMicrophone {
                    switchDeviceForMic(enabled: true)
                }
                if let index = index {
                    deviceIndex = String(index)
                    status = "BlackHole 2ch encontrado en índice \(index)."
                } else {
                    status = "No encontré BlackHole 2ch. Revisa Audio MIDI Setup."
                }
            }
        }
    }

    private func listAudioDevices() {
        guard let ffmpeg = bundledBinary("ffmpeg") else {
            status = "No se encontró ffmpeg dentro de la app."
            return
        }
        status = "Listando dispositivos..."
        DispatchQueue.global(qos: .userInitiated).async {
            let output = runProcess(executable: ffmpeg, args: [
                "-f", "avfoundation",
                "-list_devices", "true",
                "-i", ""
            ])
            let devices = parseAudioDevices(output: output)
            DispatchQueue.main.async {
                audioDevices = devices
                if let first = devices.first {
                    selectedDeviceId = first.id
                }
                if includeMicrophone {
                    switchDeviceForMic(enabled: true)
                }
                status = devices.isEmpty ? "No pude listar dispositivos." : "Dispositivos listados."
            }
        }
    }

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                status = granted ? "Permiso de micrófono concedido." : "Permiso de micrófono denegado."
            }
        }
    }

    private func requestScreenRecordingPermission() {
        let hasAccess = CGPreflightScreenCaptureAccess()
        if hasAccess {
            status = "Permiso de grabación de pantalla ya concedido."
            return
        }
        let granted = CGRequestScreenCaptureAccess()
        status = granted ? "Permiso de grabación de pantalla concedido." : "Permiso de grabación de pantalla denegado."
        if !granted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startRecording() {
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

    private func stopRecording() {
        guard let process = recordingProcess else { return }
        process.terminate()
        recordingProcess = nil
        isRecording = false
        status = "Grabación detenida."
    }

    private func transcribeLastAudio() {
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
            let output = runProcess(executable: whisper, args: args)
            DispatchQueue.main.async {
                isTranscribing = false
                lastWhisperLog = output.isEmpty ? "Sin salida de whisper." : output
                status = "Transcripción lista."
            }
        }
    }

    private func downloadModel() {
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
                    downloadStatus = "Error: \(error.localizedDescription)"
                    return
                }
                guard let tempURL = tempURL else {
                    downloadStatus = "Descarga falló."
                    return
                }
                do {
                    try FileManager.default.moveItem(at: tempURL, to: target)
                    downloadStatus = "Modelo listo: \(fileName)"
                } catch {
                    downloadStatus = "No pude guardar el modelo: \(error.localizedDescription)"
                }
            }
        }
        task.resume()
    }

    private func openOutputFolder() {
        NSWorkspace.shared.open(outputFolderURL())
    }

    private func runProcess(executable: URL, args: [String]) -> String {
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

    private func parseBlackHoleIndex(output: String) -> Int? {
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

    private func parseAudioDevices(output: String) -> [AudioDevice] {
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

    private func switchDeviceForMic(enabled: Bool) {
        if audioDevices.isEmpty {
            return
        }
        if enabled {
            if let aggregate = audioDevices.first(where: { $0.name.lowercased().contains("aggregate") }) {
                selectedDeviceId = aggregate.id
                deviceIndex = String(aggregate.index)
                status = "Micrófono ON: usando Aggregate Device."
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

    private func sanitizeBaseName(_ input: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = input
            .lowercased()
            .map { String($0.unicodeScalars.allSatisfy { allowed.contains($0) } ? $0 : "-") }
            .joined()
        let collapsed = cleaned.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
    }
}
