import AppKit

enum CSVExport {
    /// 返回是否真的写盘。
    @discardableResult
    static func save(_ body: String, fileName: String) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.title = "导出用量 CSV"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        var data = Data()
        data.append(contentsOf: [0xEF, 0xBB, 0xBF])   // UTF-8 BOM，Excel 打开不乱码
        data.append(Data(body.utf8))
        do {
            try data.write(to: url)
            return true
        } catch {
            NSLog("margin: csv write failed \(error)")
            return false
        }
    }
}
