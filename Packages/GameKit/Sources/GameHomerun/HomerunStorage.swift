import Foundation

/// 保存先。蓄積は「プレイ記録を消去」の対象（`allKeys` に入れる）、台帳は対象外（補充の穴を塞ぐ）。
public enum HomerunStorage {
    public static let recordsKey = "homerun_records_v1"
    public static let ledgerKey = "homerun_ledger_v1"

    public static func loadRecords(_ defaults: UserDefaults = .standard) -> HomerunRecords {
        load(HomerunRecords.self, key: recordsKey, defaults) ?? HomerunRecords()
    }

    public static func saveRecords(_ records: HomerunRecords, _ defaults: UserDefaults = .standard) {
        save(records, key: recordsKey, defaults)
    }

    public static func loadLedger(_ defaults: UserDefaults = .standard) -> HomerunLedger {
        load(HomerunLedger.self, key: ledgerKey, defaults) ?? HomerunLedger()
    }

    public static func saveLedger(_ ledger: HomerunLedger, _ defaults: UserDefaults = .standard) {
        save(ledger, key: ledgerKey, defaults)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, _ defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func save<T: Encodable>(_ value: T, key: String, _ defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
