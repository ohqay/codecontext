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
        
        do {
            // Try to create container with automatic migration
            let config = ModelConfiguration(
                schema: schema, 
                isStoredInMemoryOnly: inMemory,
                allowsSave: true,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
            container = try ModelContainer(for: schema, configurations: [config])
            print("[DataController] Successfully created ModelContainer")
        } catch {
            print("[DataController] Failed to create ModelContainer with error: \(error)")
            
            // If migration fails, try creating a fresh container (this will lose existing data)
            // In a production app, you'd want more sophisticated migration handling
            do {
                let freshConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true, // Force in-memory to avoid conflicts
                    allowsSave: true,
                    groupContainer: .none,
                    cloudKitDatabase: .none
                )
                container = try ModelContainer(for: schema, configurations: [freshConfig])
                print("[DataController] Created fallback in-memory container")
            } catch {
                // Last resort: fatal error
                fatalError("Failed to create fallback ModelContainer: \(error)")
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
