import Foundation
import Network
import SystemConfiguration
import VoiceCore

/// Minimaler HTTP/1.1-Server ohne Fremdbibliotheken (Network.framework).
/// Eine Anfrage pro Verbindung, danach wird die Verbindung geschlossen.

struct HTTPRequest {
    var method: String
    var path: String
    var query: String
    var headers: [String: String]
    var body: Data

    /// Wert eines Parameters aus der Adresse, z. B. "show" aus "?show=the-voice-of-germany"
    func queryValue(_ name: String) -> String? {
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.first == name {
                let value = parts.count > 1 ? parts[1] : ""
                return value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
            }
        }
        return nil
    }

    enum ParseResult {
        case incomplete
        case invalid
        case ok(HTTPRequest)
    }

    static func parse(_ data: Data) -> ParseResult {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > 64 * 1024 ? .invalid : .incomplete
        }
        guard let head = String(data: data[data.startIndex..<separator.lowerBound], encoding: .utf8) else {
            return .invalid
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length >= 0, length <= 1_000_000 else { return .invalid }
        let bodyStart = separator.upperBound
        guard data.endIndex - bodyStart >= length else { return .incomplete }
        let body = data.subdata(in: bodyStart..<(bodyStart + length))

        let target = String(requestLine[1])
        let parts = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = String(parts[0])
        return .ok(HTTPRequest(
            method: String(requestLine[0]).uppercased(),
            path: rawPath.removingPercentEncoding ?? rawPath,
            query: parts.count > 1 ? String(parts[1]) : "",
            headers: headers,
            body: body
        ))
    }
}

struct HTTPResponse {
    var status: Int
    var contentType: String
    var body: Data

    static func json<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONCoding.encoder.encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: data)
    }

    static func error(_ message: String, status: Int) -> HTTPResponse {
        json(APIError(error: message), status: status)
    }

    func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        // Erlaubt eine Web-App, die woanders läuft (z. B. beim Entwickeln), die API zu nutzen
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        head += "Access-Control-Allow-Headers: Content-Type\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        default: return "Status"
        }
    }
}

final class HTTPServer {
    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let listener: NWListener
    private let queue = DispatchQueue(label: "io.github.fotocast.tvlauncher.http")
    private let handler: Handler

    init(port: UInt16, handler: @escaping Handler) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw NWError.posix(.EINVAL) }
        self.listener = try NWListener(using: .tcp, on: nwPort)
        self.handler = handler
        // Im lokalen Netz ankündigen (Name = Computername aus den Systemeinstellungen)
        let host = (SCDynamicStoreCopyLocalHostName(nil) as String?).map { "\($0).local" }
            ?? ProcessInfo.processInfo.hostName
        let txt = NWTXTRecord(["host": host, "port": String(port)])
        listener.service = NWListener.Service(type: Discovery.serviceType, txtRecord: txt)
        listener.serviceRegistrationUpdateHandler = { change in
            if case .add(let endpoint) = change { serverLog("Im Netzwerk angekündigt: \(endpoint) (\(host))") }
        }
    }

    func start() {
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                serverLog("Server bereit.")
            case .failed(let error):
                serverLog("Server-Fehler: \(error)")
                exit(1)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }
            connection.start(queue: self.queue)
            self.receive(on: connection, buffer: Data())
        }
        listener.start(queue: queue)
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data = data { buffer.append(data) }

            switch HTTPRequest.parse(buffer) {
            case .ok(let request):
                let handler = self.handler
                Task {
                    let response = await handler(request)
                    connection.send(content: response.serialized(), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            case .invalid:
                let response = HTTPResponse.error("Ungültige Anfrage", status: 400)
                connection.send(content: response.serialized(), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            case .incomplete:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }
}
