import Foundation
import Network

@MainActor
final class DiscoveryService: ObservableObject {
    @Published private(set) var devices: [DiscoveredTV] = []
    @Published private(set) var isSearching = false

    private var browsers: [NWBrowser] = []
    private var resolutionConnections: [NWConnection] = []
    private var dnsBrowseProcess: Process?
    private var dnsBrowseBuffer = ""
    private var dnsLookups: [Process] = []
    private var legacyBrowser: NetServiceBrowser?
    private var legacyDelegate: BonjourDelegate?
    // AIWA comercializa modelos Android TV e Google TV. Os dois serviços
    // Android abaixo cobrem gerações diferentes do Android TV Remote.
    private let serviceTypes = [
        "_googlecast._tcp",
        "_androidtvremote2._tcp",
        "_androidtvremote._tcp",
        "_airplay._tcp",
        "_roku._tcp"
    ]

    func start() {
        stop()
        devices = []
        isSearching = true

        for serviceType in serviceTypes {
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: "local."), using: .tcp)
            browser.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    Task { @MainActor in self?.remove(browser: browser) }
                }
            }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self else { return }
                Task { @MainActor in self.update(results: results, serviceType: serviceType) }
            }
            browsers.append(browser)
            browser.start(queue: .main)
        }

        // Alguns televisores anunciam apenas Google Cast. O dns-sd nativo
        // do macOS é usado como fallback para esses anúncios.
        startDNSFallback()
    }

    func stop() {
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
        resolutionConnections.forEach { $0.cancel() }
        resolutionConnections.removeAll()
        dnsBrowseProcess?.terminate()
        dnsBrowseProcess = nil
        dnsLookups.forEach { $0.terminate() }
        dnsLookups.removeAll()
        legacyBrowser?.stop()
        legacyBrowser = nil
        legacyDelegate = nil
        isSearching = false
    }

    private func remove(browser: NWBrowser) {
        browser.cancel()
        browsers.removeAll { $0 === browser }
    }

    private func update(results: Set<NWBrowser.Result>, serviceType: String) {
        let discovered = results.map { result -> DiscoveredTV in
            let name: String
            if case .service(let serviceName, _, _, _) = result.endpoint {
                name = serviceName
            } else {
                name = "TV encontrada"
            }
            let tv = DiscoveredTV(name: name, type: serviceType, serviceType: serviceType)
            resolve(result.endpoint, for: tv)
            return tv
        }
        devices = Array(Set(discovered)).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func resolve(_ endpoint: NWEndpoint, for tv: DiscoveredTV) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        resolutionConnections.append(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            if case .ready = state, case .hostPort(let host, let port) = connection.currentPath?.remoteEndpoint {
                Task { @MainActor in
                    if let index = self.devices.firstIndex(where: { $0.id == tv.id }) {
                        self.devices[index] = DiscoveredTV(id: tv.id, name: tv.name, type: tv.type, host: String(describing: host), port: Int(port.rawValue), serviceType: tv.serviceType)
                    }
                    connection.cancel()
                    self.resolutionConnections.removeAll { $0 === connection }
                }
            }
        }
        connection.start(queue: .main)
    }

    private func startDNSFallback() {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
        process.arguments = ["-B", "_googlecast._tcp", "local"]
        process.standardOutput = pipe
        process.standardError = pipe
        dnsBrowseProcess = process
        do {
            try process.run()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) { [weak self, weak process] in
                process?.terminate()
                process?.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in
                    self?.consumeDNSOutput(text + "\n")
                    self?.dnsBrowseProcess = nil
                }
            }
        } catch {
            dnsBrowseProcess = nil
        }
        startLegacyBonjourFallback()
    }

    private func consumeDNSOutput(_ text: String) {
        dnsBrowseBuffer += text
        let lines = dnsBrowseBuffer.split(separator: "\n", omittingEmptySubsequences: false)
        dnsBrowseBuffer = String(lines.last ?? "")

        for line in lines.dropLast() {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.contains("Add"), let serviceIndex = parts.firstIndex(of: "_googlecast._tcp."), serviceIndex + 1 < parts.count else { continue }
            let instance = String(parts[serviceIndex + 1]).replacingOccurrences(of: "\\ ", with: " ")
            resolveDNSInstance(instance)
        }
    }

    private func resolveDNSInstance(_ instance: String) {
        guard !devices.contains(where: { $0.name == instance }) else { return }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
        process.arguments = ["-L", instance, "_googlecast._tcp", "local"]
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.consumeDNSLookup(text, instance: instance)
                process?.terminate()
            }
        }
        dnsLookups.append(process)
        try? process.run()
    }

    private func consumeDNSLookup(_ text: String, instance: String) {
        guard let marker = text.range(of: " can be reached at ") else { return }
        let endpoint = text[marker.upperBound...].split(whereSeparator: { $0 == ":" || $0 == " " || $0 == "\n" }).first.map(String.init) ?? ""
        guard !endpoint.isEmpty else { return }
        let tv = DiscoveredTV(name: instance, type: "_googlecast._tcp", host: endpoint.trimmingCharacters(in: CharacterSet(charactersIn: ".")), port: 8009, serviceType: "_googlecast._tcp")
        if let index = devices.firstIndex(where: { $0.name == instance }) {
            devices[index] = tv
        } else {
            devices.append(tv)
        }
        devices.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func startLegacyBonjourFallback() {
        let delegate = BonjourDelegate(
            onFound: { [weak self] service in
                Task { @MainActor in self?.foundLegacyService(service) }
            },
            onResolved: { [weak self] service in
                Task { @MainActor in self?.resolvedLegacyService(service) }
            }
        )
        let browser = NetServiceBrowser()
        browser.delegate = delegate
        browser.schedule(in: .main, forMode: .common)
        browser.searchForServices(ofType: "_googlecast._tcp.", inDomain: "local.")
        legacyDelegate = delegate
        legacyBrowser = browser
    }

    private func foundLegacyService(_ service: NetService) {
        guard !devices.contains(where: { $0.name == service.name }) else { return }
        devices.append(DiscoveredTV(name: service.name, type: "_googlecast._tcp", serviceType: "_googlecast._tcp"))
        devices.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func resolvedLegacyService(_ service: NetService) {
        let host = service.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? ""
        guard !host.isEmpty else { return }
        let tv = DiscoveredTV(name: service.name, type: "_googlecast._tcp", host: host, port: service.port, serviceType: "_googlecast._tcp")
        if let index = devices.firstIndex(where: { $0.name == service.name }) {
            devices[index] = tv
        } else {
            devices.append(tv)
        }
    }
}

private final class BonjourDelegate: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let onFound: (NetService) -> Void
    private let onResolved: (NetService) -> Void

    init(onFound: @escaping (NetService) -> Void, onResolved: @escaping (NetService) -> Void) {
        self.onFound = onFound
        self.onResolved = onResolved
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        onFound(service)
        service.delegate = self
        service.schedule(in: .main, forMode: .common)
        service.resolve(withTimeout: 3)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        onResolved(sender)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {}
}
