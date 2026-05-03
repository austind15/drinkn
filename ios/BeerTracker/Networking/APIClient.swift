import Foundation
import UIKit

enum APIError: LocalizedError {
    case http(method: String, path: String, code: Int, body: String?)
    case decoding(path: String, error: Error)
    case transport(path: String, error: Error)
    case invalidResponse(path: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .http(let method, let path, let code, let body):
            return "HTTP \(code) on \(method) \(path)\n\(body ?? "")"
        case .decoding(let path, let err):
            return "Decoding error on \(path): \(err.localizedDescription)"
        case .transport(let path, let err):
            return "Network error on \(path): \(err.localizedDescription)"
        case .invalidResponse(let path):
            return "Invalid response from \(path)"
        case .cancelled:
            return "Request cancelled"
        }
    }

    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)

        let dec = JSONDecoder()
        // Backend timestamps are ISO-8601 with fractional seconds (Postgres).
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatterNoFrac = ISO8601DateFormatter()
        isoFormatterNoFrac.formatOptions = [.withInternetDateTime]

        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let d = isoFormatter.date(from: str) { return d }
            if let d = isoFormatterNoFrac.date(from: str) { return d }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(str)")
        }
        self.decoder = dec

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
    }

    // MARK: - Auth

    struct AppleAuthResponse: Codable {
        let token: String
        let user: AppUser
        let profileComplete: Bool
    }

    func signInWithApple(identityToken: String) async throws -> AppleAuthResponse {
        try await postJSON(
            path: "/auth/apple",
            body: ["identityToken": identityToken],
            authorized: false,
            decode: AppleAuthResponse.self
        )
    }

    // MARK: - Users

    func me() async throws -> AppUser {
        struct Resp: Codable { let user: AppUser }
        let r: Resp = try await getJSON(path: "/users/me")
        return r.user
    }

    func updateProfile(nickname: String?, profilePicture: UIImage?) async throws -> AppUser {
        var fields: [String: String] = [:]
        if let nickname = nickname { fields["nickname"] = nickname }
        var files: [MultipartFile] = []
        if let img = profilePicture {
            let resized = img.resizedForUpload(maxDimension: 512)
            if let data = resized.jpegData(compressionQuality: 0.8) {
                files.append(.init(field: "profilePicture", filename: "profile.jpg", mime: "image/jpeg", data: data))
            }
        }
        struct Resp: Codable { let user: AppUser }
        let r: Resp = try await postMultipart(path: "/users/me", method: "PUT", fields: fields, files: files)
        return r.user
    }

    func leaderboard(search: String? = nil, groupId: UUID? = nil) async throws -> [LeaderboardEntry] {
        struct Resp: Codable { let users: [LeaderboardEntry] }
        var params: [String: String] = [:]
        if let q = search?.trimmingCharacters(in: .whitespaces), !q.isEmpty { params["search"] = q }
        if let gid = groupId { params["groupId"] = gid.uuidString.lowercased() }
        let r: Resp = try await getJSON(path: "/users" + Self.queryString(params))
        return r.users
    }

    func searchUsers(query: String) async throws -> [SearchUser] {
        struct Resp: Codable { let users: [SearchUser] }
        let path = "/users/search" + Self.queryString(["q": query])
        let r: Resp = try await getJSON(path: path)
        return r.users
    }

    struct UserStatsResponse: Codable {
        let user: AppUser
        let stats: PersonalStats
        let beers: [Beer]
        let isFollowing: Bool?
    }

    func userStats(id: UUID) async throws -> UserStatsResponse {
        let tz = TimeZone.current.secondsFromGMT() / 60
        return try await getJSON(path: "/users/\(id.uuidString.lowercased())/stats?tzOffsetMinutes=\(tz)")
    }

    // MARK: - Beers

    func logBeer(photo: UIImage, latitude: Double?, longitude: Double?, locationName: String?, note: String?, drinkType: DrinkType) async throws -> Beer {
        let resized = photo.resizedForUpload(maxDimension: 1200)
        guard let data = resized.jpegData(compressionQuality: 0.75) else {
            throw APIError.invalidResponse(path: "/beers")
        }
        var fields: [String: String] = [:]
        if let lat = latitude { fields["latitude"] = String(lat) }
        if let lon = longitude { fields["longitude"] = String(lon) }
        if let n = locationName, !n.isEmpty { fields["locationName"] = n }
        if let note = note, !note.isEmpty { fields["note"] = note }
        fields["drinkType"] = drinkType.rawValue

        let files = [MultipartFile(field: "photo", filename: "beer.jpg", mime: "image/jpeg", data: data)]
        struct Resp: Codable { let beer: Beer }
        let r: Resp = try await postMultipart(path: "/beers", method: "POST", fields: fields, files: files)
        return r.beer
    }

    enum FeedMode: String {
        case recent, following, group
    }

    func beers(limit: Int = 20, offset: Int = 0, mode: FeedMode = .recent, groupId: UUID? = nil) async throws -> [Beer] {
        struct Resp: Codable { let beers: [Beer] }
        var params: [String: String] = ["limit": "\(limit)", "offset": "\(offset)", "mode": mode.rawValue]
        if let gid = groupId { params["groupId"] = gid.uuidString.lowercased() }
        let r: Resp = try await getJSON(path: "/beers" + Self.queryString(params))
        return r.beers
    }

    func beersTotal(groupId: UUID? = nil) async throws -> BeerTotal {
        var params: [String: String] = [:]
        if let gid = groupId { params["groupId"] = gid.uuidString.lowercased() }
        return try await getJSON(path: "/beers/total" + Self.queryString(params))
    }

    func beersMap(groupId: UUID? = nil) async throws -> [Beer] {
        struct Resp: Codable { let beers: [Beer] }
        var params: [String: String] = [:]
        if let gid = groupId { params["groupId"] = gid.uuidString.lowercased() }
        let r: Resp = try await getJSON(path: "/beers/map" + Self.queryString(params))
        return r.beers
    }

    func teamStats(groupId: UUID? = nil) async throws -> TeamStats {
        let tz = TimeZone.current.secondsFromGMT() / 60
        var params: [String: String] = ["tzOffsetMinutes": "\(tz)"]
        if let gid = groupId { params["groupId"] = gid.uuidString.lowercased() }
        return try await getJSON(path: "/beers/stats" + Self.queryString(params))
    }

    // MARK: - Votes

    func vote(beerId: UUID, vote: Int) async throws -> VoteResponse {
        try await postJSON(
            path: "/votes/\(beerId.uuidString.lowercased())",
            body: ["vote": vote],
            authorized: true,
            decode: VoteResponse.self
        )
    }

    // MARK: - Follows

    func follow(userId: UUID) async throws {
        struct Resp: Codable { let ok: Bool }
        let _: Resp = try await postJSON(
            path: "/follows/\(userId.uuidString.lowercased())",
            body: [:],
            authorized: true,
            decode: Resp.self
        )
    }

    func unfollow(userId: UUID) async throws {
        struct Resp: Codable { let ok: Bool }
        var req = try await makeRequest(path: "/follows/\(userId.uuidString.lowercased())", method: "DELETE")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let _: Resp = try await send(req, path: "/follows/\(userId.uuidString.lowercased())", method: "DELETE")
    }

    func followersList(userId: UUID) async throws -> [SearchUser] {
        struct Resp: Codable { let users: [SearchUser] }
        let r: Resp = try await getJSON(path: "/follows/\(userId.uuidString.lowercased())/followers")
        return r.users
    }

    func followingList(userId: UUID) async throws -> [SearchUser] {
        struct Resp: Codable { let users: [SearchUser] }
        let r: Resp = try await getJSON(path: "/follows/\(userId.uuidString.lowercased())/following")
        return r.users
    }

    // MARK: - Groups

    func myGroups() async throws -> [BeerGroup] {
        struct Resp: Codable { let groups: [BeerGroup] }
        let r: Resp = try await getJSON(path: "/groups")
        return r.groups
    }

    func discoverGroups(search: String? = nil) async throws -> [BeerGroup] {
        struct Resp: Codable { let groups: [BeerGroup] }
        var params: [String: String] = [:]
        if let s = search?.trimmingCharacters(in: .whitespaces), !s.isEmpty { params["search"] = s }
        let r: Resp = try await getJSON(path: "/groups/discover" + Self.queryString(params))
        return r.groups
    }

    func createGroup(name: String, description: String?) async throws -> BeerGroup {
        struct Resp: Codable { let group: BeerGroup }
        var body: [String: Any] = ["name": name]
        if let d = description?.trimmingCharacters(in: .whitespaces), !d.isEmpty { body["description"] = d }
        let r: Resp = try await postJSON(path: "/groups", body: body, authorized: true, decode: Resp.self)
        return r.group
    }

    struct GroupDetailResponse: Codable {
        let group: BeerGroup
        let members: [GroupMember]
    }

    func groupDetail(id: UUID) async throws -> GroupDetailResponse {
        try await getJSON(path: "/groups/\(id.uuidString.lowercased())")
    }

    struct InviteSearchUser: Codable, Identifiable, Hashable {
        let id: UUID
        let nickname: String
        let profilePictureURL: String?
        let invitePending: Bool

        enum CodingKeys: String, CodingKey {
            case id, nickname
            case profilePictureURL = "profile_picture_url"
            case invitePending = "invite_pending"
        }
    }

    func inviteSearch(groupId: UUID, query: String) async throws -> [InviteSearchUser] {
        struct Resp: Codable { let users: [InviteSearchUser] }
        let params = query.trimmingCharacters(in: .whitespaces).isEmpty ? [:] : ["q": query]
        let r: Resp = try await getJSON(path: "/groups/\(groupId.uuidString.lowercased())/invite-search" + Self.queryString(params))
        return r.users
    }

    func inviteToGroup(groupId: UUID, userId: UUID) async throws {
        struct Invite: Codable {}
        struct Resp: Codable { let invite: Invite }
        let _: Resp = try await postJSON(
            path: "/groups/\(groupId.uuidString.lowercased())/invites",
            body: ["userId": userId.uuidString.lowercased()],
            authorized: true,
            decode: Resp.self
        )
    }

    func incomingInvites() async throws -> [GroupInvite] {
        struct Resp: Codable { let invites: [GroupInvite] }
        let r: Resp = try await getJSON(path: "/groups/invites/incoming")
        return r.invites
    }

    func acceptInvite(id: UUID) async throws {
        struct Resp: Codable { let ok: Bool }
        let _: Resp = try await postJSON(
            path: "/groups/invites/\(id.uuidString.lowercased())/accept",
            body: [:],
            authorized: true,
            decode: Resp.self
        )
    }

    func declineInvite(id: UUID) async throws {
        struct Resp: Codable { let ok: Bool }
        let _: Resp = try await postJSON(
            path: "/groups/invites/\(id.uuidString.lowercased())/decline",
            body: [:],
            authorized: true,
            decode: Resp.self
        )
    }

    func leaveGroup(id: UUID) async throws {
        struct Resp: Codable { let ok: Bool }
        let _: Resp = try await postJSON(
            path: "/groups/\(id.uuidString.lowercased())/leave",
            body: [:],
            authorized: true,
            decode: Resp.self
        )
    }

    func promoteMember(groupId: UUID, memberId: UUID) async throws {
        struct Resp: Codable { let ok: Bool }
        let _: Resp = try await postJSON(
            path: "/groups/\(groupId.uuidString.lowercased())/members/\(memberId.uuidString.lowercased())/promote",
            body: [:],
            authorized: true,
            decode: Resp.self
        )
    }

    // MARK: - Transport

    private func makeRequest(path: String, method: String = "GET", authorized: Bool = true) async throws -> URLRequest {
        // Split path from query string so we can append cleanly.
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let pathOnly = String(parts[0])
        let query = parts.count > 1 ? String(parts[1]) : nil

        let trimmed = pathOnly.hasPrefix("/") ? String(pathOnly.dropFirst()) : pathOnly
        var components = URLComponents(url: APIConfig.baseURL.appendingPathComponent(trimmed),
                                       resolvingAgainstBaseURL: false)!
        if let query = query {
            components.percentEncodedQuery = query
        }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        if authorized, let token = await AuthStore.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, path: String, method: String, decode: T.Type = T.self) async throws -> T {
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse(path: path)
            }
            if !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8)
                throw APIError.http(method: method, path: path, code: http.statusCode, body: body)
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decoding(path: path, error: error)
            }
        } catch let err as APIError {
            throw err
        } catch let err as URLError where err.code == .cancelled {
            throw APIError.cancelled
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            throw APIError.transport(path: path, error: error)
        }
    }

    private func getJSON<T: Decodable>(path: String) async throws -> T {
        let req = try await makeRequest(path: path, method: "GET")
        return try await send(req, path: path, method: "GET")
    }

    private func postJSON<T: Decodable>(path: String, body: [String: Any], authorized: Bool, decode: T.Type) async throws -> T {
        var req = try await makeRequest(path: path, method: "POST", authorized: authorized)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req, path: path, method: "POST")
    }

    private func postMultipart<T: Decodable>(path: String, method: String, fields: [String: String], files: [MultipartFile]) async throws -> T {
        var req = try await makeRequest(path: path, method: method)
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let crlf = "\r\n"
        for (k, v) in fields {
            body.append("--\(boundary)\(crlf)")
            body.append("Content-Disposition: form-data; name=\"\(k)\"\(crlf)\(crlf)")
            body.append(v)
            body.append(crlf)
        }
        for f in files {
            body.append("--\(boundary)\(crlf)")
            body.append("Content-Disposition: form-data; name=\"\(f.field)\"; filename=\"\(f.filename)\"\(crlf)")
            body.append("Content-Type: \(f.mime)\(crlf)\(crlf)")
            body.append(f.data)
            body.append(crlf)
        }
        body.append("--\(boundary)--\(crlf)")
        req.httpBody = body
        return try await send(req, path: path, method: method)
    }

    // MARK: - URL helpers

    private static func queryString(_ params: [String: String]) -> String {
        guard !params.isEmpty else { return "" }
        let items = params
            .map { (k, v) -> String in
                let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k
                let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
                return "\(ek)=\(ev)"
            }
            .joined(separator: "&")
        return "?" + items
    }
}

private struct MultipartFile {
    let field: String
    let filename: String
    let mime: String
    let data: Data
}

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}

extension UIImage {
    /// Returns a copy of the image scaled so neither dimension exceeds `maxDimension`,
    /// preserving aspect ratio. Returns `self` if already small enough.
    func resizedForUpload(maxDimension: CGFloat) -> UIImage {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension else { return self }
        let scale = maxDimension / largestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
