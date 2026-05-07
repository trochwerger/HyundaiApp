import Foundation
import SwiftData

public enum PersistenceController {
    public static let appGroupIdentifier = "group.com.tomas.hyundaiapp"

    public static let shared: ModelContainer = {
        do {
            let configuration = ModelConfiguration(
                groupContainer: .identifier(appGroupIdentifier),
                cloudKitDatabase: .none
            )
            return try ModelContainer(
                for: StatusSnapshot.self,
                Trip.self,
                ChargeSession.self,
                configurations: configuration
            )
        } catch {
            fatalError("Failed to configure SwiftData: \(error)")
        }
    }()

    public static func inMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: StatusSnapshot.self,
            Trip.self,
            ChargeSession.self,
            configurations: configuration
        )
    }
}
