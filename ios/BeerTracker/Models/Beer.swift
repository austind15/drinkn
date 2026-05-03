import Foundation
import CoreLocation

enum DrinkType: String, Codable, CaseIterable, Hashable, Identifiable {
    case beer
    case wine
    case spirits
    case cocktail
    case cider

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .beer:     return "🍺"
        case .wine:     return "🍷"
        case .spirits:  return "🥃"
        case .cocktail: return "🍹"
        case .cider:    return "🍏"
        }
    }

    var displayName: String {
        switch self {
        case .beer:     return "Beer"
        case .wine:     return "Wine"
        case .spirits:  return "Spirits"
        case .cocktail: return "Cocktail"
        case .cider:    return "Cider"
        }
    }
}

struct Beer: Codable, Identifiable, Hashable {
    let id: UUID
    let photoURL: String
    let timestamp: Date
    let latitude: Double?
    let longitude: Double?
    let locationName: String?
    let note: String?
    let drinkType: DrinkType?
    let user: BeerUserStub?
    let score: Int?
    let upvotes: Int?
    let downvotes: Int?
    let myVote: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case photoURL = "photo_url"
        case timestamp
        case latitude
        case longitude
        case locationName = "location_name"
        case note
        case drinkType = "drink_type"
        case user
        case score
        case upvotes
        case downvotes
        case myVote = "my_vote"
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var resolvedDrinkType: DrinkType { drinkType ?? .beer }
}

struct BeerUserStub: Codable, Hashable {
    let id: UUID
    let nickname: String
    let profilePictureURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case nickname
        case profilePictureURL = "profile_picture_url"
    }
}

struct BeerTotal: Codable {
    let total: Int
    let goal: Int
}

struct DrinkTypeBucket: Codable, Identifiable, Hashable {
    var id: String { type }
    let type: String
    let count: Int

    var drinkType: DrinkType? { DrinkType(rawValue: type) }
}

struct TeamStats: Codable {
    let total: Int
    let myCount: Int
    let weekTotal: Int?
    let byHour: [HourBucket]
    let byDayOfWeek: [DayOfWeekBucket]
    let byWeek: [WeekBucket]
    let byMonth: [MonthBucket]
    let cumulative: [CumulativePoint]
    let topUsers: [TopUser]
    let drinkTypes: [DrinkTypeBucket]?
}

struct HourBucket: Codable, Identifiable, Hashable {
    var id: Int { hour }
    let hour: Int
    let count: Int
}

struct DayOfWeekBucket: Codable, Identifiable, Hashable {
    var id: Int { day }
    let day: Int        // 0 = Sunday … 6 = Saturday
    let count: Int
}

struct WeekBucket: Codable, Identifiable, Hashable {
    var id: String { week }
    let week: String
    let count: Int
}

struct MonthBucket: Codable, Identifiable, Hashable {
    var id: String { month }
    let month: String
    let count: Int
}

struct CumulativePoint: Codable, Identifiable, Hashable {
    var id: String { date }
    let date: String
    let total: Int
}

struct TopUser: Codable, Identifiable, Hashable {
    var id: UUID { userId }
    let userId: UUID
    let nickname: String
    let profilePictureURL: String?
    let count: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case nickname
        case profilePictureURL = "profile_picture_url"
        case count
    }
}

struct VoteResponse: Codable {
    let score: Int
    let upvotes: Int
    let downvotes: Int
    let myVote: Int

    enum CodingKeys: String, CodingKey {
        case score, upvotes, downvotes
        case myVote = "myVote"
    }
}
