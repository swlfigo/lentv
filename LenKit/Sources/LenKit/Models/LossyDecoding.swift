import Foundation

/// 资源站采集的数据字段类型不稳定（同一字段可能是数字、字符串或 null），解码时尽量宽松。
extension KeyedDecodingContainer {
    func lossyString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            // 部分标题里混有零宽空格
            let trimmed = value
                .replacingOccurrences(of: "\u{200B}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed == "None" ? nil : trimmed
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return nil
    }

    func lossyInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value ? 1 : 0 }
        return nil
    }

    func lossyBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        return lossyInt(key).map { $0 != 0 }
    }

    func lossyURL(_ key: Key) -> URL? {
        guard let string = lossyString(key) else { return nil }
        return URL(string: string)
    }

    /// `"2026"`、`"2026-07-30"`、`2026` 都解析成 2026。
    func lossyYear(_ keys: Key...) -> Int? {
        for key in keys {
            if let value = lossyInt(key), value > 1800 { return value }
            if let string = lossyString(key), string.count >= 4, let year = Int(string.prefix(4)), year > 1800 {
                return year
            }
        }
        return nil
    }
}

/// 解码失败时得到 nil，而不是抛出错误：一条脏数据不应该让整个列表失败。
struct Lossy<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: any Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

extension KeyedDecodingContainer {
    func lossyArray<Element: Decodable>(_ type: Element.Type, forKey key: Key) -> [Element] {
        ((try? decodeIfPresent([Lossy<Element>].self, forKey: key)) ?? nil)?.compactMap(\.value) ?? []
    }
}
