nonisolated struct Page<Element: Sendable>: Sendable {
    let items: [Element]
    /// `nil` when this is the last page.
    let nextPage: Int?
}

extension Page: Equatable where Element: Equatable {}
