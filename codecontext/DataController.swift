import Foundation
import SwiftData

@MainActor
final class DataController {
    static let shared = DataController()

    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: SDWorkspace.self, SDPreference.self,
                configurations: ModelConfiguration("default", isStoredInMemoryOnly: false)
            )
            print("[DataController] Successfully created ModelContainer")
        } catch let containerError as NSError {
            if containerError.code == 134110 {  // Migration error code
                print("[DataController] Migration failed with error: \(containerError)")
                // Attempt to delete the existing store and recreate
                let storeURL = ModelConfiguration("default", isStoredInMemoryOnly: false).url
                do {
                    try FileManager.default.removeItem(at: storeURL)
                    print("[DataController] Deleted existing store at \(storeURL.path)")
                    container = try ModelContainer(
                        for: SDWorkspace.self, SDPreference.self,
                        configurations: ModelConfiguration(
                            "default", isStoredInMemoryOnly: false)
                    )
                    print(
                        "[DataController] Successfully recreated ModelContainer after deleting old store"
                    )
                } catch {
                    print("[DataController] Failed to delete and recreate store: \(error)")
                    container = try! ModelContainer(
                        for: SDWorkspace.self, SDPreference.self,
                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                    )
                    print("[DataController] Created fallback in-memory container")
                }
            } else {
                print(
                    "[DataController] Failed to create ModelContainer with error: \(containerError)"
                )
                container = try! ModelContainer(
                    for: SDWorkspace.self, SDPreference.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
                print("[DataController] Created fallback in-memory container")
            }
        }

        // Perform any necessary data migrations after container creation
        performPostMigrationTasks()
    }

    /// Perform any necessary data migrations or fixes after container creation
    private func performPostMigrationTasks() {
        Task { @MainActor in
            do {
                let context = ModelContext(container)

                // Ensure all workspaces have IDs (migration from old schema)
                let fetchDescriptor = FetchDescriptor<SDWorkspace>()
                let workspaces = try context.fetch(fetchDescriptor)

                var needsSave = false
                for workspace in workspaces {
                    if workspace.id.isEmpty {
                        workspace.id = UUID().uuidString
                        needsSave = true
                        print("[DataController] Added ID to existing workspace: \(workspace.name)")
                    }
                }

                if needsSave {
                    try context.save()
                    print("[DataController] Completed workspace ID migration")
                }

            } catch {
                print("[DataController] Warning: Post-migration tasks failed: \(error)")
                // Don't fatal error here, as this isn't critical
            }
        }
    }
}
