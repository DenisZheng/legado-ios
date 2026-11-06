import SwiftUI
@preconcurrency import WebKit
import UIKit

enum RSSWebAction {
    case showPhoto(String)
    case searchBook(key: String, scope: String?)
    case addBook(String)
    case open(name: String, url: String?, title: String?, origin: String?)
    case openBrowser(String)
    case openExternal(String)
    case message(String)
    case download(url: String, fileName: String)
}

struct RSSWebReaderView: UIViewRepresentable {
    let mode: RSSReadingMode
    let source: RssSource
    let onTextChange: (String) -> Void
    let onAction: (RSSWebAction) -> Void

    init(mode: RSSReadingMode, source: RssSource, onTextChange: @escaping (String) -> Void = { _ in }, onAction: @escaping (RSSWebAction) -> Void = { _ in }) {
        self.mode = mode
        self.source = source
        self.onTextChange = onTextChange
        self.onAction = onAction
    }

    func makeCoordinator() -> Coordinator { Coordinator(source: source, onTextChange: onTextChange, onAction: onAction) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = source.enableJs
        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.configureScripts(for: mode, in: webView)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(ReadingTheme.canvas)
        webView.scrollView.backgroundColor = UIColor(ReadingTheme.canvas)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        context.coordinator.installRulesAndLoad(mode: mode, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(source: source)
        context.coordinator.configureScripts(for: mode, in: webView)
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onAction = onAction
        context.coordinator.loadIfChanged(mode: mode, in: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "legado")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private var source: RssSource
        var onTextChange: (String) -> Void
        var onAction: (RSSWebAction) -> Void
        private var signature = ""
        private var rulesInstalled = false
        private var bridgeEnabled = false
        private var trustedMainFrameOrigin: String?
        private let htmlProcessor = RSSHTMLProcessor()
        private var analyzeContent: JSONValue = .string("")
        private var analyzeBaseURL = ""
        private var analyzeRedirectURL: String?
        private var analyzeVariables: [String: String] = [:]

        init(source: RssSource, onTextChange: @escaping (String) -> Void, onAction: @escaping (RSSWebAction) -> Void) { self.source = source; self.onTextChange = onTextChange; self.onAction = onAction }
        func update(source: RssSource) { self.source = source }

        func configureScripts(for mode: RSSReadingMode, in webView: WKWebView) {
            let controller = webView.configuration.userContentController
            controller.removeAllUserScripts()
            controller.removeScriptMessageHandler(forName: "legado")
            bridgeEnabled = mode.allowsNativeBridge
            guard bridgeEnabled else { return }

            controller.add(self, name: "legado")
            controller.addUserScript(.init(
                source: bridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
            if let preload = source.preloadJs?.trimmedNonEmpty {
                controller.addUserScript(.init(
                    source: preload,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                ))
            }
            if let inject = source.injectJs?.trimmedNonEmpty {
                controller.addUserScript(.init(
                    source: inject,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                ))
            }
        }

        var bridgeScript: String {
            let sourceJSON = (try? JSONEncoder().encode(source)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            return """
            (() => {
              const native = (action, payload) => window.webkit.messageHandlers.legado.postMessage(Object.assign({action}, payload || {}));
              const get = key => window.prompt('__legado_get__', String(key)) || '';
              const put = (key, value) => { value = String(value ?? ''); native('put', {key:String(key), value}); return value; };
              const nativeCall = (name, payload) => {
                const raw = window.prompt(name, JSON.stringify(payload || {}));
                if (raw == null || raw === '') return null;
                try { return JSON.parse(raw); } catch (_) { return raw; }
              };
              const ruleCall = payload => {
                const result = window.prompt('__legado_rule__', JSON.stringify(payload));
                if (result == null || result === '') return null;
                try { return JSON.parse(result); } catch (_) { return result; }
              };
              const evaluateJS = script => {
                const result = window.prompt('__legado_js__', JSON.stringify({script:String(script)}));
                if (result == null || result === '') return null;
                try { return JSON.parse(result); } catch (_) { return result; }
              };
              const analyzer = {
                setContent(content, baseUrl) { if (content == null) throw new Error('内容不可空（Content cannot be null）'); ruleCall({op:'setContent', content, baseUrl:baseUrl == null ? null : String(baseUrl)}); return analyzer; },
                setBaseUrl(baseUrl) { ruleCall({op:'setBaseUrl', baseUrl:baseUrl == null ? null : String(baseUrl)}); return analyzer; },
                setRedirectUrl(url) { return ruleCall({op:'setRedirectUrl', url:String(url)}); },
                getStringList(rule, content, isUrl) { return ruleCall({op:'getStringList', rule:rule == null ? null : String(rule), content:content === undefined ? null : content, hasContent:content !== undefined, isUrl:!!isUrl}); },
                getString(rule, content, isUrl) { return ruleCall({op:'getString', rule:rule == null ? null : String(rule), content:content === undefined ? null : content, hasContent:content !== undefined && typeof content !== 'boolean', unescape:typeof content === 'boolean' ? content : false, isUrl:!!isUrl}); },
                getElement(rule) { return ruleCall({op:'getElement', rule:String(rule)}); },
                getElements(rule) { return ruleCall({op:'getElements', rule:String(rule)}); }
              };
              window.java = window.java || {};
              java.get = get; java.put = put;
              java.getSource = () => window.source; java.getTag = () => \(Self.jsString(source.sourceName));
              java.ajax = (url, timeout) => evaluateJS(
                'java.ajax(' + JSON.stringify(String(url)) + (timeout == null ? '' : ',' + Number(timeout)) + ')'
              );
              java.connect = (url, headers, timeout) => evaluateJS(
                'JSON.stringify(java.connect(' + JSON.stringify(String(url)) + ',' +
                JSON.stringify(headers || {}) + (timeout == null ? '' : ',' + Number(timeout)) + '))'
              );
              java.get = function (url, headers, timeout) {
                if (arguments.length === 1) return get(url);
                return evaluateJS(
                  'java.get(' + JSON.stringify(String(url)) + ',' + JSON.stringify(headers || {}) +
                  (timeout == null ? '' : ',' + Number(timeout)) + ').body()'
                );
              };
              java.head = (url, headers, timeout) => evaluateJS(
                'JSON.stringify(java.head(' + JSON.stringify(String(url)) + ',' +
                JSON.stringify(headers || {}) + (timeout == null ? '' : ',' + Number(timeout)) + ').headers())'
              );
              java.post = (url, body, headers, timeout) => evaluateJS(
                'java.post(' + JSON.stringify(String(url)) + ',' + JSON.stringify(body == null ? '' : body) + ',' +
                JSON.stringify(headers || {}) + (timeout == null ? '' : ',' + Number(timeout)) + ').body()'
              );
              java.getCookie = (tag, key) => nativeCall('__legado_cookie__', {
                op: key == null ? 'get' : 'getKey',
                url: String(tag),
                key: key == null ? null : String(key)
              });
              window.cache = {
                put(key, value, saveTime) { nativeCall('__legado_cache__', {op:'put', key:String(key), value, saveTime:Number(saveTime) || 0}); },
                get(key, onlyDisk) { return nativeCall('__legado_cache__', {op:'get', key:String(key), onlyDisk:!!onlyDisk}); },
                putMemory(key, value) { nativeCall('__legado_cache__', {op:'putMemory', key:String(key), value}); },
                getFromMemory(key) { return nativeCall('__legado_cache__', {op:'getFromMemory', key:String(key)}); },
                deleteMemory(key) { nativeCall('__legado_cache__', {op:'deleteMemory', key:String(key)}); },
                delete(key) { nativeCall('__legado_cache__', {op:'delete', key:String(key)}); },
                putFile(key, value, saveTime) { nativeCall('__legado_cache__', {op:'putFile', key:String(key), value, saveTime:Number(saveTime) || 0}); },
                getFile(key) { return nativeCall('__legado_cache__', {op:'getFile', key:String(key)}); }
              };
              window.cookie = {
                getCookie(url) { return nativeCall('__legado_cookie__', {op:'get', url:String(url)}); },
                getKey(url, key) { return nativeCall('__legado_cookie__', {op:'getKey', url:String(url), key:String(key)}); },
                setCookie(url, value) { nativeCall('__legado_cookie__', {op:'set', url:String(url), value:String(value)}); },
                removeCookie(url) { nativeCall('__legado_cookie__', {op:'remove', url:String(url)}); },
                cookieToMap(header) {
                  const map = {};
                  String(header || '').split(';').forEach(part => {
                    const index = part.indexOf('=');
                    if (index > 0) map[part.slice(0, index).trim()] = part.slice(index + 1).trim();
                  });
                  return map;
                },
                mapToCookie(map) {
                  return Object.keys(map || {}).map(key => key + '=' + map[key]).join('; ');
                }
              };
              java.showPhoto = src => native('showPhoto', {url:String(src)});
              java.addBook = url => native('addBook', {url:String(url)});
              java.searchBook = (key, scope) => native('searchBook', {key:String(key), scope:scope == null ? null : String(scope)});
              java.open = (name, url, title, origin) => native('open', {name:String(name), url:url == null ? null : String(url), title:title == null ? null : String(title), origin:origin == null ? null : String(origin)});
              java.openUrl = (url, mimeType) => native('openExternal', {url:String(url), mimeType:mimeType == null ? null : String(mimeType)});
              java.longToast = message => native('message', {message:String(message == null ? '' : message)});
              java.toast = java.longToast;
              java.setContent = analyzer.setContent; java.setBaseUrl = analyzer.setBaseUrl; java.setRedirectUrl = analyzer.setRedirectUrl;
              java.getString = analyzer.getString; java.getStringList = analyzer.getStringList; java.getElement = analyzer.getElement; java.getElements = analyzer.getElements;
              window.source = Object.assign(\(sourceJSON), {
                getKey: () => \(Self.jsString(source.sourceUrl)),
                getTag: () => \(Self.jsString(source.sourceName)),
                get, put
              });
              document.addEventListener('contextmenu', event => {
                const image = event.target && event.target.closest ? event.target.closest('img') : null;
                if (!image || !image.src) return;
                event.preventDefault();
                native('showPhoto', {url:String(image.currentSrc || image.src)});
              }, true);
            })();
            """
        }

        func installRulesAndLoad(mode: RSSReadingMode, in webView: WKWebView) {
            let policy = RSSResourcePolicy(blacklist: source.contentBlacklist, whitelist: source.contentWhitelist)
            guard let json = policy.contentBlockerJSON() else {
                rulesInstalled = true; loadIfChanged(mode: mode, in: webView); return
            }
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "rss-\(source.sourceUrl.hashValue)", encodedContentRuleList: json) { [weak self, weak webView] list, _ in
                DispatchQueue.main.async {
                    guard let self, let webView else { return }
                    if let list { webView.configuration.userContentController.add(list) }
                    self.rulesInstalled = true
                    self.loadIfChanged(mode: mode, in: webView)
                }
            }
        }

        func loadIfChanged(mode: RSSReadingMode, in webView: WKWebView) {
            guard rulesInstalled else { return }
            let newSignature = String(describing: mode)
            guard signature != newSignature else { return }
            signature = newSignature
            switch mode {
            case .html(_, let baseURL), .startHTML(_, let baseURL):
                trustedMainFrameOrigin = Self.webOrigin(baseURL) ?? Self.webOrigin(source.sourceUrl)
            case .image(let value), .video(let value):
                trustedMainFrameOrigin = Self.webOrigin(value)
            case .web:
                trustedMainFrameOrigin = nil
            }
            switch mode {
            case .html(let content, let baseURL):
                webView.loadHTMLString(htmlProcessor.contentHTML(content, style: source.style), baseURL: baseURL.flatMap(URL.init(string:)))
            case .startHTML(let content, let baseURL):
                webView.loadHTMLString(htmlProcessor.startHTML(content, source: source), baseURL: baseURL.flatMap(URL.init(string:)))
            case .web(let value): load(value, in: webView)
            case .image(let value):
                let escaped = Self.htmlEscape(value)
                webView.loadHTMLString(htmlProcessor.contentHTML("<body><img src=\"\(escaped)\"></body>", style: source.style), baseURL: URL(string: value))
            case .video(let value):
                let escaped = Self.htmlEscape(value)
                webView.loadHTMLString(htmlProcessor.contentHTML("<body><video src=\"\(escaped)\" controls autoplay playsinline></video></body>", style: source.style), baseURL: URL(string: value))
            }
        }

        private func load(_ value: String, in webView: WKWebView) {
            guard let url = URL(string: value) else { return }
            var request = URLRequest(url: url, cachePolicy: source.cacheFirst ? .returnCacheDataElseLoad : .useProtocolCachePolicy, timeoutInterval: 180)
            if let headers = try? BookSourceHeaderResolver().resolve(source.bookSourceAdapter) {
                for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
                webView.customUserAgent = headers.first { $0.key.caseInsensitiveCompare("User-Agent") == .orderedSame }?.value
            }
            if webView.customUserAgent == nil { webView.customUserAgent = ApplicationSettingsStore.shared.settings.effectiveUserAgent }
            request = ApplicationSettingsStore.shared.settings.configure(request)
            let cookie = LegadoCookieStore.shared.cookieHeader(for: value)
            if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
            webView.load(request)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard bridgeEnabled, message.frameInfo.isMainFrame,
                  let body = message.body as? [String: Any],
                  let action = body["action"] as? String else { return }
            switch action {
            case "put":
                if let key = body["key"] as? String { BookSourceRuntimeStore.shared.put(sourceID: source.sourceUrl, key: key, value: String(describing: body["value"] ?? "")) }
            case "showPhoto":
                if let raw = body["url"] as? String { DispatchQueue.main.async { self.onAction(.showPhoto(raw)) } }
            case "searchBook":
                if let key = body["key"] as? String { DispatchQueue.main.async { self.onAction(.searchBook(key: key, scope: body["scope"] as? String)) } }
            case "addBook":
                if let raw = body["url"] as? String { DispatchQueue.main.async { self.onAction(.addBook(raw)) } }
            case "open":
                let name = body["name"] as? String ?? ""
                DispatchQueue.main.async { self.onAction(.open(name: name, url: body["url"] as? String, title: body["title"] as? String, origin: body["origin"] as? String)) }
            case "openBrowser":
                if let raw = body["url"] as? String,
                   let url = URL(string: raw),
                   ["http", "https", "legado", "yuedu"].contains(url.scheme?.lowercased() ?? "") {
                    DispatchQueue.main.async { self.onAction(.openBrowser(raw)) }
                }
            case "openExternal":
                if let raw = body["url"] as? String,
                   let url = URL(string: raw),
                   ["http", "https", "legado", "yuedu"].contains(url.scheme?.lowercased() ?? "") {
                    DispatchQueue.main.async { self.onAction(.openExternal(raw)) }
                }
            case "message":
                let message = String(describing: body["message"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !message.isEmpty {
                    DispatchQueue.main.async { self.onAction(.message(message)) }
                }
            default: break
            }
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
            guard bridgeEnabled, frame.isMainFrame else {
                completionHandler(defaultText)
                return
            }
            if prompt == "__legado_get__" {
                completionHandler(BookSourceRuntimeStore.shared.get(sourceID: source.sourceUrl, key: defaultText ?? ""))
            } else if prompt == "__legado_rule__" {
                handleRulePrompt(defaultText, completionHandler: completionHandler)
            } else if prompt == "__legado_js__" {
                handleJavaScriptPrompt(defaultText, completionHandler: completionHandler)
            } else if prompt == "__legado_cache__" {
                handleCachePrompt(defaultText, completionHandler: completionHandler)
            } else if prompt == "__legado_cookie__" {
                handleCookiePrompt(defaultText, completionHandler: completionHandler)
            } else { completionHandler(defaultText) }
        }

        private func handleJavaScriptPrompt(_ payload: String?, completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
            guard let payload, let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let script = object["script"] as? String, !script.isEmpty else {
                completionHandler("null")
                return
            }
            let context = RuleExecutionContext(
                variables: analyzeVariables,
                baseURL: analyzeRedirectURL ?? analyzeBaseURL,
                source: source.bookSourceAdapter,
                content: analyzeContent
            )
            Task {
                do {
                    let result = try await JavaScriptRuleEvaluator().evaluateAsync(
                        script: script,
                        result: analyzeContent,
                        executionContext: context
                    )
                    self.analyzeVariables = result.variables
                    completionHandler(Self.json(result.value.foundationObject))
                } catch {
                    completionHandler(Self.json(["error": error.localizedDescription]))
                }
            }
        }

        private func handleCachePrompt(_ payload: String?, completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
            guard let payload, let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let operation = object["op"] as? String,
                  let key = object["key"] as? String else {
                completionHandler("null")
                return
            }
            let value = object["value"].map { String(describing: $0) } ?? ""
            let cache = JavaScriptRuleCache.shared
            switch operation {
            case "put":
                cache.put(key, value: value, saveTime: max(0, object["saveTime"] as? Int ?? 0))
                completionHandler("true")
            case "get":
                let result = cache.get(key, onlyDisk: object["onlyDisk"] as? Bool == true)
                completionHandler(Self.json(result as Any? ?? NSNull()))
            case "putMemory":
                cache.putMemory(key, value: value)
                completionHandler("true")
            case "getFromMemory":
                completionHandler(Self.json(cache.getFromMemory(key) as Any? ?? NSNull()))
            case "deleteMemory":
                cache.deleteMemory(key)
                completionHandler("true")
            case "delete":
                cache.delete(key)
                completionHandler("true")
            case "putFile":
                do {
                    try cache.putFile(key, value: value, saveTime: max(0, object["saveTime"] as? Int ?? 0))
                    completionHandler("true")
                } catch {
                    completionHandler(Self.json(["error": error.localizedDescription]))
                }
            case "getFile":
                completionHandler(Self.json(cache.getFile(key) as Any? ?? NSNull()))
            default:
                completionHandler("null")
            }
        }

        private func handleCookiePrompt(_ payload: String?, completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
            guard let payload, let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let operation = object["op"] as? String,
                  let url = object["url"] as? String else {
                completionHandler("null")
                return
            }
            let cookies = LegadoCookieStore.shared
            switch operation {
            case "get":
                completionHandler(Self.json(cookies.cookieHeader(for: url)))
            case "getKey":
                completionHandler(Self.json(cookies.cookie(for: url, key: object["key"] as? String ?? "")))
            case "set":
                cookies.setCookie(object["value"] as? String ?? "", for: url)
                completionHandler("true")
            case "remove":
                cookies.removeCookies(for: url)
                completionHandler("true")
            default:
                completionHandler("null")
            }
        }

        private func handleRulePrompt(_ payload: String?, completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
            guard let payload, let data = payload.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let operation = object["op"] as? String else { completionHandler("null"); return }
            switch operation {
            case "setContent":
                analyzeContent = JSONValue.bridge(object["content"])
                if let base = object["baseUrl"] as? String, !base.isEmpty { analyzeBaseURL = base }
                completionHandler("true")
            case "setBaseUrl":
                if let base = object["baseUrl"] as? String, !base.isEmpty { analyzeBaseURL = base }
                completionHandler("true")
            case "setRedirectUrl":
                let value = object["url"] as? String ?? ""
                if !value.lowercased().hasPrefix("data:"), URL(string: value) != nil { analyzeRedirectURL = value }
                completionHandler(Self.jsonString(analyzeRedirectURL))
            default:
                let rule = object["rule"] as? String ?? ""
                guard !rule.isEmpty else { completionHandler(operation == "getStringList" || operation == "getElements" ? "null" : "\"\""); return }
                let input = (object["hasContent"] as? Bool) == true ? JSONValue.bridge(object["content"]) : analyzeContent
                let baseURL = analyzeRedirectURL ?? analyzeBaseURL
                let context = RuleExecutionContext(variables: analyzeVariables, baseURL: baseURL, source: source.bookSourceAdapter)
                Task {
                    let evaluation: RuleEvaluation
                    switch input {
                    case .string(let text):
                        evaluation = await RuleEngine().evaluate(rule, inText: text, baseURL: baseURL, listMode: operation == "getStringList" || operation == "getElements", context: context)
                    default:
                        evaluation = await RuleEngine().evaluate(rule, in: input, context: context)
                    }
                    self.analyzeVariables = evaluation.variables
                    let isURL = object["isUrl"] as? Bool == true
                    let values = evaluation.values.map { value -> JSONValue in
                        guard isURL else { return value }
                        let raw = value.stringValue
                        return .string(URL(string: raw, relativeTo: URL(string: baseURL))?.absoluteURL.absoluteString ?? raw)
                    }
                    let response: Any
                    switch operation {
                    case "getStringList": response = values.map(\.stringValue)
                    case "getElement": response = values.first?.foundationObject ?? NSNull()
                    case "getElements": response = values.map(\.foundationObject)
                    default:
                        var value = values.map(\.stringValue).joined(separator: "\n")
                        if object["unescape"] as? Bool == true { value = Self.unescapeHTML(value) }
                        response = value
                    }
                    completionHandler(Self.json(response))
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            let scheme = url.scheme?.lowercased() ?? ""
            if !["http", "https", "file", "data", "about"].contains(scheme) {
                UIApplication.shared.open(url); decisionHandler(.cancel); return
            }
            if bridgeEnabled, navigationAction.targetFrame?.isMainFrame != false {
                if scheme == "about", url.absoluteString == "about:blank" {
                    decisionHandler(.allow)
                    return
                }
                if ["http", "https"].contains(scheme),
                   Self.webOrigin(url) != trustedMainFrameOrigin {
                    decisionHandler(.cancel)
                    DispatchQueue.main.async { self.onAction(.openBrowser(url.absoluteString)) }
                    return
                }
                if !["http", "https"].contains(scheme) {
                    // data:/file: documents can execute attacker-controlled script in the
                    // main frame, so never let them inherit the privileged source bridge.
                    decisionHandler(.cancel)
                    return
                }
            }
            if navigationAction.navigationType == .linkActivated, shouldOverride(url.absoluteString) {
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }

        private static func webOrigin(_ rawValue: String?) -> String? {
            guard let rawValue, let url = URL(string: rawValue) else { return nil }
            return webOrigin(url)
        }

        private static func webOrigin(_ url: URL) -> String? {
            guard let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  let host = url.host?.lowercased() else { return nil }
            let port = url.port.map { ":\\($0)" } ?? ""
            return "\\(scheme)://\\(host)\\(port)"
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
            guard let response = navigationResponse.response as? HTTPURLResponse, let url = response.url else { decisionHandler(.allow); return }
            let disposition = response.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
            if disposition.contains("attachment") || !navigationResponse.canShowMIMEType {
                let name = response.suggestedFilename ?? url.lastPathComponent.nilIfBlank ?? "download"
                DispatchQueue.main.async { self.onAction(.download(url: url.absoluteString, fileName: name)) }
                decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] value, _ in
                guard let text = value as? String else { return }
                DispatchQueue.main.async { self?.onTextChange(text) }
            }
        }

        private func shouldOverride(_ url: String) -> Bool {
            guard let script = source.shouldOverrideUrlLoading?.trimmedNonEmpty else { return false }
            let quoted = Self.jsString(url)
            let expression = "(function(url){return (\(script));})(\(quoted))"
            let body = "(function(url){\(script)})(\(quoted))"
            let evaluator = JavaScriptRuleEvaluator()
            let context = RuleExecutionContext(variables: ["url": url], baseURL: url, source: source.bookSourceAdapter)
            let result = (try? evaluator.evaluate(script: expression, result: .string(url), executionContext: context))
                ?? (try? evaluator.evaluate(script: body, result: .string(url), executionContext: context))
            let value = result?.value.stringValue.lowercased() ?? ""
            return ["true", "1", "yes"].contains(value)
        }

        private static func jsString(_ value: String) -> String {
            let data = try? JSONEncoder().encode(value)
            return data.map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
        }
        private static func htmlEscape(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;")
        }
        private static func json(_ value: Any) -> String {
            guard JSONSerialization.isValidJSONObject([value]), let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) else { return "null" }
            return String(decoding: data, as: UTF8.self)
        }
        private static func jsonString(_ value: String?) -> String { value.map { json($0) } ?? "null" }
        private static func unescapeHTML(_ value: String) -> String {
            guard let data = "<span>\(value)</span>".data(using: .utf8), let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) else { return value }
            return attributed.string
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    var nilIfBlank: String? { trimmedNonEmpty }
}
