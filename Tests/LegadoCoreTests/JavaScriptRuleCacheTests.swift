import Foundation
import Testing
@testable import LegadoCore

struct JavaScriptRuleCacheTests {
    @Test func diskReadBeforeExpiryDoesNotKeepTheValueAliveAfterItsDeadline() throws {
        let suite = "rss-cache-ttl-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = CacheTestClock()
        let writer = JavaScriptRuleCache(defaults: defaults, now: { clock.now() })
        writer.put("token", value: "temporary", saveTime: 10)

        // 模拟另一次进程生命周期：从同一持久存储加载，没有 writer 的内存条目。
        let reader = JavaScriptRuleCache(defaults: defaults, now: { clock.now() })
        clock.advance(by: 9)
        #expect(reader.get("token") == "temporary")
        #expect(reader.getFromMemory("token") == nil)

        clock.advance(by: 1)
        #expect(reader.get("token") == nil)
        #expect(reader.get("token", onlyDisk: true) == nil)
    }

    @Test func expiringWriteReplacesAnUnlimitedValueWithoutLeavingItInMemory() throws {
        let suite = "rss-cache-replace-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = CacheTestClock()
        let cache = JavaScriptRuleCache(defaults: defaults, now: { clock.now() })

        cache.put("token", value: "old")
        #expect(cache.getFromMemory("token") == "old")
        cache.put("token", value: "new", saveTime: 10)
        #expect(cache.getFromMemory("token") == nil)
        #expect(cache.get("token") == "new")

        clock.advance(by: 10)
        #expect(cache.get("token") == nil)
    }

    @Test func diskOnlyReadDoesNotPromoteValuesOrDeleteExplicitMemoryOverrides() throws {
        let suite = "rss-cache-disk-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = CacheTestClock()
        let cache = JavaScriptRuleCache(defaults: defaults, now: { clock.now() })

        cache.put("token", value: "disk", saveTime: 10)
        cache.deleteMemory("token")
        #expect(cache.get("token", onlyDisk: true) == "disk")
        #expect(cache.getFromMemory("token") == nil)
        cache.putMemory("token", value: "explicit")
        #expect(cache.get("token", onlyDisk: true) == "disk")
        #expect(cache.get("token") == "explicit")

        clock.advance(by: 10)
        #expect(cache.get("token", onlyDisk: true) == nil)
        #expect(cache.get("token") == "explicit")
        cache.deleteMemory("token")
        #expect(cache.get("token") == nil)
    }

    @Test func unlimitedDiskValuesRemainCacheableAndRemoveThePreviousDeadline() throws {
        let suite = "rss-cache-unlimited-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = CacheTestClock()
        let cache = JavaScriptRuleCache(defaults: defaults, now: { clock.now() })

        cache.put("token", value: "temporary", saveTime: 10)
        cache.put("token", value: "unlimited")
        cache.deleteMemory("token")
        clock.advance(by: 100)
        #expect(cache.get("token", onlyDisk: true) == "unlimited")
        #expect(cache.getFromMemory("token") == nil)
        #expect(cache.get("token") == "unlimited")
        #expect(cache.getFromMemory("token") == "unlimited")
        cache.delete("token")
        #expect(cache.get("token") == nil)
    }
}

private final class CacheTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_000)

    func now() -> Date { lock.withLock { date } }
    func advance(by seconds: TimeInterval) {
        lock.withLock { date = date.addingTimeInterval(seconds) }
    }
}
