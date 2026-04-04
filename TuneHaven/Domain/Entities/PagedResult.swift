import Foundation

struct PagedResult<T: Sendable>: Sendable {
    let items: [T]
    let totalCount: Int
    let currentPage: Int
    let hasMore: Bool
}
