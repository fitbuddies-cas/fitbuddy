import Foundation

/// One page of `GET /v1/routines?page=<n>&pageSize=<m>` — the same envelope
/// as `HevyWorkoutsPage`, around routines.
struct HevyRoutinesPage: Decodable, Equatable, Sendable {
    /// Page number Hevy echoes back.
    let page: Int
    /// Total number of pages available for the requested page size.
    let pageCount: Int
    let routines: [HevyRoutineDTO]

    private enum CodingKeys: String, CodingKey {
        case page
        case pageCount = "page_count"
        case routines
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        page = try container.decodeLooseIntIfPresent(forKey: .page) ?? 1
        pageCount = try container.decodeLooseIntIfPresent(forKey: .pageCount) ?? 1
        routines = try container.decodeIfPresent([HevyRoutineDTO].self, forKey: .routines) ?? []
    }
}
