import SwiftUI

struct ContentView: View {
    @ObservedObject var model: TVRemoteAppModel

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("TVs na rede").font(.headline)
                    Spacer()
                    Button { model.startDiscovery() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Atualizar busca")
                }

                if model.discovery.isSearching && model.discovery.devices.isEmpty {
                    ProgressView("Procurando…")
                        .controlSize(.small)
                        .padding(.vertical, 8)
                } else if model.discovery.devices.isEmpty {
                    Text("Nenhuma TV encontrada.").foregroundStyle(.secondary)
                } else {
                    List(model.discovery.devices, selection: Binding(get: { model.selectedTV?.id }, set: { id in
                        if let id, let tv = model.discovery.devices.first(where: { $0.id == id }) { model.select(tv) }
                    })) { tv in
                        VStack(alignment: .leading) {
                            Text(tv.name)
                            Text(tv.type).font(.caption).foregroundStyle(.secondary)
                        }.tag(tv.id)
                    }
                    .listStyle(.sidebar)
                }
                Spacer()
            }
            .padding()
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            VStack(spacing: 22) {
                header
                RemotePad(model: model)
                Text(model.statusMessage).font(.caption).foregroundStyle(.secondary)
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(36)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $model.showPairingCode) {
                PairingCodeView(model: model)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(model.selectedTV?.name ?? "Nenhuma TV selecionada").font(.title2.bold())
                Text(model.selectedTV == nil ? "Escolha uma TV para começar" : "Pronta para controle")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Parear") { model.pair() }
                .disabled(model.selectedTV == nil || model.isPairing)
        }
    }
}

private struct PairingCodeView: View {
    @ObservedObject var model: TVRemoteAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Parear Android TV").font(.title2.bold())
            Text("Digite o PIN de 6 caracteres exibido na tela da TV.")
                .foregroundStyle(.secondary)
            TextField("PIN", text: $model.pairingCode)
                .textFieldStyle(.roundedBorder)
                .textCase(.uppercase)
                .onSubmit { model.submitPairingCode() }
            HStack {
                Spacer()
                Button("Cancelar") { model.cancelPairing() }
                Button("Confirmar") { model.submitPairingCode() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.pairingCode.count != 6)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

private struct RemotePad: View {
    @ObservedObject var model: TVRemoteAppModel
    private let size: CGFloat = 58

    var body: some View {
        VStack(spacing: 14) {
            Button { model.send { try await $0.up() } } label: { Image(systemName: "chevron.up") }.remoteButton(size: size)
            HStack(spacing: 14) {
                Button { model.send { try await $0.left() } } label: { Image(systemName: "chevron.left") }.remoteButton(size: size)
                Button { model.send { try await $0.select() } } label: { Text("OK").fontWeight(.bold) }.remoteButton(size: size)
                Button { model.send { try await $0.right() } } label: { Image(systemName: "chevron.right") }.remoteButton(size: size)
            }
            Button { model.send { try await $0.down() } } label: { Image(systemName: "chevron.down") }.remoteButton(size: size)

            HStack(spacing: 14) {
                Button("Volume −") { model.send { try await $0.volumeDown() } }
                Button("Volume +") { model.send { try await $0.volumeUp() } }
            }
            .buttonStyle(.bordered)
            Button { model.send { try await $0.power() } } label: { Label("Power", systemImage: "power") }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
    }
}

private extension View {
    func remoteButton(size: CGFloat) -> some View {
        self.frame(width: size, height: size).buttonStyle(.bordered).font(.title3)
    }
}
