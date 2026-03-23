import Foundation

// MARK: - Client → Server

enum ClientMessage: Encodable {
    case auth(token: String)
    case input(session: String, data: String)
    case resize(session: String, cols: Int, rows: Int)
    case sessionCreate
    case sessionClose(session: String)
    case sessionList
    case ping(timestamp: UInt64)

    enum CodingKeys: String, CodingKey {
        case type
        case token, session, data, cols, rows, timestamp
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .auth(let token):
            try container.encode("Auth", forKey: .type)
            try container.encode(token, forKey: .token)
        case .input(let session, let data):
            try container.encode("Input", forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(data, forKey: .data)
        case .resize(let session, let cols, let rows):
            try container.encode("Resize", forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(cols, forKey: .cols)
            try container.encode(rows, forKey: .rows)
        case .sessionCreate:
            try container.encode("SessionCreate", forKey: .type)
        case .sessionClose(let session):
            try container.encode("SessionClose", forKey: .type)
            try container.encode(session, forKey: .session)
        case .sessionList:
            try container.encode("SessionList", forKey: .type)
        case .ping(let timestamp):
            try container.encode("Ping", forKey: .type)
            try container.encode(timestamp, forKey: .timestamp)
        }
    }
}

// MARK: - Server → Client

enum ServerMessage: Decodable {
    case authOk(deviceId: String)
    case authFail(reason: String)
    case output(session: String, data: String)
    case sessionCreated(session: String, shell: String)
    case sessionClosed(session: String)
    case sessionList(sessions: [SessionInfo])
    case sessionExited(session: String, code: Int)
    case pong(timestamp: UInt64)
    case error(code: String, message: String)

    enum CodingKeys: String, CodingKey {
        case type
        case device_id, reason, session, data, shell, sessions, code, message, timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try container.decode(String.self, forKey: .type)

        switch type_ {
        case "AuthOk":
            let deviceId = try container.decode(String.self, forKey: .device_id)
            self = .authOk(deviceId: deviceId)
        case "AuthFail":
            let reason = try container.decode(String.self, forKey: .reason)
            self = .authFail(reason: reason)
        case "Output":
            let session = try container.decode(String.self, forKey: .session)
            let data = try container.decode(String.self, forKey: .data)
            self = .output(session: session, data: data)
        case "SessionCreated":
            let session = try container.decode(String.self, forKey: .session)
            let shell = try container.decode(String.self, forKey: .shell)
            self = .sessionCreated(session: session, shell: shell)
        case "SessionClosed":
            let session = try container.decode(String.self, forKey: .session)
            self = .sessionClosed(session: session)
        case "SessionList":
            let sessions = try container.decode([SessionInfo].self, forKey: .sessions)
            self = .sessionList(sessions: sessions)
        case "SessionExited":
            let session = try container.decode(String.self, forKey: .session)
            let code = try container.decode(Int.self, forKey: .code)
            self = .sessionExited(session: session, code: code)
        case "Pong":
            let timestamp = try container.decode(UInt64.self, forKey: .timestamp)
            self = .pong(timestamp: timestamp)
        case "Error":
            let code = try container.decode(String.self, forKey: .code)
            let message = try container.decode(String.self, forKey: .message)
            self = .error(code: code, message: message)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "Unknown message type: \(type_)"))
        }
    }
}

struct SessionInfo: Decodable {
    let id: String
    let shell: String
    let alive: Bool
}

struct TermDims: Codable {
    let cols: Int
    let rows: Int
}
