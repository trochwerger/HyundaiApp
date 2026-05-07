import Foundation
import SwiftData

@Model
public final class ChargeSession {
    public var id: UUID = UUID()
    public var startAt: Date = Date()
    public var endAt: Date = Date()
    public var startSoc: Int? = nil
    public var endSoc: Int? = nil
    public var estimatedKwh: Double? = nil

    public init(
        id: UUID = UUID(),
        startAt: Date = Date(),
        endAt: Date = Date(),
        startSoc: Int? = nil,
        endSoc: Int? = nil,
        estimatedKwh: Double? = nil
    ) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
        self.startSoc = startSoc
        self.endSoc = endSoc
        self.estimatedKwh = estimatedKwh
    }
}
