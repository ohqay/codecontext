import Foundation
import SwiftData

@MainActor
final class DataController {
    static let shared = DataController()

    let container: ModelContainer

    private init(inMemory: Bool = false) {
        let schema = Schema([
            SDWorkspace.self,
            SDPreference.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
