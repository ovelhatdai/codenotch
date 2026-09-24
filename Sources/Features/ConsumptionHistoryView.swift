import SwiftUI

struct ConsumptionHistoryView: View {
    @ObservedObject var history: ConsumptionHistory
    let snapshots: [ProviderSnapshot]
    let summaries: [ProviderSummary]
    @AppStorage(AccountNames.key) private var names = Data()
    @State private var period = 30
    private var distinctAccounts: [ProviderSnapshot] {
        var seen = Set<String>()
        return snapshots.filter { snapshot in
            let email = summaries.first { $0.id == snapshot.providerID }?.account?.label
            return seen.insert(ConsumptionHistory.accountKey(providerID: snapshot.providerID, email: email)).inserted
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Período", selection: $period) {
                Text("30 dias").tag(30); Text("90 dias").tag(90); Text("180 dias").tag(180)
            }.pickerStyle(.segmented).frame(maxWidth: 360)
            Text("Limites: picos observados enquanto o monitor esteve ativo. Tokens e custos: dias fornecidos pelo serviço. Ausência de dados não significa consumo zero.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = history.persistenceError { Text(error).foregroundStyle(.orange) }
            ForEach(distinctAccounts) { snapshot in
                let email = summaries.first { $0.id == snapshot.providerID }?.account?.label
                let cutoff = CodexTokenUsage.dayKey(for: Calendar.current.date(byAdding: .day, value: 1 - period, to: Date())!, calendar: .current)
                let records = history.records(providerID: snapshot.providerID, email: email, since: cutoff)
                DisclosureGroup {
                    if records.isEmpty { Text("Ainda sem histórico desta conta.").foregroundStyle(.secondary) }
                    else {
                        let summary = ConsumptionHistory.summarize(records)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(summary.observedDays) dias com limites observados · \(summary.daysAtLimit) dias atingiram algum limite")
                            if let peak = summary.highestObservedFraction {
                                Text("Maior uso de limite observado: \(Percent.text(for: peak))%")
                                Text("Compare os picos entre contas. Intervalos sem leitura podem esconder uso maior; este percentual não é o consumo acumulado do período.")
                                    .foregroundStyle(.secondary)
                            }
                            if let day = summary.highestTokenDay, let tokens = day.tokens {
                                Text("Maior consumo diário informado: \(tokens.formatted()) tokens em \(day.day)")
                            } else {
                                Text("Tokens diários não informados pelo serviço.").foregroundStyle(.secondary)
                            }
                            if summary.monthlyCosts.isEmpty {
                                Text("Custos não informados pelo serviço.").foregroundStyle(.secondary)
                            }
                            ForEach(summary.monthlyCosts.keys.sorted().reversed(), id: \.self) { month in
                                ForEach(summary.monthlyCosts[month]!.keys.sorted(), id: \.self) { currency in
                                    Text("\(month): \(summary.monthlyCosts[month]![currency]!, format: .currency(code: currency)) · \(summary.costDays[month]![currency]!) dias informados neste período")
                                }
                            }
                        }.font(.caption).padding(.vertical, 8)
                        ForEach(records.reversed()) { day in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day.day).font(.subheadline.bold())
                                if let tokens = day.tokens { Text("Tokens do dia: \(tokens.formatted())") }
                                if let input = day.inputTokens, let output = day.outputTokens {
                                    Text("Entrada: \(input.formatted()) · saída: \(output.formatted())")
                                }
                                ForEach(day.costs.keys.sorted(), id: \.self) { currency in
                                    Text("Custo informado: \(day.costs[currency]!, format: .currency(code: currency))")
                                }
                                ForEach(day.displayQuotaIDs, id: \.self) { id in
                                    let quota = day.quotas[id]!
                                    Text("\(quota.label): pico observado de \(Percent.text(for: quota.maximum))% usado")
                                        .foregroundStyle(.secondary)
                                }
                            }.font(.caption).padding(.vertical, 6)
                            Divider()
                        }
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text(AccountNames.name(for: snapshot.id, fallback: snapshot.displayName, in: names, email: snapshot.accountEmail)).font(.headline)
                        Text("\(snapshot.glyph == .claude ? "Claude" : snapshot.glyph == .openai ? "Codex" : snapshot.displayName) · \(email ?? "Identidade não confirmada")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
            }
        }
    }
}
