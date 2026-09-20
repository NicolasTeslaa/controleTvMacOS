import Foundation
import Network
import Security
import AndroidTVRemoteControl

final class AndroidTVRemoteClient: TVRemote {
    private let host: String
    private let identity: AndroidTVIdentity
    private var remote: RemoteManager?
    private var pairing: PairingManager?
    private var identityDirectory: URL?
    private var isConnected = false
    private var connectionWaiter: CheckedContinuation<Void, Error>?

    init(host: String) throws {
        self.host = host
        self.identity = try AndroidTVIdentity.loadOrCreate()
    }

    deinit {
        remote?.disconnect()
        pairing?.disconnect()
        if let identityDirectory { try? FileManager.default.removeItem(at: identityDirectory) }
    }

    func beginPairing(onPINRequested: @escaping @Sendable () -> Void, completion: @escaping @Sendable (Swift.Result<Void, Error>) -> Void) throws {
        let resources = try makeTLSResources()
        let crypto = CryptoManager()
        crypto.clientPublicCertificate = { CertManager().getSecKey(resources.der) }
        resources.tls.secTrustClosure = { trust in
            crypto.serverPublicCertificate = {
                guard let key = SecTrustCopyKey(trust) else { return .Error(.secTrustCopyKeyError) }
                return .Result(key)
            }
        }

        let manager = PairingManager(resources.tls, crypto)
        pairing = manager
        manager.stateChanged = { [weak self] state in
            switch state {
            case .waitingCode:
                onPINRequested()
            case .successPaired:
                self?.pairing = nil
                completion(.success(()))
            case .error(let error):
                self?.pairing = nil
                completion(.failure(error))
            default:
                break
            }
        }
        manager.connect(host, "Controle TV macOS", "AIWA Android TV", timeout: 15)
    }

    func finishPairing(pin: String) {
        pairing?.sendSecret(pin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
    }

    func power() async throws { try await send(.KEYCODE_POWER) }
    func volumeUp() async throws { try await send(.KEYCODE_VOLUME_UP) }
    func volumeDown() async throws { try await send(.KEYCODE_VOLUME_DOWN) }
    func up() async throws { try await send(.KEYCODE_DPAD_UP) }
    func down() async throws { try await send(.KEYCODE_DPAD_DOWN) }
    func left() async throws { try await send(.KEYCODE_DPAD_LEFT) }
    func right() async throws { try await send(.KEYCODE_DPAD_RIGHT) }
    func select() async throws { try await send(.KEYCODE_DPAD_CENTER) }

    private func send(_ key: Key) async throws {
        try await connect()
        guard let remote else { throw TVRemoteError.transport("A conexão com a TV não está disponível.") }
        try await remote.sendAsync(KeyPress(key))
    }

    func connect() async throws {
        if isConnected { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connectionWaiter = continuation
            do {
                let resources = try makeTLSResources()
                let manager = RemoteManager(
                    resources.tls,
                    CommandNetwork.DeviceInfo("AIWA Android TV", "Mac", "1.0", "Controle TV macOS", "1")
                )
                remote = manager
                manager.stateChanged = { [weak self] state in
                    switch state {
                    case .paired:
                        self?.isConnected = true
                        self?.connectionWaiter?.resume()
                        self?.connectionWaiter = nil
                    case .error(let error):
                        self?.isConnected = false
                        self?.remote = nil
                        self?.connectionWaiter?.resume(throwing: error)
                        self?.connectionWaiter = nil
                    default:
                        break
                    }
                }
                manager.connect(host, timeout: 10)
            } catch {
                continuation.resume(throwing: error)
                connectionWaiter = nil
            }
        }
    }

    private func connectedRemote() throws -> RemoteManager {
        if let remote { return remote }
        let resources = try makeTLSResources()
        let manager = RemoteManager(
            resources.tls,
            CommandNetwork.DeviceInfo("AIWA Android TV", "Mac", "1.0", "Controle TV macOS", "1")
        )
        remote = manager
        manager.connect(host, timeout: 10)
        return manager
    }

    private func makeTLSResources() throws -> (tls: TLSManager, der: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("controle-tv-identity-\(host.replacingOccurrences(of: ".", with: "_"))")
        identityDirectory = directory
        let files = try identity.materialize(in: directory)
        let tls = TLSManager { CertManager().cert(files.p12, self.identity.password) }
        return (tls, files.der)
    }
}
