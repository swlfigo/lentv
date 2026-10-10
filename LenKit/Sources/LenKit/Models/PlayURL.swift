import Foundation

/// `GET /movies/{id}/play-url` 和 `GET /tv-series/{id}/episodes/{n}/play-url` 的 data 部分。
struct PlayURLPayload: Decodable {
    let url: URL?

    private enum CodingKeys: String, CodingKey { case url }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = c.lossyURL(.url)
    }
}

/// 详情、列表和播放地址接口外层的 `{ "success": true, "data": ... }`。
/// 分类、地区、年份接口只有 `data`，没有 `success`。
struct Envelope<Payload: Decodable>: Decodable {
    let success: Bool
    let data: Payload?
    let message: String?

    private enum CodingKeys: String, CodingKey { case success, data, message, error }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = c.lossyBool(.success) ?? c.contains(.data)
        data = try c.decodeIfPresent(Payload.self, forKey: .data)
        message = c.lossyString(.message) ?? c.lossyString(.error)
    }
}
