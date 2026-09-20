import Foundation
import CryptoKit

struct DiscoveredTV: Identifiable, Hashable {
    let id: UUID
    let name: String
    let type: String
    let host: String
    let port: Int
    let serviceType: String

    init(id: UUID? = nil, name: String, type: String, host: String = "", port: Int = 0, serviceType: String = "") {
        self.id = id ?? Self.stableID(for: "\(serviceType)|\(name)")
        self.name = name
        self.type = type
        self.host = host
        self.port = port
        self.serviceType = serviceType
    }

    private static func stableID(for value: String) -> UUID {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        let uuidText = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: uuidText) ?? UUID()
    }
}

enum TVRemoteError: LocalizedError {
    case noTVSelected
    case unsupportedProtocol
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .noTVSelected: return "Selecione uma TV primeiro."
        case .unsupportedProtocol: return "O protocolo desta TV ainda não foi configurado."
        case .transport(let message): return message
        }
    }
}

protocol TVRemote: AnyObject {
    func power() async throws
    func volumeUp() async throws
    func volumeDown() async throws
    func up() async throws
    func down() async throws
    func left() async throws
    func right() async throws
    func select() async throws
}
