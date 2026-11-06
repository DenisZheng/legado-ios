import UIKit

// 独立的模拟器测试应用，通过系统导出流程准备 Files 文件；不进入正式 App。
@main
@MainActor
final class FixtureAppDelegate: UIResponder, UIApplicationDelegate, UIDocumentPickerDelegate {
    var window: UIWindow?
    private let status = UILabel()
    private var fixtureDirectory: URL?

    private func prepareFixtures() throws -> URL {
        let name = UserDefaults.standard.string(forKey: "fixtureFolderName") ?? "Legado Import Fixtures"
        guard name.hasPrefix("Legado Import Fixtures"), !name.contains("/"), !name.contains("\\") else {
            throw NSError(domain: "SourceImportFixtures", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "非法夹具目录名称"])
        }
        let documents = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let fixtures = [
            ("JSON-Source.json", "https://file-import.test/json", "文件导入 JSON 测试"),
            ("JSON-Uppercase.JSON", "https://file-import.test/uppercase", "文件导入大写扩展名测试"),
            ("JSON-Text.txt", "https://file-import.test/text", "文件导入文本扩展名测试")
        ]
        for (name, url, title) in fixtures {
            let source = [["bookSourceUrl": url, "bookSourceName": title]]
            try JSONSerialization.data(withJSONObject: source).write(to: documents.appendingPathComponent(name))
        }
        let rssSources: [[String: String]] = [[
            "sourceUrl": "https://rss-file-import.test/feed",
            "sourceName": "本地 RSS 文件导入测试",
            "ruleArticles": "$.items",
            "ruleTitle": "$.title",
            "ruleLink": "$.link"
        ]]
        try JSONSerialization.data(withJSONObject: rssSources).write(to: documents.appendingPathComponent("RSS-Source.json"))
        for name in ["TXT-Book.txt", "TXT-Uppercase.TXT"] {
            try Data("第一章 开始\n这是用于验证本地 TXT 导入的小说正文。\n第二章 后续\n正文继续。".utf8)
                .write(to: documents.appendingPathComponent(name))
        }
        guard let epub = Bundle.main.url(forResource: "EPUB-Book", withExtension: "epub") else {
            throw CocoaError(.fileNoSuchFile)
        }
        try Data(contentsOf: epub).write(to: documents.appendingPathComponent("EPUB-Book.epub"))
        return documents
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        status.numberOfLines = 0
        status.frame = CGRect(x: 20, y: 100, width: 350, height: 120)
        status.accessibilityIdentifier = "fixtureStatus"
        controller.view.addSubview(status)
        let export = UIButton(type: .system)
        export.setTitle("存储导入夹具", for: .normal)
        export.accessibilityIdentifier = "exportImportFixtures"
        export.frame = CGRect(x: 20, y: 240, width: 350, height: 60)
        export.addTarget(self, action: #selector(exportFixtures), for: .touchUpInside)
        controller.view.addSubview(export)
        do {
            fixtureDirectory = try prepareFixtures()
            status.text = "夹具待存储"
        } catch {
            status.text = "夹具生成失败：\(error)"
            export.isEnabled = false
        }
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = controller
        window?.makeKeyAndVisible()
        return true
    }

    @objc private func exportFixtures() {
        guard let fixtureDirectory else { return }
        let picker = UIDocumentPickerViewController(forExporting: [fixtureDirectory], asCopy: true)
        picker.delegate = self
        window?.rootViewController?.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let original = fixtureDirectory, urls.count == 1, let saved = urls.first else {
            status.text = "夹具存储失败：返回目录数量错误"
            return
        }
        let scoped = saved.startAccessingSecurityScopedResource()
        defer { if scoped { saved.stopAccessingSecurityScopedResource() } }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: original, includingPropertiesForKeys: nil)
            var coordinationError: NSError?
            var verification: Result<Void, Error>?
            NSFileCoordinator().coordinate(readingItemAt: saved, options: [], error: &coordinationError) { directory in
                verification = Result {
                    for file in files {
                        guard try Data(contentsOf: file) == Data(contentsOf: directory.appendingPathComponent(file.lastPathComponent)) else {
                            throw NSError(domain: "SourceImportFixtures", code: 2,
                                          userInfo: [NSLocalizedDescriptionKey: "存储后文件内容不一致：\(file.lastPathComponent)"])
                        }
                    }
                }
            }
            if let coordinationError { throw coordinationError }
            guard let verification else { throw CocoaError(.fileReadUnknown) }
            try verification.get()
            status.text = "夹具已存储并校验：\(files.count)"
        } catch {
            status.text = "夹具存储校验失败：\(error)"
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        status.text = "夹具存储已取消"
    }
}
