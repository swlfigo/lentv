import Foundation

public enum LenAPIError: Error, Sendable, Equatable {
    case cancelled
    case transport(String)
    case http(status: Int)
    /// 接口返回 `success: false`
    case server(message: String?)
    case decoding(String)
    /// 所有线路都没有可播放的地址
    case noPlayableSource
}

extension LenAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cancelled: "请求已取消"
        case .transport(let message): "网络连接失败：\(message)"
        case .http(let status): "服务器错误（\(status)）"
        case .server(let message): message ?? "服务器返回了错误"
        case .decoding: "数据格式无法识别"
        case .noPlayableSource: "没有可播放的线路"
        }
    }
}
