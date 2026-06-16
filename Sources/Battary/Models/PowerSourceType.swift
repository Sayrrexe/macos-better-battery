import Foundation

enum PowerSourceType: String, Codable, Equatable {
    case battery
    case powerAdapter
    case unknown

    var isBattery: Bool {
        self == .battery
    }
}
