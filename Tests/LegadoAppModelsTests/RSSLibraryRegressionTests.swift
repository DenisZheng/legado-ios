import Foundation
import Testing
import LegadoCore
@testable import LegadoAppModels

@MainActor
struct RSSLibraryRegressionTests {
    @Test func importsRSSSourcesFromLocalJSONFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LegadoDatabase(url: directory.appendingPathComponent("rss.sqlite3"))
        let fileURL = directory.appendingPathComponent("rssSources.json")
        let json = """
        [
          {
            "sourceUrl": "https://local-rss-import.test/feed",
            "sourceName": "本地文件 RSS 测试",
            "sourceGroup": "测试",
            "enabled": true,
            "type": 0
          }
        ]
        """
        try Data(json.utf8).write(to: fileURL)

        let model = RSSLibraryModel(database: database)
        await model.load()
        await model.importFiles([fileURL])

        #expect(model.errorMessage == nil)
        #expect(model.sources.map(\.sourceName) == ["本地文件 RSS 测试"])
        #expect(model.successMessage?.contains("新增 1 个") == true)
        #expect(try await database.loadRssSources().map(\.sourceUrl) == ["https://local-rss-import.test/feed"])
    }

    @Test func importsPickedRSSFilesWithMixedExtensions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LegadoDatabase(url: directory.appendingPathComponent("rss.sqlite3"))
        let first = RssSource(sourceUrl: "https://picked-rss.test/one", sourceName: "第一个文件")
        let second = RssSource(sourceUrl: "https://picked-rss.test/two", sourceName: "第二个文件")
        let urls = [directory.appendingPathComponent("source.JSON"), directory.appendingPathComponent("source.txt")]
        try JSONEncoder().encode([first]).write(to: urls[0])
        try JSONEncoder().encode([second]).write(to: urls[1])

        let files = urls.map { SourceImportFile(url: $0) }
        let model = RSSLibraryModel(database: database)
        await model.importPickedFiles(files)

        #expect(model.errorMessage == nil)
        #expect(model.successMessage?.contains("读取 2 个文件") == true)
        #expect(Set(try await database.loadRssSources().map(\.sourceUrl)) == [first.sourceUrl, second.sourceUrl])
    }

    @Test(arguments: ["folder", "missing", "invalid-json"])
    func pickedFileFailureDoesNotSaveAPartialImport(failure: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LegadoDatabase(url: directory.appendingPathComponent("rss.sqlite3"))
        let validURL = directory.appendingPathComponent("valid.json")
        let source = RssSource(sourceUrl: "https://picked-rss.test/valid", sourceName: "有效文件")
        try JSONEncoder().encode([source]).write(to: validURL)
        let invalidURL = directory.appendingPathComponent(failure)
        switch failure {
        case "folder": try FileManager.default.createDirectory(at: invalidURL, withIntermediateDirectories: true)
        case "invalid-json": try Data("not JSON".utf8).write(to: invalidURL)
        default: break
        }

        let model = RSSLibraryModel(database: database)
        await model.importPickedFiles([validURL, invalidURL].map { SourceImportFile(url: $0) })

        #expect(model.errorMessage != nil)
        #expect(model.successMessage == nil)
        #expect(model.sources.isEmpty)
        #expect(try await database.loadRssSources().isEmpty)
        if failure == "folder" {
            #expect(model.errorMessage == RSSSourceImportError.notAFile.localizedDescription)
        }
    }

    @Test func explicitContentRefreshReplacesTheExistingDescription() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LegadoDatabase(url: directory.appendingPathComponent("rss.sqlite3"))
        let transport = RSSSequenceTransport(bodies: [#"{"content":"更新后的正文"}"#])
        let model = RSSLibraryModel(database: database, service: .init(transport: transport, networkPolicy: .init()))
        var source = source()
        source.ruleContent = "$.content"
        var article = RssArticle(origin: source.sourceUrl, sort: "全部", title: "文章", link: source.sourceUrl + "/one")
        article.description = "旧正文"
        #expect(await model.readingMode(for: article, source: source) == .html(content: "旧正文", baseURL: article.link))
        let refreshed = await model.readingMode(for: article, source: source, forceRefresh: true)
        #expect(refreshed == .html(content: "更新后的正文", baseURL: article.link))
        #expect(try await database.findRssArticle(origin: source.sourceUrl, link: article.link)?.description == "更新后的正文")
    }

    @Test func searchesDoNotMixPreviousQueriesOrTheCachedFeed() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LegadoDatabase(url: directory.appendingPathComponent("rss.sqlite3"))
        let transport = RSSSequenceTransport(bodies: [
            #"{"items":[{"title":"旧搜索","link":"/old"}]}"#,
            #"{"items":[{"title":"新搜索","link":"/new"}]}"#,
            #"{"items":[]}"#
        ])
        let model = RSSLibraryModel(database: database, service: .init(transport: transport, networkPolicy: .init()))
        let source = source()
        let cached = RssArticle(origin: source.sourceUrl, sort: "全部", title: "缓存文章", link: "/cached")
        try await database.putRssArticles([cached])
        await model.refresh(source, sortName: "搜索", key: "old")
        #expect(model.articles.map(\.title) == ["旧搜索"])
        await model.refresh(source, sortName: "搜索", key: "new")
        #expect(model.articles.map(\.title) == ["新搜索"])
        await model.refresh(source, sortName: "搜索", key: "missing")
        #expect(model.articles.isEmpty)
        #expect(try await database.loadRssArticles(origin: source.sourceUrl, sort: "全部") == [cached])
    }

    @Test func failedRefreshKeepsTheExistingPageAndNextPageCursor() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LegadoDatabase(url: directory.appendingPathComponent("rss.sqlite3"))
        let transport = RSSSequenceTransport(bodies: [
            #"{"items":[{"title":"第一页","link":"/one"}],"next":"/page2"}"#,
            nil,
            #"{"items":[{"title":"第二页","link":"/two"}]}"#
        ])
        let model = RSSLibraryModel(database: database, service: .init(transport: transport, networkPolicy: .init()))
        var source = source()
        source.ruleNextPage = "$.next"
        await model.refresh(source)
        await model.refresh(source)
        #expect(model.errorMessage != nil)
        #expect(model.articles.map(\.title) == ["第一页"])
        await model.loadMore(source)
        #expect(model.articles.map(\.title) == ["第一页", "第二页"])
        #expect(await transport.requestCount() == 3)
    }

    @Test func searchPaginationDeduplicatesResultsAndPreservesReadState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LegadoDatabase(url: directory.appendingPathComponent("rss.sqlite3"))
        let transport = RSSSequenceTransport(bodies: [
            #"{"items":[{"title":"第一篇","link":"/one"}],"next":"/page2"}"#,
            #"{"items":[{"title":"第一篇","link":"/one"},{"title":"第二篇","link":"/two"}]}"#
        ])
        let model = RSSLibraryModel(database: database, service: .init(transport: transport, networkPolicy: .init()))
        var source = source()
        source.ruleNextPage = "$.next"
        await model.refresh(source, sortName: "搜索", key: "test")
        let article = try #require(model.articles.first)
        await model.read(article)
        await model.toggleStar(article)
        await model.loadMore(source, sortName: "搜索", key: "test")
        #expect(model.articles.map(\.title) == ["第一篇", "第二篇"])
        #expect(model.articles.first?.read == true)
        #expect(model.isStarred(article))
    }

    @Test func failedRuleEvaluationPreservesPersistedArticles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LegadoDatabase(url: directory.appendingPathComponent("rss.sqlite3"))
        let transport = RSSSequenceTransport(bodies: [#"{"items":[{"title":"已有文章","link":"/one"}]}"#, "{}"])
        let model = RSSLibraryModel(database: database, service: .init(transport: transport, networkPolicy: .init()))
        var source = source()
        source.ruleNextPage = "PAGE"
        await model.refresh(source)
        source.ruleArticles = "@js:throw new Error('broken rule')"
        await model.refresh(source)
        #expect(model.errorMessage != nil)
        #expect(model.articles.map(\.title) == ["已有文章"])
        #expect(try await database.loadRssArticles(origin: source.sourceUrl, sort: source.sourceName).map(\.title) == ["已有文章"])
    }

    private func source() -> RssSource {
        var source = RssSource(sourceUrl: "https://rss-model.test", sourceName: "全部")
        source.ruleArticles = "$.items"
        source.ruleTitle = "$.title"
        source.ruleLink = "$.link"
        return source
    }
}

private actor RSSSequenceTransport: HTTPTransport {
    private var bodies: [String?]
    private var count = 0
    init(bodies: [String?]) { self.bodies = bodies }
    func data(for request: URLRequest) async throws -> HTTPResponse {
        count += 1
        guard !bodies.isEmpty, let body = bodies.removeFirst() else { throw URLError(.networkConnectionLost) }
        return .init(data: Data(body.utf8), statusCode: 200, headers: [:], finalURL: request.url!)
    }
    func requestCount() -> Int { count }
}
