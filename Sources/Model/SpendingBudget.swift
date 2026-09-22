import Foundation

struct SpendingBudget: Codable, Equatable {
    var limit: Double
    var currency: String
    var manualSpend: Double?
    var month: String
    var sourceLabel: String { manualSpend == nil ? "Leitura do serviço" : "Informado por você" }
    static let key = "monthlySpendingBudgets"
    static func load(_ data: Data) -> [String: Self] { (try? JSONDecoder().decode([String: Self].self, from: data)) ?? [:] }
    static var currentMonth: String {
        String(CodexTokenUsage.dayKey(for: Date(), calendar: .current).prefix(7))
    }
    static func budget(in data: Data, accountKey: String, month: String = currentMonth) -> Self? {
        let values = load(data)
        return values[accountKey + ":" + month] ?? values[accountKey].flatMap { $0.month == month ? $0 : nil }
    }
    static func save(_ budget: Self, accountKey: String, into data: Data) throws -> Data {
        guard budget.limit.isFinite, budget.limit > 0,
              budget.manualSpend.map({ $0.isFinite && $0 >= 0 }) ?? true,
              budget.currency.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil,
              budget.month.range(of: "^[0-9]{4}-(0[1-9]|1[0-2])$", options: .regularExpression) != nil
        else { throw Validation.invalid }
        var values = load(data)
        if let previous = values.removeValue(forKey: accountKey) {
            values[accountKey + ":" + previous.month] = previous
        }
        values[accountKey + ":" + budget.month] = budget
        return try JSONEncoder().encode(values)
    }
    enum Validation: Error { case invalid }
    func costDays(in records: [ConsumptionHistory.Day]) -> Int {
        records.filter { $0.day.hasPrefix(month + "-") && $0.costs[currency] != nil }.count
    }
    func spent(records: [ConsumptionHistory.Day]) -> Double? {
        if let manualSpend { return manualSpend }
        let amounts = records.filter { $0.day.hasPrefix(month + "-") }.compactMap { $0.costs[currency] }
        return amounts.isEmpty ? nil : amounts.reduce(0, +)
    }
}
