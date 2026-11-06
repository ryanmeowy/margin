import Foundation

/// 全局请求闸门：所有打到 OpenDesign 的请求都从这里过，避免并行任务叠加把接口打限流。
actor TaskGate {
    private let limit: Int
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
        self.available = limit
    }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            available = min(limit, available + 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// 进程内共享的 API 闸门（7 路按天并行 + 导出 + 后台刷新共用）
let apiGate = TaskGate(limit: 8)
