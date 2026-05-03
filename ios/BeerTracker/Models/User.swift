import Foundation

struct AppUser: Codable, Identifiable, Hashable {
    let id: UUID
    let appleId: String?
    let nickname: String
    let profilePictureURL: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case appleId = "apple_id"
        case nickname
        case profilePictureURL = "profile_picture_url"
        case createdAt = "created_at"
    }
}

struct LeaderboardEntry: Codable, Identifiable, Hashable {
    var id: UUID { userId }
    let userId: UUID
    let nickname: String
    let profilePictureURL: String?
    let totalBeers: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case nickname
        case profilePictureURL = "profile_picture_url"
        case totalBeers = "total_beers"
    }
}

struct PersonalStats: Codable {
    let total: Int
    let currentStreak: Int
    let longestStreak: Int
    let mostActiveDayOfWeek: Int?
    let mostActiveHour: Int?
    let timeline: [TimelinePoint]
    let drinkTypes: [DrinkTypeBucket]?
    let netScore: Int?
    let totalUpvotes: Int?
    let totalDownvotes: Int?
    let followers: Int?
    let following: Int?
}

struct TimelinePoint: Codable, Identifiable, Hashable {
    var id: String { date }
    let date: String
    let count: Int
}

// MARK: - Groups

struct BeerGroup: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let description: String?
    let createdBy: UUID
    let createdAt: Date?
    let role: String?
    let memberCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, description, role
        case createdBy = "created_by"
        case createdAt = "created_at"
        case memberCount = "member_count"
    }

    var isAdmin: Bool { role == "admin" }
}

struct GroupMember: Codable, Identifiable, Hashable {
    let id: UUID
    let nickname: String
    let profilePictureURL: String?
    let role: String
    let joinedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, nickname, role
        case profilePictureURL = "profile_picture_url"
        case joinedAt = "joined_at"
    }

    var isAdmin: Bool { role == "admin" }
}

struct GroupInvite: Codable, Identifiable, Hashable {
    let id: UUID
    let status: String
    let createdAt: Date?
    let group: GroupSummary
    let invitedByUser: BeerUserStub

    enum CodingKeys: String, CodingKey {
        case id, status, group
        case createdAt = "created_at"
        case invitedByUser = "invited_by_user"
    }
}

struct GroupSummary: Codable, Hashable {
    let id: UUID
    let name: String
    let description: String?
}

// MARK: - Search

struct SearchUser: Codable, Identifiable, Hashable {
    let id: UUID
    let nickname: String
    let profilePictureURL: String?
    let isFollowing: Bool

    enum CodingKeys: String, CodingKey {
        case id, nickname
        case profilePictureURL = "profile_picture_url"
        case isFollowing = "is_following"
    }
}
