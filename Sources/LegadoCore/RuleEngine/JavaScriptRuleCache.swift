import Foundation

/// Small synchronous cache surface matching the Android Legado JavaScript `cache` object.
/// Persistent text entries use UserDefaults with an optional expiry; memory entries are
/// process-local; file entries live in the app's Caches directory.
public final class JavaScriptRuleCache: @unchecked Sendable {
    public static let shared = JavaScriptRuleCache()

    private struct Entry {
        let value: String
        let expiresAt: Date?
    }

    // get/delete 会复用内存方法；递归锁让内存和持久文本的读写保持同一临界区。
    private let lock = NSRecursiveLock()
    private var memory: [String: Entry] = [:]
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let prefix = "legado.rule.cache."
    private let memoryPrefix = "legado.rule.cache.memory."
    private let filePrefix = "legado-rule-cache-"

    // 独立存储与时钟供契约回归使用；正式调用仍通过 shared。
    init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
    }

    public func put(_ key: String, value: String, saveTime: Int = 0) {
        lock.lock()
        defer { lock.unlock() }
        let expiry = saveTime > 0 ? now().addingTimeInterval(TimeInterval(saveTime)) : nil
        let entry = Entry(value: value, expiresAt: expiry)
        // Android CacheManager 只把不限时的持久条目放入内存；限时覆盖也要清除旧值。
        if expiry == nil { memory[key] = entry }
        else { memory.removeValue(forKey: key) }

        let storageKey = prefix + key
        defaults.set(value, forKey: storageKey)
        if let expiry {
            defaults.set(expiry.timeIntervalSince1970, forKey: storageKey + ".expires")
        } else {
            defaults.removeObject(forKey: storageKey + ".expires")
        }
    }

    public func get(_ key: String, onlyDisk: Bool = false) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if !onlyDisk, let value = getFromMemory(key) { return value }
        let storageKey = prefix + key
        let expiry = defaults.object(forKey: storageKey + ".expires") as? Double
        if let expiry, expiry <= now().timeIntervalSince1970 {
            defaults.removeObject(forKey: storageKey)
            defaults.removeObject(forKey: storageKey + ".expires")
            return nil
        }
        guard let value = defaults.string(forKey: storageKey) else { return nil }
        // putMemory 没有期限，不能把即将过期的磁盘值提升成永久缓存。
        if !onlyDisk && expiry == nil { putMemory(key, value: value) }
        return value
    }

    public func putMemory(_ key: String, value: String) {
        lock.lock()
        memory[key] = Entry(value: value, expiresAt: nil)
        lock.unlock()
    }

    public func getFromMemory(_ key: String) -> String? {
        lock.lock()
        let entry = memory[key]
        if let expiry = entry?.expiresAt, expiry <= now() {
            memory.removeValue(forKey: key)
            lock.unlock()
            return nil
        }
        lock.unlock()
        return entry?.value
    }

    public func deleteMemory(_ key: String) {
        lock.lock()
        memory.removeValue(forKey: key)
        lock.unlock()
    }

    public func delete(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        deleteMemory(key)
        defaults.removeObject(forKey: prefix + key)
        defaults.removeObject(forKey: prefix + key + ".expires")
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    public func putFile(_ key: String, value: String, saveTime: Int = 0) throws {
        let url = fileURL(for: key)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(value.utf8).write(to: url, options: .atomic)
        if saveTime > 0 {
            defaults.set(now().addingTimeInterval(TimeInterval(saveTime)).timeIntervalSince1970,
                         forKey: url.path + ".expires")
        } else {
            defaults.removeObject(forKey: url.path + ".expires")
        }
    }

    public func getFile(_ key: String) -> String? {
        let url = fileURL(for: key)
        if let expiry = defaults.object(forKey: url.path + ".expires") as? Double,
           expiry <= now().timeIntervalSince1970 {
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
