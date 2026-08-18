import Foundation

/// One page of `GET /v1/workouts?page=<n>&pageSize=<m>`.
struct HevyWorkoutsPage: Decodable, Equatable, Sendable {
    /// Page number Hevy echoes back.
    let page: Int
    /// Total number of pages available for the requested page size.
    let pageCount: Int
    let workouts: [HevyWorkoutDTO]

    private enum CodingKeys: String, CodingKey {
        case page
        case pageCount = "page_count"
        case workouts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        page = try container.decodeLooseIntIfPresent(forKey: .page) ?? 1
        pageCount = try container.decodeLooseIntIfPresent(forKey: .pageCount) ?? 1
        workouts = try container.decodeIfPresent([HevyWorkoutDTO].self, forKey: .workouts) ?? []
    }
}
