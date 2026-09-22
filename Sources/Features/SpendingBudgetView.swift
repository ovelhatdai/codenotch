import SwiftUI

struct SpendingBudgetView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SpendingBudget.key) private var data = Data()
    let accountKey: String
    let name: String
    let records: [ConsumptionHistory.Day]
    @State private var limit = ""
    @State private var currency = "BRL"
    @State private var useManual = false
    @State private var manualSpend = ""
    @State private var month = String(CodexTokenUsage.dayKey(for: Date(), calendar: .current).prefix(7))
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Orçamento · \(name)").font(.title2)
            Text("Aviso no painel quando o gasto informado atingir o orçamento. Este controle não bloqueia cobranças do serviço.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Mês (AAAA-MM)", text: $month)
            HStack {
                TextField("Orçamento do mês", text: $limit)
                Picker("Moeda", selection: $currency) {
                    ForEach(["BRL", "USD", "EUR"], id: \.self) { Text($0).tag($0) }
                }
            }
            Toggle("Informar o gasto manualmente", isOn: $useManual)
            if useManual { TextField("Gasto acumulado neste mês", text: $manualSpend) }
            else { Text("Será usado apenas o custo datado que o serviço fornecer, nesta moeda. Sem esse dado, o gasto aparece como não informado.").font(.caption) }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancelar") { dismiss() }
                Spacer()
                Button("Salvar orçamento") {
                    guard let value = number(limit), !useManual || number(manualSpend) != nil else {
                        error = "Informe valores válidos, sem símbolo de moeda."; return
                    }
                    do {
                        let budget = SpendingBudget(limit: value, currency: currency,
                            manualSpend: useManual ? number(manualSpend) : nil, month: month)
                        data = try SpendingBudget.save(budget, accountKey: accountKey, into: data)
                        dismiss()
                    } catch { self.error = "Confira mês, moeda e orçamento maior que zero." }
                }.buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 440).textFieldStyle(.roundedBorder)
        .onAppear { loadMonth() }
        .onChange(of: month) { _ in loadMonth() }
    }
    private func loadMonth() {
        let saved = SpendingBudget.budget(in: data, accountKey: accountKey, month: month)
        limit = saved.map { String($0.limit) } ?? ""
        currency = saved?.currency ?? "BRL"
        useManual = saved?.manualSpend != nil
        manualSpend = saved?.manualSpend.map { String($0) } ?? ""
    }
    private func number(_ string: String) -> Double? {
        Double(string.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}
