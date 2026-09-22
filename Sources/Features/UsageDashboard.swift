import AppKit
import SwiftUI

@MainActor
final class UsageDashboardController: NSWindowController, NSWindowDelegate {
    private var screensObserver: NSObjectProtocol?
    private var isRestoring = false
    private let defaults = UserDefaults.standard
    private var lastScreenID: String?

    static func visibleFrame(_ proposed: NSRect, on screen: NSRect) -> NSRect {
        let width = min(proposed.width, screen.width), height = min(proposed.height, screen.height)
        return NSRect(x: min(max(proposed.minX, screen.minX), screen.maxX - width),
                      y: min(max(proposed.minY, screen.minY), screen.maxY - height), width: width, height: height)
    }
    private func savePlacement() {
        guard !isRestoring, let window, let id = window.screen?.displayIdentifier else { return }
        var frames = defaults.dictionary(forKey: "dashboardFramesByMonitor") as? [String: String] ?? [:]
        frames[id] = NSStringFromRect(window.frame)
        defaults.set(frames, forKey: "dashboardFramesByMonitor")
        defaults.set(id, forKey: "dashboardLastMonitor")
        lastScreenID = id
    }
    func windowDidMove(_ notification: Notification) { savePlacement() }
    func windowDidResize(_ notification: Notification) { savePlacement() }
    func windowWillClose(_ notification: Notification) { savePlacement() }
    private func move(to screen: NSScreen) {
        guard let window else { return }
        savePlacement()
        isRestoring = true
        let frames = defaults.dictionary(forKey: "dashboardFramesByMonitor") as? [String: String] ?? [:]
        let remembered = screen.displayIdentifier.flatMap { frames[$0] }.map(NSRectFromString)
        let fallback = NSRect(x: screen.visibleFrame.midX - window.frame.width / 2,
                              y: screen.visibleFrame.midY - window.frame.height / 2,
                              width: window.frame.width, height: window.frame.height)
        window.setFrame(Self.visibleFrame(remembered ?? fallback, on: screen.visibleFrame), display: true)
        isRestoring = false
        savePlacement()
    }
    private func recoverVisibleWindow() {
        guard let window, let fallback = NSScreen.main ?? NSScreen.screens.first else { return }
        let isVisible = NSScreen.screens.contains { screen in
            let overlap = window.frame.intersection(screen.visibleFrame)
            return overlap.width >= 100 && overlap.height >= 60
        }
        if !isVisible {
            isRestoring = true
            window.setFrame(Self.visibleFrame(window.frame, on: fallback.visibleFrame), display: true)
            isRestoring = false
        }
    }
    static let shared = UsageDashboardController()
    func show(store: UsageStore, preferences: Preferences, on screen: NSScreen? = nil) {
        if let window {
            if let screen { move(to: screen) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
        panel.title = "Dashboard de consumo"
        panel.titlebarAppearsTransparent = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.minSize = NSSize(width: 380, height: 420)
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName("usageDashboardFrame")
        panel.contentView = NSHostingView(rootView: UsageDashboard(store: store, preferences: preferences,
            moveTo: { [weak self] screen in self?.move(to: screen)
            }, stayOnTop: { panel.level = $0 ? .floating : .normal }))
        window = panel
        panel.delegate = self
        if !panel.setFrameUsingName("usageDashboardFrame") { panel.center() }
        if let screen { move(to: screen) }
        else if let id = defaults.string(forKey: "dashboardLastMonitor"),
                let saved = NSScreen.screens.first(where: { $0.displayIdentifier == id }) { move(to: saved) }
        recoverVisibleWindow()
        screensObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.recoverVisibleWindow() }
            }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct UsageDashboard: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var preferences: Preferences
    let moveTo: (NSScreen) -> Void
    let stayOnTop: (Bool) -> Void
    @AppStorage("dashboardFloating") private var floating = false
    @AppStorage("dashboardFilter") private var filter = "all"
    @AppStorage("dashboardGrouping") private var grouping = "service"
    @AppStorage("dashboardLayout") private var layout = "cards"
    @AppStorage(AccountNames.key) private var names = Data()
    @State private var page = "accounts"
    @State private var showsControls = false
    @State private var contentWidth: CGFloat = 800
    private var visible: [ProviderSnapshot] {
        store.notchSnapshots.filter { filter == "all" || (filter == "claude" ? $0.glyph == .claude : $0.glyph == .openai) }
    }
    static func columnCount(width: CGFloat) -> Int { width >= 1162 ? 4 : width >= 574 ? 2 : 1 }
    private var groups: [(String, [ProviderSnapshot])] {
        if grouping == "person" {
            let labels = visible.map { AccountNames.name(for: $0.id, fallback: $0.displayName, in: names, email: $0.accountEmail) }
            return Array(Set(labels)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { name in
                (name, visible.filter { AccountNames.name(for: $0.id, fallback: $0.displayName, in: names, email: $0.accountEmail) == name })
            }
        }
        return [("Claude Code", visible.filter { $0.glyph == .claude }),
                ("Codex / OpenAI", visible.filter { $0.glyph == .openai }),
                ("Outros serviços", visible.filter { $0.glyph != .claude && $0.glyph != .openai })]
    }
    @ViewBuilder
    private func accountGroup(_ title: String, snapshots: [ProviderSnapshot]) -> some View {
        if !snapshots.isEmpty {
            let accounts = store.providerSummaries
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("\(snapshots.count) perfis").font(.caption).foregroundStyle(.white.opacity(0.62))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: layout == "list" ? 1 : Self.columnCount(width: contentWidth)), alignment: .leading, spacing: 14) {
                    ForEach(snapshots) { snapshot in
                        let email = accounts.first { $0.id == snapshot.providerID }?.account?.label
                        let service: AccountService? = ClaudeProfile.isClaude(providerID: snapshot.providerID) ? .claude
                            : CodexProfile.isCodex(providerID: snapshot.providerID) ? .codex : nil
                        let duplicated = service.map { service in
                            guard let email else { return false }
                            let enabled = accounts.filter { account in visible.contains { $0.providerID == account.id } }
                            return LinkedAccount.matches(email: email, service: service, summaries: enabled).count > 1
                        } ?? false
                        DashboardAccountCard(snapshot: snapshot, identity: email, duplicated: duplicated,
                                             refreshing: store.refreshing.contains(snapshot.providerID),
                                             preferences: preferences, compact: layout == "list",
                                             health: store.readingHealth[snapshot.providerID], history: store.consumptionHistory)
                    }
                }
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Seu painel de consumo").font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text("Passe o mouse sobre um anel para explorar a conta.").font(.callout).foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                Button { store.refreshNow() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Atualizar todas as contas")
                Button { withAnimation(.easeInOut(duration: 0.2)) { showsControls.toggle() } } label: {
                    Image(systemName: "slider.horizontal.3")
                }.help("Organização e exibição")
            }
            ViewThatFits(in: .horizontal) {
              HStack { filterPicker; Spacer(); monitorMenu }
              VStack(alignment: .leading) { filterPicker; monitorMenu }
            }
            if showsControls {
                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack { organizationControls }
                        VStack(alignment: .leading) { organizationControls }
                    }
                    Toggle("Manter sobre as outras janelas", isOn: $floating)
                }.padding(14).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            }
            Picker("Página", selection: $page) {
                Text("Contas").tag("accounts"); Text("Histórico").tag("history")
            }.pickerStyle(.segmented).frame(maxWidth: 230)
            GeometryReader { geometry in
                ScrollView {
                    if page == "history", let history = store.consumptionHistory {
                        ConsumptionHistoryView(history: history, snapshots: visible, summaries: store.providerSummaries)
                    } else {
                        if visible.isEmpty { Text("Ative uma conta nos ajustes para acompanhar o consumo.").padding(30) }
                        VStack(alignment: .leading, spacing: 24) {
                            ForEach(groups, id: \.0) { title, snapshots in accountGroup(title, snapshots: snapshots) }
                        }
                    }
                }
                .onAppear { contentWidth = geometry.size.width }
                .onChange(of: geometry.size.width) { _, value in contentWidth = value }
            }
        }
        .padding(24)
        .onChange(of: floating) { _, value in stayOnTop(value) }
        .onAppear { stayOnTop(floating) }
        .frame(minWidth: 340, minHeight: 380)
        .background(.black.opacity(0.82))
        .background(.ultraThinMaterial)
        .foregroundStyle(.white)
        .environment(\.codenotchAccentColor, preferences.accentColor.color)
        .environment(\.usageWatchLimit, preferences.watchLimit)
        .environment(\.usageCriticalLimit, preferences.criticalLimit)
        .environment(\.usageDisplayMode, preferences.usageDisplayMode)
        .environment(\.weeklyRingDashed, preferences.weeklyRingDashed)
        .preferredColorScheme(.dark)
    }
    private var filterPicker: some View {
                Picker("Perfis", selection: $filter) {
                    Text("Todos").tag("all")
                    Text("Claude").tag("claude")
                    Text("Codex / OpenAI").tag("codex")
                }.pickerStyle(.segmented).frame(maxWidth: 360)
    }
    private var monitorMenu: some View {
        HStack {
            if let portrait = NSScreen.screens.first(where: { $0.frame.height > $0.frame.width }) {
                Button("Usar tela vertical") {
                    moveTo(portrait)
                }.help("Move esta janela para o monitor vertical; os cartões se adaptam à largura")
            }
            Menu("Monitor") {
                ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                    Button("\(index + 1) · \(screen.localizedName) · \(screen.frame.height > screen.frame.width ? "vertical" : "horizontal")") { moveTo(screen) }
                }
            }.fixedSize()
        }
    }
    @ViewBuilder private var organizationControls: some View {
        Picker("Agrupar", selection: $grouping) {
            Text("Por serviço").tag("service"); Text("Por conta").tag("person")
        }.pickerStyle(.segmented).frame(maxWidth: 290)
        Picker("Exibição", selection: $layout) {
            Text("Painel de anéis").tag("cards"); Text("Lista compacta").tag("list")
        }.pickerStyle(.segmented).frame(maxWidth: 290)
    }
}

