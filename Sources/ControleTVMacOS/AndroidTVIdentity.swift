import Foundation

struct AndroidTVIdentity {
    let der: Data
    let p12: Data
    let password = "controle-tv"

    private static let derAccount = "android-tv-client-certificate-der"
    private static let p12Account = "android-tv-client-identity-p12"
    static func loadOrCreate() throws -> AndroidTVIdentity {
        let store = KeychainStore()
        if let der = try store.data(account: derAccount), let p12 = try store.data(account: p12Account) {
            return AndroidTVIdentity(der: der, p12: p12)
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let key = directory.appendingPathComponent("key.pem")
        let cert = directory.appendingPathComponent("cert.pem")
        let der = directory.appendingPathComponent("cert.der")
        let p12 = directory.appendingPathComponent("cert.p12")

        try runOpenSSL(arguments: ["req", "-x509", "-newkey", "rsa:2048", "-sha256", "-nodes", "-keyout", key.path, "-out", cert.path, "-days", "3650", "-subj", "/CN=Controle TV macOS"])
        try runOpenSSL(arguments: ["x509", "-in", cert.path, "-outform", "DER", "-out", der.path])
        try runOpenSSL(arguments: ["pkcs12", "-export", "-inkey", key.path, "-in", cert.path, "-out", p12.path, "-passout", "pass:controle-tv"])

        let derData = try Data(contentsOf: der)
        let p12Data = try Data(contentsOf: p12)
        try store.save(data: derData, account: derAccount)
        try store.save(data: p12Data, account: p12Account)
        return AndroidTVIdentity(der: derData, p12: p12Data)
    }

    func materialize(in directory: URL) throws -> (der: URL, p12: URL) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let derURL = directory.appendingPathComponent("client.der")
        let p12URL = directory.appendingPathComponent("client.p12")
        try der.write(to: derURL, options: .completeFileProtection)
        try p12.write(to: p12URL, options: .completeFileProtection)
        return (derURL, p12URL)
    }

    private static func runOpenSSL(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "OpenSSL falhou."
            throw TVRemoteError.transport(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
