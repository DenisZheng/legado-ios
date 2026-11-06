import Foundation

/// Small synchronous cache surface matching the Android Legado JavaScript `cache` object.
/// Persistent text entries use UserDefaults with an optional expiry; memory entries are
/// process-local; file entries live in the app's Caches directory.
final class JavaScriptRuleCache: @unchecked Sendable {
    static let shared = JavaScriptRuleCache()

    private struct Entry {
        let value: String
        let expiresAt: Date?
    }

    private let lock = NSLock()
    private var memory: [String: Entry] = [:]
    private let defaults = UserDefaults.standard
    private let prefix = "legado.rule.cache."
    private let memoryPrefix = "legado.rule.cache.memory."
    private let filePrefix = "legado-rule-cache-"

    private init() {}

    func put(_ key: String, value: String, saveTime: Int = 0) {
        let expiry = saveTime > 0 ? Date().addingTimeInterval(TimeInterval(saveTime)) : nil
        let entry = Entry(value: value, expiresAt: expiry)
        lock.lock()
        memory[key] = entry
        lock.unlock()

        let storageKey = prefix + key
        defaults.set(value, forKey: storageKey)
        if let expiry {
            defaults.set(expiry.timeIntervalSince1970, forKey: storageKey + ".expires")
        } else {
            defaults.removeObject(forKey: storageKey + ".expires")
        }
    }

    func get(_ key: String) -> String? {
        if let value = getFromMemory(key) { return value }
        let storageKey = prefix + key
        if let expiry = defaults.object(forKey: storageKey + ".expires") as? Double,
           expiry <= Date().timeIntervalSince1970 {
            defaults.removeObject(forKey: storageKey)
            defaults.removeObject(forKey: storageKey + ".expires")
            return nil
        }
        guard let value = defaults.string(forKey: storageKey) else { return nil }
        putMemory(key, value: value)
        return value
    }

    func putMemory(_ key: String, value: String) {
        lock.lock()
        memory[key] = Entry(value: value, expiresAt: nil)
        lock.unlock()
    }

    func getFromMemory(_ key: String) -> String? {
        lock.lock()
        let entry = memory[key]
        if let expiry = entry?.expiresAt, expiry <= Date() {
            memory.removeValue(forKey: key)
            lock.unlock()
            return nil
        }
        lock.unlock()
        return entry?.value
    }

    func deleteMemory(_ key: String) {
        lock.lock()
        memory.removeValue(forKey: key)
        lock.unlock()
    }

    func delete(_ key: String) {
        deleteMemory(key)
        defaults.removeObject(forKey: prefix + key)
        defaults.removeObject(forKey: prefix + key + ".expires")
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    func putFile(_ key: String, value: String, saveTime: Int = 0) throws {
        let url = fileURL(for: key)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(value.utf8).write(to: url, options: .atomic)
        if saveTime > 0 {
            defaults.set(Date().addingTimeInterval(TimeInterval(saveTime)).timeIntervalSince1970,
                         forKey: url.path + ".expires")
        } else {
            defaults.removeObject(forKey: url.path + ".expires")
        }
    }

    func getFile(_ key: String) -> String? {
        let url = fileURL(for: key)
        if let expiry = defaults.object(forKey: url.path + ".expires") as? Double,
           expiry <= Date().timeIntervalSince1970 {
            try? FileManager.default.removeItem(at: url)
            defaults.removeObject(forKey: url.path + ".expires")
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func fileURL(for key: String) -> URL {
        let name = Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filePrefix + name)
    }
}