private struct DashboardAccountCard: View {
    let snapshot: ProviderSnapshot
    let identity: String?
    let duplicated: Bool
    let refreshing: Bool
    @ObservedObject var preferences: Preferences
    var compact: Bool
    var health: ReadingHealth?
    var history: ConsumptionHistory?
    @State private var showsBudget = false
    @AppStorage(SpendingBudget.key) private var budgets = Data()
    @AppStorage(AccountNames.key) private var names = Data()
    @AppStorage(UsageDisplayMode.key) private var mode: UsageDisplayMode = .used
    @State private var hovered = false
    @State private var pinnedDetails = false
    @State private var ringHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var summaryWindows: [LimitWindow] {
        let selected = [snapshot.headline, snapshot.weeklyWindow].compactMap { $0 }
        return selected.isEmpty ? Array(snapshot.windows.prefix(2)) : selected
    }
    private var accountKey: String { ConsumptionHistory.accountKey(providerID: snapshot.providerID, email: identity) }
    private var records: [ConsumptionHistory.Day] { history?.records(providerID: snapshot.providerID, email: identity, since: "") ?? [] }
    private var reading: ProviderSnapshot { preferences.notchQuota.reading(from: snapshot) }
    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(AccountNames.name(for: snapshot.id, fallback: snapshot.displayName, in: names, email: snapshot.accountEmail))
                        .font(.system(size: 18, weight: .semibold, design: .rounded)).lineLimit(1)
                    Text(identity ?? "Identidade ainda não confirmada")
                        .font(.caption).foregroundStyle(.white.opacity(0.62)).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if duplicated { Image(systemName: "person.crop.circle.badge.exclamationmark").foregroundStyle(.orange).help("Login repetido") }
            }
            HStack(spacing: 22) {
                ProviderRing(usedFraction: reading.hasReading ? reading.ringFraction : nil,
                             glyph: snapshot.glyph, customIconFilename: snapshot.customIconFilename,
                             isStale: snapshot.status.isStale || !reading.hasReading,
                             isBlocked: snapshot.block != nil, isRefreshing: refreshing,
                             weeklyFraction: reading.hasReading ? reading.weeklyFraction : nil,
                             weeklyRing: preferences.weeklyRing, bandOverride: reading.bandOverride,
                             displayMode: mode)
                    .scaleEffect(1.9).frame(width: 82, height: 82)
                    .contentShape(Circle())
                    .onHover { ringHovered = $0 }
                    .onTapGesture { pinnedDetails = true }
                    .accessibilityLabel("Detalhes de " + snapshot.displayName)
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.text(for: reading))
                        .font(.system(size: 43, weight: .medium, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text(mode.title.lowercased()).font(.callout).foregroundStyle(.white.opacity(0.62))
                    Text(reading.headline?.label ?? "Sem leitura")
                        .font(.caption).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 13) {
                ForEach(summaryWindows) { window in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(window.label).foregroundStyle(.white.opacity(0.62))
                            Spacer()
                            if let fraction = window.usedFraction {
                                Text((mode == .available ? Percent.halves(for: fraction).left : Percent.text(for: fraction)) + "%")
                                    .monospacedDigit().fontWeight(.medium)
                            } else { Text("—") }
                        }.font(.caption)
                        if let fraction = window.usedFraction {
                            GeometryReader { proxy in
                                Capsule().fill(.white.opacity(0.08))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(UsageBand.band(for: fraction, watchLimit: preferences.watchLimit,
                                            criticalLimit: preferences.criticalLimit).color(accent: preferences.accentColor.color))
                                            .frame(width: max(0, proxy.size.width * mode.fraction(for: fraction)))
                                    }
                            }.frame(height: 4)
                        }
                        if let reset = window.resetsAt {
                            Text(ResetCopy.text(for: reset, now: Date(), format: preferences.resetTimeFormat))
                                .font(.caption2).foregroundStyle(.white.opacity(0.62))
                        }
                        if let money = window.money {
                            Text("Saldo: \(money.remaining, format: .currency(code: money.currency))")
                                .font(.caption2).foregroundStyle(.white.opacity(0.62))
                        }
                    }
                }
            }.frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
            Divider().opacity(0.5)
            resetCreditsRow.foregroundStyle(.white.opacity(0.62))
            HStack {
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    let health = self.health?.at(timeline.date)
                    HStack(spacing: 5) {
                        Circle().fill(health?.state == .current ? Color.green : .orange).frame(width: 5, height: 5)
                        Text(health?.title ?? "Aguardando leitura").font(.caption2).foregroundStyle(.white.opacity(0.62))
                    }
                }
                Spacer()
                Button { showsBudget = true } label: { Image(systemName: "wallet.bifold") }
                    .buttonStyle(.plain).help("Orçamento desta conta")
                Button { pinnedDetails = true } label: { Image(systemName: "arrow.up.right") }
                    .buttonStyle(.plain).help("Ver todos os dados da conta")
            }
            if let budget = SpendingBudget.budget(in: budgets, accountKey: accountKey) {
                if let spent = budget.spent(records: records) {
                    Text("\(spent, format: .currency(code: budget.currency)) / \(budget.limit, format: .currency(code: budget.currency)) · \(budget.month)")
                        .font(.caption2).foregroundStyle(spent >= budget.limit ? .orange : .white.opacity(0.62))
                } else { Text("Orçamento · gasto não informado").font(.caption2).foregroundStyle(.white.opacity(0.62)) }
            }
            if let message = snapshot.statusMessage {
                Text(message).font(.caption).foregroundStyle(.orange).lineLimit(2)
            }
        }
    }
    @ViewBuilder private var resetCreditsRow: some View {
        if ClaudeProfile.isClaude(providerID: snapshot.providerID) || CodexProfile.isCodex(providerID: snapshot.providerID) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Label("Resets extras disponíveis", systemImage: "arrow.counterclockwise")
                    Spacer()
                    Text(snapshot.resetCredits.map { String($0.availableCount) } ?? "Não informado")
                        .fontWeight(.semibold).monospacedDigit()
                }
                if let credits = snapshot.resetCredits, credits.availableCount > 0, let expiry = credits.nextExpiry {
                    Text("Próximo vencimento: \(expiry.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.white.opacity(0.62))
                }
            }.font(.caption)
            .help("Créditos de renovação extra informados pelo serviço. São diferentes da renovação automática da sessão ou da semana. Consultar este número não consome um reset.")
        }
    }
    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AccountNames.name(for: snapshot.id, fallback: snapshot.displayName, in: names, email: snapshot.accountEmail)).font(.headline)
                Text(snapshot.glyph == .claude ? "Claude" : snapshot.glyph == .openai ? "Codex" : snapshot.displayName)
                    .font(.caption).foregroundStyle(.white.opacity(0.62))
                Spacer()
                Button("Detalhes") { pinnedDetails = true }.buttonStyle(.borderless)
                Button("Orçamento") { showsBudget = true }.buttonStyle(.borderless)
            }
            Text(identity ?? "Identidade não confirmada").font(.caption).foregroundStyle(.white.opacity(0.62))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { compactLimits }
                VStack(alignment: .leading, spacing: 4) { compactLimits }
            }
            resetCreditsRow
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let health = self.health?.at(timeline.date)
                HStack {
                    Text(health?.title ?? "Aguardando atualização")
                        .foregroundStyle(health?.state == .current ? Color.white.opacity(0.62) : .orange)
                    if let date = health?.measuredAt { Text(date, style: .relative) }
                    if duplicated { Text("Login repetido").foregroundStyle(.orange) }
                }.font(.caption2).foregroundStyle(.white.opacity(0.62))
            }
        }
    }
    @ViewBuilder private var compactLimits: some View {
        ForEach(summaryWindows) { window in
            HStack(spacing: 4) {
                Text(window.label + ":")
                if let used = window.usedFraction {
                    Text((mode == .available ? Percent.halves(for: used).left : Percent.text(for: used)) + "% " + mode.title.lowercased()).bold()
                } else { Text("Não informado") }
            }.font(.caption)
        }
    }
    var body: some View {
        Group { if compact { compactBody } else { cardBody } }
        .padding(compact ? 18 : 22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: compact ? nil : 360, alignment: .topLeading)
        .background {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 26).fill(.clear)
                    .glassEffect(.regular.tint(.black.opacity(0.22)), in: RoundedRectangle(cornerRadius: 26))
            } else {
                RoundedRectangle(cornerRadius: 26).fill(.ultraThinMaterial)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(hovered ? 0.24 : 0.08)))
        .scaleEffect(hovered && !reduceMotion ? 1.012 : 1)
        .shadow(color: .black.opacity(hovered ? 0.18 : 0.06), radius: hovered ? 16 : 6, y: 6)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: hovered)
        .onHover { hovered = $0 }
        .sheet(isPresented: $showsBudget) {
            SpendingBudgetView(accountKey: accountKey,
                name: AccountNames.name(for: snapshot.id, fallback: snapshot.displayName, in: names, email: snapshot.accountEmail), records: records)
        }
        .popover(isPresented: Binding(get: { pinnedDetails || ringHovered }, set: { if !$0 { ringHovered = false; pinnedDetails = false } })) {
            TooltipCard(snapshot: snapshot, now: Date(), direction: .down,
                        resetTimeFormat: preferences.resetTimeFormat)
                .padding(12)
        }
    }
}
