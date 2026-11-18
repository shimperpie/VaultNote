import Foundation

/// 笔记数据模型
struct Note: Identifiable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
