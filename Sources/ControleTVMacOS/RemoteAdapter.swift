import Foundation

/// Adaptador temporário enquanto o transporte Android TV Remote v2 é integrado.
///
/// Para a AIWA Android TV, o protocolo-alvo é:
/// - mDNS: `_androidtvremote2._tcp`
/// - pareamento: TLS/protobuf na porta 6467, com PIN exibido na TV
/// - comandos: TLS/protobuf persistente na porta 6466
///
/// A implementação final deve manter a identidade RSA do Mac no Keychain;
/// o PIN não deve ser tratado como uma credencial permanente.
final class UnsupportedTVRemote: TVRemote {
    func power() async throws { throw TVRemoteError.unsupportedProtocol }
    func volumeUp() async throws { throw TVRemoteError.unsupportedProtocol }
    func volumeDown() async throws { throw TVRemoteError.unsupportedProtocol }
    func up() async throws { throw TVRemoteError.unsupportedProtocol }
    func down() async throws { throw TVRemoteError.unsupportedProtocol }
    func left() async throws { throw TVRemoteError.unsupportedProtocol }
    func right() async throws { throw TVRemoteError.unsupportedProtocol }
    func select() async throws { throw TVRemoteError.unsupportedProtocol }
}
