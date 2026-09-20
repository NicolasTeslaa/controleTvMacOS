import Foundation

@MainActor
final class TVRemoteAppModel: ObservableObject {
    @Published var selectedTV: DiscoveredTV?
    @Published var isPairing = false
    @Published var showPairingCode = false
    @Published var pairingCode = ""
    @Published var statusMessage = "Pronto para procurar uma TV."
    @Published var errorMessage: String?
    let discovery = DiscoveryService()

    private let keychain = KeychainStore()
    private var remote: TVRemote?
    private var androidClient: AndroidTVRemoteClient?

    init() {
        startDiscovery()
    }

    func startDiscovery() {
        errorMessage = nil
        statusMessage = "Procurando TVs na rede local…"
        discovery.start()
    }

    func select(_ tv: DiscoveredTV) {
        selectedTV = tv
        if !tv.host.isEmpty, let client = try? AndroidTVRemoteClient(host: tv.host) {
            androidClient = client
            remote = client
        }
        statusMessage = "TV selecionada: \(tv.name)"
    }

    func pair() {
        guard let tv = selectedTV else { errorMessage = TVRemoteError.noTVSelected.localizedDescription; return }
        guard !tv.host.isEmpty else {
            errorMessage = "Não foi possível resolver o endereço da TV. Atualize a busca e tente novamente."
            return
        }
        isPairing = true
        errorMessage = nil
        statusMessage = "Solicitando pareamento à TV…"
        do {
            let client = try AndroidTVRemoteClient(host: tv.host)
            androidClient = client
            try client.beginPairing(onPINRequested: { [weak self] in
                Task { @MainActor in
                    self?.statusMessage = "Digite o PIN exibido na TV."
                    self?.showPairingCode = true
                }
            }, completion: { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    self.isPairing = false
                    switch result {
                    case .success:
                        self.remote = client
                        self.showPairingCode = false
                        self.statusMessage = "TV pareada com sucesso."
                    case .failure(let error):
                        self.errorMessage = error.localizedDescription
                        self.statusMessage = "Falha no pareamento."
                    }
                }
            })
        } catch {
            isPairing = false
            errorMessage = error.localizedDescription
        }
    }

    func submitPairingCode() {
        guard pairingCode.count == 6 else {
            errorMessage = "O PIN deve conter 6 caracteres."
            return
        }
        androidClient?.finishPairing(pin: pairingCode)
        statusMessage = "Validando PIN…"
    }

    func cancelPairing() {
        showPairingCode = false
        isPairing = false
        pairingCode = ""
    }

    func send(_ action: @escaping (TVRemote) async throws -> Void) {
        guard selectedTV != nil else { errorMessage = TVRemoteError.noTVSelected.localizedDescription; return }
        guard let remote else {
            errorMessage = "Pareie a TV antes de enviar comandos."
            return
        }
        Task {
            do {
                try await action(remote)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
