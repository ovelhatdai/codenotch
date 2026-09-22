import AppKit
import SwiftUI

@MainActor
final class ClaudeAccountLogin: ObservableObject {
    @Published var message = "Informe o nome e o e-mail da conta que deseja vincular."
    @Published var authorizationURL: URL?
    @Published var busy = false
    @Published var deviceCode: String?
    let service: AccountService
    init(service: AccountService = .claude) { self.service = service }
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var buffer = ""
    private var attempt: UUID?
    private var deadline: Task<Void, Never>?

    static func authorizationURL(in text: String, service: AccountService = .claude) -> URL? {
        let pattern = #"https://[^\s\x00-\x1f]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).flatMap { URL(string: String(text[$0])) }
        }.first {
            $0.scheme == "https" && (service == .claude
                ? (["claude.ai", "claude.com", "platform.claude.com", "console.anthropic.com"].contains($0.host ?? "") && $0.path.contains("authorize"))
                : ($0.host == "auth.openai.com" && $0.path == "/codex/device"))
        }
    }

    func start(name: String, email: String, root: URL, reconnecting: LinkedAccount? = nil, connected: @escaping (LinkedClaudeAccount) -> Void) {
        guard !busy, let binary = Self.binary(for: service) else {
            message = "Instale o \(service.title) antes de vincular uma conta."; return
        }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, email.contains("@"), !email.contains("\n") else {
            message = "Informe um nome e um e-mail válido."; return
        }
        let id = UUID()
        let account = LinkedClaudeAccount(id: reconnecting?.id ?? id.uuidString.lowercased(), name: String(name.prefix(80)), email: email,
                                          directory: reconnecting?.directory ?? root.appendingPathComponent(service.rawValue + "-" + id.uuidString.lowercased()), service: service)
        do {
            try FileManager.default.createDirectory(at: account.directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let task = Process(), stdin = Pipe(), stdout = Pipe()
            task.executableURL = binary
            task.arguments = service == .claude ? ["auth", "login", "--claudeai", "--email", email]
                : ["-c", "cli_auth_credentials_store=\"file\"", "login", "--device-auth"]
            task.environment = Self.environment(directory: account.directory, service: service)
            task.currentDirectoryURL = account.directory
            task.standardInput = stdin; task.standardOutput = stdout; task.standardError = stdout
            attempt = id; busy = true; authorizationURL = nil; buffer = ""
            message = "Preparando a autorização oficial do \(service.title)…"
            process = task; input = stdin; output = stdout
            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { handle.readabilityHandler = nil; return }
                let text = String(decoding: data, as: UTF8.self)
                Task { @MainActor in
                    guard let self, self.attempt == id else { return }
                    self.buffer = String((self.buffer + text).suffix(32768))
                    if let url = Self.authorizationURL(in: self.buffer, service: self.service) {
                        self.authorizationURL = url
                        self.deviceCode = Self.deviceCode(in: self.buffer)
                        self.message = self.service == .claude ? "Autorize no Claude. Se ele apresentar um código, cole no campo abaixo." : "Abra o link e informe o código no site oficial do Codex."
                    }
                }
            }
            task.terminationHandler = { [weak self] task in
                let status = task.terminationStatus
                Task { @MainActor in
                    guard let self, self.attempt == id else { return }
                    self.deadline?.cancel()
                    guard status == 0 else {
                        self.finish("Autenticação não concluída. Você pode tentar novamente."); return
                    }
                    self.message = "Conferindo a identidade da conta…"
                    let actual: String?
                    if account.service == .claude {
                        actual = await Task.detached { Self.identity(binary: binary, directory: account.directory) }.value
                    } else {
                        actual = CodexCredentials.account(from: account.codexProfile.authURL)?.label
                    }
                    guard self.attempt == id else { return }
                    guard actual?.lowercased() == email.lowercased() else {
                        self.finish("O e-mail autenticado não corresponde ao informado. A conta não foi adicionada."); return
                    }
                    self.finish("Identidade confirmada: \(name).")
                    connected(account)
                }
            }
            try task.run()
            deadline = Task { [weak self] in
                try? await Task.sleep(for: .seconds(600))
                guard !Task.isCancelled, let self, self.attempt == id else { return }
                self.cancel(); self.message = "Autorização expirada. Inicie novamente."
            }
        } catch { finish("Não foi possível iniciar o Claude Code.") }
    }

    nonisolated static func binary(for service: AccountService) -> URL? {
        if service == .claude { return ClaudeUsageCLI.locate()?.binary }
        let home = NSHomeDirectory()
        return [home + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                "/Applications/Codex.app/Contents/Resources/codex"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
    nonisolated static func deviceCode(in text: String) -> String? {
        // The official CLI wraps the code in ANSI blue/reset sequences even
        // when stdout is a pipe. Their trailing "m" defeats a word boundary.
        let plain = text.replacingOccurrences(of: #"\x1B\[[0-?]*[ -/]*[@-~]"#,
                                             with: "", options: .regularExpression)
        guard let range = plain.range(of: #"\b[A-Z0-9]{4}-[A-Z0-9]{4,5}\b"#, options: .regularExpression) else { return nil }
        return String(plain[range])
    }

    func submit(code: String) {
        guard busy, !code.isEmpty, !code.contains("\n"), !code.contains("\r") else { return }
        do { try input?.fileHandleForWriting.write(contentsOf: Data((code + "\n").utf8)) }
        catch { message = "O processo não aceitou o código. Inicie novamente." }
    }
    func cancel() {
        attempt = nil; deadline?.cancel()
        if process?.isRunning == true { process?.terminate() }
        finish("Autenticação cancelada.")
    }
    private func finish(_ text: String) {
        attempt = nil
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        process = nil; input = nil; output = nil; buffer = ""
        busy = false; authorizationURL = nil; deviceCode = nil; message = text
    }
    nonisolated private static func environment(directory: URL, service: AccountService = .claude) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_BASE_URL", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY", "OPENAI_API_KEY", "CODEX_API_KEY", "CODEX_ACCESS_TOKEN"] { env.removeValue(forKey: key) }
        env[service == .claude ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME"] = directory.path
        return env
    }
    nonisolated private static func identity(binary: URL, directory: URL) -> String? {
        let task = Process(), output = Pipe()
        task.executableURL = binary; task.arguments = ["auth", "status", "--json"]
        task.environment = environment(directory: directory); task.currentDirectoryURL = directory
        task.standardOutput = output; task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let timeout = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit(); timeout.cancel()
        guard task.terminationStatus == 0,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["loggedIn"] as? Bool == true else { return nil }
        return object["email"] as? String
    }
}

struct AddLinkedAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var login: ClaudeAccountLogin
    @State private var name = ""
    @State private var email = ""
    @State private var code = ""
    @State private var verified: LinkedAccount?
    @State private var replaceDuplicates = true
    @State private var saveError: String?
    @AppStorage("linkedAccountStorageDirectory") private var storage = ""
    let service: AccountService
    let existing: [ProviderSummary]
    let reconnecting: LinkedAccount?
    let connected: (LinkedAccount, [String]) -> Void

    init(service: AccountService, existing: [ProviderSummary], reconnecting: LinkedAccount? = nil, connected: @escaping (LinkedAccount, [String]) -> Void) {
        self.service = service; self.existing = existing; self.connected = connected
        self.reconnecting = reconnecting
        _name = State(initialValue: reconnecting?.name ?? "")
        _email = State(initialValue: reconnecting?.email ?? "")
        _login = StateObject(wrappedValue: ClaudeAccountLogin(service: service))
    }
    private var duplicates: [String] { LinkedAccount.matches(email: email, service: service, summaries: existing) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vincular conta \(service.title)").font(.title2)
            Text("Uma sessão exclusiva para monitoramento, separada do login do aplicativo de trabalho.").font(.callout)
            TextField("Nome da conta", text: $name).disabled(login.busy || verified != nil)
            TextField("E-mail esperado", text: $email).disabled(login.busy || verified != nil)
            HStack {
                Button("Pasta protegida das sessões…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url { storage = url.path }
                }
                Text(storage.isEmpty ? "Selecione a pasta de credenciais" : storage).font(.caption).lineLimit(2)
            }.disabled(login.busy || verified != nil)
            if !duplicates.isEmpty {
                Text("Há \(duplicates.count) perfil(is) de \(service.title) com este e-mail.").foregroundStyle(.orange)
                Toggle("Mostrar só a nova sessão independente", isOn: $replaceDuplicates)
                Text("Os outros logins são preservados. Você pode reativar seus indicadores nos ajustes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let account = verified {
                Text("E-mail confirmado: \(account.email)").foregroundStyle(.green)
                Button("Concluir vínculo") {
                    do {
                        try account.save()
                        connected(account, replaceDuplicates ? duplicates : [])
                        dismiss()
                    } catch { saveError = "Não foi possível salvar o vínculo." }
                }.buttonStyle(.borderedProminent)
            } else {
                Button("Iniciar autenticação oficial") {
                    login.start(name: name, email: email, root: URL(fileURLWithPath: storage), reconnecting: reconnecting) { verified = $0 }
                }.disabled(login.busy || (storage.isEmpty && reconnecting == nil) || name.isEmpty || email.isEmpty)
            }
            Text(login.message).font(.callout).textSelection(.enabled)
            if let url = login.authorizationURL {
                Link("Abrir autorização de \(service.title)", destination: url)
                if service == .codex {
                    if let deviceCode = login.deviceCode { Text(deviceCode).font(.title.monospaced()).textSelection(.enabled) }
                    else { Text("Aguardando o código do Codex…") }
                } else {
                    SecureField("Código recebido, se solicitado", text: $code)
                    Button("Confirmar código") { login.submit(code: code); code = "" }.disabled(code.isEmpty)
                }
            }
            if let saveError { Text(saveError).foregroundStyle(.red) }
            Button("Cancelar") { login.cancel(); dismiss() }
        }
        .textFieldStyle(.roundedBorder)
        .padding(24).frame(width: 510)
        .onDisappear { login.cancel() }
    }
}
