import Foundation

struct PagedResult<T> {
    let items: [T]
    let totalCount: Int
    let currentPage: Int
    let hasMore: Bool
}
