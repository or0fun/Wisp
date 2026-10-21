import AppKit

enum LocalResultKind: Equatable, Sendable { case application, file, folder }

struct LocalSearchResult: Identifiable, Equatable, Sendable {
    let url: URL
    let title: String
    let kind: LocalResultKind
    var aliases: [String] = []
    var id: String { "local:\(url.standardizedFileURL.path)" }
    var subtitle: String { (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath }
    var isApplication: Bool { kind == .application }
    func score(for term: String) -> Int? {
        let needle = Self.normalized(term)
        guard !needle.isEmpty else { return nil }
        return ([title, url.lastPathComponent] + aliases).compactMap { value -> Int? in
            let value = Self.normalized(value)
            if value == needle { return 0 }
            if value.hasPrefix(needle) { return 1 }
            return value.contains(needle) ? 2 : nil
        }.min()
    }
    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
    static func ranked(_ items: [Self], for term: String, limit: Int) -> [Self] {
        var seen = Set<String>()
        return items.compactMap { item -> (Self, Int)? in
            guard seen.insert(item.id).inserted, let score = item.score(for: term) else { return nil }
            return (item, score)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            let order = $0.0.title.localizedStandardCompare($1.0.title)
            return order == .orderedSame ? $0.0.id < $1.0.id : order == .orderedAscending
        }.prefix(limit).map(\.0)
    }
}

struct LocalSearchSnapshot {
    var applications: [LocalSearchResult] = []
    var files: [LocalSearchResult] = []
    var searchingFiles = false
    var loadingApplications = false
    var fileMessage = "输入文件名，搜索本机文件与文件夹。"
    var moreFiles = false
}

/// Queries the system filename index; application discovery is cached off the UI thread.
@MainActor final class LocalSearchService: NSObject {
    var onUpdate: ((LocalSearchSnapshot) -> Void)?
    private(set) var snapshot = LocalSearchSnapshot()
    private var catalog: [LocalSearchResult] = []
    private var catalogTask: Task<Void, Never>?
    private var lastCatalogRefresh = Date.distantPast
    private var debounce: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var metadata: NSMetadataQuery?
    private var term = ""
    private let applicationRoots: [URL]
    private let fileScopes: [Any]
    static let fileLimit = 40

