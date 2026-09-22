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
    func show(store: UsageStore, preferences: Preferences) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
        panel.title = "Dashboard de consumo"
        panel.minSize = NSSize(width: 380, height: 420)
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName("usageDashboardFrame")
        panel.contentView = NSHostingView(rootView: UsageDashboard(store: store, preferences: preferences,
            moveTo: { [weak self] screen in self?.move(to: screen)
            }, stayOnTop: { panel.level = $0 ? .floating : .normal }))
        window = panel
        panel.delegate = self
        if !panel.setFrameUsingName("usageDashboardFrame") { panel.center() }
        if let id = defaults.string(forKey: "dashboardLastMonitor"),
           let screen = NSScreen.screens.first(where: { $0.displayIdentifier == id }) { move(to: screen) }
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
                    Text(title).font(.title3.bold())
                    Text("\(snapshots.count) perfis").font(.caption).foregroundStyle(.secondary)
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
                    Text("Suas contas, lado a lado").font(.title2.bold())
                    Text("Uso, saldo e renovação por perfil").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Atualizar") { store.refreshNow() }
            }
            ViewThatFits(in: .horizontal) {
              HStack { filterPicker; Spacer(); monitorMenu }
              VStack(alignment: .leading) { filterPicker; monitorMenu }
            }
            ViewThatFits(in: .horizontal) {
                HStack { organizationControls }
                VStack(alignment: .leading) { organizationControls }
            }
            Picker("Página", selection: $page) {
                Text("Contas").tag("accounts"); Text("Histórico").tag("history")
            }.pickerStyle(.segmented).frame(maxWidth: 280)
            Toggle("Manter sobre as outras janelas", isOn: $floating)
                .onChange(of: floating) { _, value in stayOnTop(value) }
                .onAppear { stayOnTop(floating) }
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
        .frame(minWidth: 340, minHeight: 380)
        .background(Color(nsColor: .windowBackgroundColor))
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
                Menu("Monitor") {
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        Button("\(index + 1) · \(screen.localizedName)") { moveTo(screen) }
                    }
                }.fixedSize()
            }
    @ViewBuilder private var organizationControls: some View {
        Picker("Agrupar", selection: $grouping) {
            Text("Por serviço").tag("service"); Text("Por conta").tag("person")
        }.frame(maxWidth: 260)
        Picker("Exibição", selection: $layout) {
            Text("Cartões").tag("cards"); Text("Lista compacta").tag("list")
        }.frame(maxWidth: 260)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var summaryWindows: [LimitWindow] {
        let selected = [snapshot.headline, snapshot.weeklyWindow].compactMap { $0 }
        return selected.isEmpty ? Array(snapshot.windows.prefix(2)) : selected
    }
    private var accountKey: String { ConsumptionHistory.accountKey(providerID: snapshot.providerID, email: identity) }
    private var records: [ConsumptionHistory.Day] { history?.records(providerID: snapshot.providerID, email: identity, since: "") ?? [] }
    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ProviderRing(usedFraction: snapshot.hasReading ? snapshot.ringFraction : nil,
                             glyph: snapshot.glyph, customIconFilename: snapshot.customIconFilename,
                             isStale: snapshot.status.isStale || !snapshot.hasReading,
                             isBlocked: snapshot.block != nil, isRefreshing: refreshing,
                             displayMode: mode)
                VStack(alignment: .leading, spacing: 4) {
                    Text(AccountNames.name(for: snapshot.id, fallback: snapshot.displayName, in: names, email: snapshot.accountEmail))
                        .font(.headline).lineLimit(1)
                    Text(snapshot.glyph == .claude ? "Claude Code" : snapshot.glyph == .openai ? "Codex / OpenAI" : snapshot.displayName)
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(identity ?? "Identidade ainda não confirmada")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(mode.text(for: snapshot)).font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(mode.title.lowercased()).font(.callout).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(summaryWindows) { window in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(window.label).font(.caption)
                            Spacer()
                            if let fraction = window.usedFraction {
                                Text((mode == .available ? Percent.halves(for: fraction).left : Percent.text(for: fraction)) + "%")
                                    .font(.caption.monospacedDigit())
                            }
                        }
                        if let fraction = window.usedFraction {
                            ProgressView(value: mode.fraction(for: fraction))
                                .tint(UsageBand.band(for: fraction, watchLimit: preferences.watchLimit,
                                                     criticalLimit: preferences.criticalLimit).color(accent: preferences.accentColor.color))
                        }
                        if let money = window.money {
                            Text("Saldo: \(money.remaining, format: .currency(code: money.currency)) · gasto informado: \(money.spent, format: .currency(code: money.currency))")
                                .font(.caption2)
                        } else if let unit = window.unit {
                            if let remaining = window.remaining { Text("\(remaining) \(unit.title) restantes").font(.caption2) }
                            if let used = window.used { Text("\(used) \(unit.title) usados").font(.caption2) }
                        } else if window.usedFraction == nil {
                            Text(window.usedText ?? window.detail ?? "Unidade não informada").font(.caption2)
                        }
                        if let reset = window.resetsAt {
                            HStack { Text("Renova em"); Text(reset, style: .relative) }
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if !snapshot.hasReading { Text("Aguardando leitura").font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            Spacer(minLength: 0)
            HStack {
                Button("Ver detalhes") { pinnedDetails = true }.buttonStyle(.borderless)
                Spacer()
                if duplicated {
                    Text("Login repetido").font(.caption2).foregroundStyle(.orange)
                        .help("Outro perfil deste serviço está usando o mesmo e-mail.")
                }
            }
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let health = self.health?.at(timeline.date)
                VStack(alignment: .leading, spacing: 2) {
                    Text(health?.title ?? "Aguardando atualização")
                        .foregroundStyle(health?.state == .current ? Color.secondary : .orange)
                    if let date = health?.measuredAt {
                        HStack(spacing: 3) { Text("Lido"); Text(date, style: .relative); Text("atrás") }
                            .foregroundStyle(.secondary)
                    }
                }.font(.caption2)
            }
            HStack {
                Button("Orçamento") { showsBudget = true }.buttonStyle(.borderless)
                if let budget = SpendingBudget.budget(in: budgets, accountKey: accountKey) {
                    if let spent = budget.spent(records: records) {
                        Text("\(spent, format: .currency(code: budget.currency)) / \(budget.limit, format: .currency(code: budget.currency))")
                            .font(.caption).foregroundStyle(spent >= budget.limit ? .orange : .secondary)
                    } else { Text("Gasto não informado").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if let budget = SpendingBudget.budget(in: budgets, accountKey: accountKey) {
                Text("\(budget.month) · \(budget.sourceLabel) · aviso, sem bloqueio").font(.caption2).foregroundStyle(.secondary)
                if let spent = budget.spent(records: records), spent >= budget.limit {
                    Text("Orçamento atingido").font(.caption.bold()).foregroundStyle(.orange)
                }
                if budget.manualSpend == nil {
                    Text("Custo disponível em \(budget.costDays(in: records)) dia(s) do mês")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let message = snapshot.statusMessage { Text(message).font(.caption).foregroundStyle(.orange).lineLimit(2) }
        }
    }
    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AccountNames.name(for: snapshot.id, fallback: snapshot.displayName, in: names, email: snapshot.accountEmail)).font(.headline)
                Text(snapshot.glyph == .claude ? "Claude" : snapshot.glyph == .openai ? "Codex" : snapshot.displayName)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Detalhes") { pinnedDetails = true }.buttonStyle(.borderless)
                Button("Orçamento") { showsBudget = true }.buttonStyle(.borderless)
            }
            Text(identity ?? "Identidade não confirmada").font(.caption).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { compactLimits }
                VStack(alignment: .leading, spacing: 4) { compactLimits }
            }
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let health = self.health?.at(timeline.date)
                HStack {
                    Text(health?.title ?? "Aguardando atualização")
                        .foregroundStyle(health?.state == .current ? Color.secondary : .orange)
                    if let date = health?.measuredAt { Text(date, style: .relative) }
                    if duplicated { Text("Login repetido").foregroundStyle(.orange) }
                }.font(.caption2).foregroundStyle(.secondary)
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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: compact ? nil : 420, alignment: .topLeading)
        .background(.white.opacity(hovered ? 0.09 : 0.045), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(hovered ? 0.24 : 0.10)))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: hovered)
        .onHover { hovered = $0 }
        .sheet(isPresented: $showsBudget) {
            SpendingBudgetView(accountKey: accountKey,
                name: AccountNames.name(for: snapshot.id, fallback: snapshot.displayName, in: names, email: snapshot.accountEmail), records: records)
        }
        .popover(isPresented: Binding(get: { pinnedDetails }, set: { if !$0 { hovered = false; pinnedDetails = false } })) {
            TooltipCard(snapshot: snapshot, now: Date(), direction: .down,
                        resetTimeFormat: preferences.resetTimeFormat)
                .padding(12)
        }
    }
}
