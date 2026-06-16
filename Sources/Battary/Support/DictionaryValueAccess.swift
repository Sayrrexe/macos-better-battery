import Foundation

extension Dictionary where Key == String, Value == Any {
    func int(_ key: String) -> Int? {
        if let value = self[key] as? Int { return value }
        if let value = self[key] as? UInt64 {
            return Int(bitPattern: UInt(value))
        }
        if let value = self[key] as? UInt {
            return Int(bitPattern: value)
        }
        if let value = self[key] as? Int64 { return Int(value) }
        if let value = self[key] as? Double { return Int(value) }
        if let value = self[key] as? NSNumber { return value.intValue }
        return nil
    }

    func int64(_ key: String) -> Int64? {
        if let value = self[key] as? Int64 { return value }
        if let value = self[key] as? UInt64 { return Int64(bitPattern: value) }
        if let value = self[key] as? Int { return Int64(value) }
        if let value = self[key] as? UInt { return Int64(bitPattern: UInt64(value)) }
        if let value = self[key] as? Double { return Int64(value) }
        if let value = self[key] as? NSNumber { return value.int64Value }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if let value = self[key] as? Bool { return value }
        if let value = self[key] as? NSNumber { return value.boolValue }
        return nil
    }

    func string(_ key: String) -> String? {
        if let value = self[key] as? String { return value }
        if let value = self[key] as? NSString { return value as String }
        return nil
    }

    func dictionary(_ key: String) -> [String: Any]? {
        if let value = self[key] as? [String: Any] { return value }
        if let value = self[key] as? NSDictionary { return value as? [String: Any] }
        return nil
    }
}