    init(applicationRoots: [URL] = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")], fileScopes: [Any] = [NSMetadataQueryLocalComputerScope]) {
        self.applicationRoots = applicationRoots; self.fileScopes = fileScopes
        super.init()
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryGatheringProgress, .NSMetadataQueryDidUpdate] {
            NotificationCenter.default.addObserver(self, selector: #selector(receiveMetadata(_:)), name: name, object: nil)
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    func search(_ query: String) {
        stopMetadata()
        term = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
        refreshApplicationsIfNeeded()
        snapshot.applications = LocalSearchResult.ranked(catalog, for: term, limit: 12)
        snapshot.files = []; snapshot.moreFiles = false
        snapshot.searchingFiles = !term.isEmpty
        snapshot.fileMessage = term.isEmpty ? "输入文件名，搜索本机文件与文件夹。" : "正在搜索本机文件…"
        publish()
        guard !term.isEmpty else { return }
        let requested = term
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)); try Task.checkCancellation() }
            catch { return }
            guard let self, self.term == requested else { return }
            self.startMetadata(requested)
        }
    }
    func cancel() {
        stopMetadata()
        term = ""; snapshot.applications = []; snapshot.files = []
        snapshot.searchingFiles = false; snapshot.moreFiles = false
        snapshot.fileMessage = "输入文件名，搜索本机文件与文件夹。"
        publish()
    }
    private func publish() { onUpdate?(snapshot) }
    private func stopMetadata() {
        debounce?.cancel(); debounce = nil
        timeout?.cancel(); timeout = nil
        metadata?.stop(); metadata = nil
    }
    private func refreshApplicationsIfNeeded() {
        guard catalogTask == nil, Date().timeIntervalSince(lastCatalogRefresh) > 60 else { return }
        let roots = applicationRoots
        snapshot.loadingApplications = true
        catalogTask = Task { [weak self] in
            let results = await Task.detached(priority: .utility) { Self.discoverApplications(in: roots) }.value
            guard let self else { return }
            self.catalog = results; self.lastCatalogRefresh = Date(); self.catalogTask = nil
            self.snapshot.loadingApplications = false
            self.snapshot.applications = LocalSearchResult.ranked(results, for: self.term, limit: 12)
            self.publish()
        }
    }
    nonisolated static func discoverApplications(in roots: [URL]) -> [LocalSearchResult] {
        let manager = FileManager.default
        var seen = Set<String>(), results: [LocalSearchResult] = []
        for root in roots {
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.localizedNameKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                if enumerator.level > 5 { enumerator.skipDescendants(); continue }
                guard url.pathExtension.lowercased() == "app", seen.insert(url.standardizedFileURL.path).inserted else { continue }
                enumerator.skipDescendants()
                let bundle = Bundle(url: url)
                let display = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                let localized = (try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName
                let name = display ?? localized ?? url.lastPathComponent
                let title = name.lowercased().hasSuffix(".app") ? (name as NSString).deletingPathExtension : name
                let aliases = [url.deletingPathExtension().lastPathComponent, bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String, bundle?.bundleIdentifier].compactMap { $0 }
                results.append(LocalSearchResult(url: url, title: title, kind: .application, aliases: aliases))
            }
        }
        return results
    }
    private func startMetadata(_ requested: String) {
        let query = NSMetadataQuery()
        // Parameter substitution treats quotes, wildcards and predicate syntax as filename text.
        query.predicate = NSPredicate(format: "%K CONTAINS[cd] %@ AND NOT (%K == %@)", NSMetadataItemFSNameKey, requested, NSMetadataItemContentTypeKey, "com.apple.application-bundle")
        query.searchScopes = fileScopes
        query.operationQueue = .main
        query.notificationBatchingInterval = 0.15
        metadata = query
        guard query.start() else {
            metadata = nil; snapshot.searchingFiles = false
            snapshot.fileMessage = "系统文件索引暂不可用，请检查 Spotlight 索引与文件访问权限。"
            publish(); return
        }
        timeout = Task { [weak self, weak query] in
            do { try await Task.sleep(for: .seconds(8)); try Task.checkCancellation() }
            catch { return }
            guard let self, let query, self.metadata === query else { return }
            self.collect(query)
            query.stop(); self.metadata = nil; self.snapshot.searchingFiles = false
            if self.snapshot.files.isEmpty { self.snapshot.fileMessage = "未收到索引结果；请检查 Spotlight 索引与文件访问权限。" }
            self.publish()
        }
    }
    @objc private func receiveMetadata(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery, query === metadata else { return }
        collect(query)
        if notification.name == .NSMetadataQueryDidFinishGathering {
            snapshot.searchingFiles = false; timeout?.cancel(); timeout = nil
            query.stop(); metadata = nil
        }
        publish()
    }
    private func collect(_ query: NSMetadataQuery) {
        query.disableUpdates()
        defer { query.enableUpdates() }
        var results: [LocalSearchResult] = []
        for index in 0..<min(query.resultCount, 2000) {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  Self.isVisibleFile(path: path) else { continue }
            let url = URL(fileURLWithPath: path)
            let type = item.value(forAttribute: NSMetadataItemContentTypeKey) as? String
            results.append(LocalSearchResult(url: url, title: url.lastPathComponent, kind: type == "public.folder" ? .folder : .file))
        }
        snapshot.files = LocalSearchResult.ranked(results, for: term, limit: Self.fileLimit)
        snapshot.moreFiles = snapshot.files.count == Self.fileLimit && query.resultCount > Self.fileLimit
        snapshot.fileMessage = snapshot.files.isEmpty ? "未找到匹配文件。未被 Spotlight 索引或无权访问的文件不会显示。" : "按文件名搜索；回车打开，右键可在 Finder 中显示。"
    }
    nonisolated static func isVisibleFile(path: String) -> Bool {
        let parts = URL(fileURLWithPath: path).pathComponents
        guard !parts.contains(where: { $0.hasPrefix(".") || ["node_modules", "Pods", "Carthage", "vendor"].contains($0) || ["app", "framework", "bundle"].contains(($0 as NSString).pathExtension.lowercased()) }) else { return false }
        return !["/System/", "/Library/", "/private/", "/usr/", "/bin/", "/sbin/"].contains(where: path.hasPrefix)
            && !path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path + "/")
    }
}
