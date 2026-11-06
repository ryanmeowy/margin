import AppKit

/// 导出近 7 天 CSV：后台任务 + 直接落盘 + 系统通知
final class ExportController {
    private let storeProvider: () -> UsageStore?
    private let notify: (String, String) -> Void
    private let reveal: (URL) -> Void
    private var task: Task<Void, Never>?

    init(storeProvider: @escaping () -> UsageStore?,
         notify: @escaping (String, String) -> Void = { Notifier.notify(title: $0, body: $1) },
         reveal: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }) {
        self.storeProvider = storeProvider
        self.notify = notify
        self.reveal = reveal
    }

    var isRunning: Bool { task != nil }

    func start() {
        guard task == nil, let store = storeProvider() else { return }
        store.setExporting(true)
        task = Task { [weak self] in
            guard let self else { return }
            let body = await store.exportCSV(days: 7) { count in store.reportExport(count) }
            store.setExporting(false)
            defer { self.task = nil }

            guard !body.isEmpty else {
                self.notify("导出失败", "没有拿到明细数据")
                return
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM"
            let base = "margin-usage-\(formatter.string(from: Date()))"
            let url = Self.uniqueDownloadURL(base: base)

            var data = Data([0xEF, 0xBB, 0xBF])        // UTF-8 BOM，Excel 打开不乱码
            data.append(Data(body.utf8))
            do {
                try data.write(to: url)
                let rows = body.split(separator: "\n").count - 9
                self.notify("用量已导出", "\(rows) 条明细 · \(url.lastPathComponent)")
                self.reveal(url)
            } catch {
                self.notify("导出失败", error.localizedDescription)
            }
        }
    }

    /// ~/Downloads 里挑一个不重名的文件名
    static func uniqueDownloadURL(base: String) -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        var url = downloads.appendingPathComponent("\(base).csv")
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = downloads.appendingPathComponent("\(base) (\(index)).csv")
            index += 1
        }
        return url
    }
}
