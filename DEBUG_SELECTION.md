# Debug Guide for Selection Issues

## What Was Fixed

### 1. Folder Selection Not Showing
**Problem:** Folders never showed checkmarks even when selected
**Cause:** `collectAffectedPaths` only collected file paths, not directory paths
**Fix:** Now collects ALL paths (both files and directories)

### 2. XML Context Not Generating
**Problem:** Nothing showed in context preview
**Cause:** Incorrect logic in `regenerateOutput` - was checking `isCancelled == false` and returning
**Fix:** Removed the faulty check that was preventing regeneration

### 3. Selection State Management
**Problem:** SelectionManager wasn't distinguishing between files and directories
**Cause:** Only tracked a single set of paths
**Fix:** Now tracks:
- `selectedPaths`: All selected items (files + directories) for UI display
- `selectedFiles`: Only files for token counting and XML generation

### 4. Token Counter Not Updating
**Problem:** Token count stayed at 0
**Cause:** Was trying to count tokens for directories
**Fix:** Only counts tokens for actual files

## How Selection Now Works

1. **User clicks checkbox on folder**
   - `FileTreeView.handleSelectionChange` is called
   - Runs on detached task with `.userInitiated` priority

2. **Collect affected items**
   - `collectAffectedPathsAndFiles` gathers:
     - All paths (for UI updates)
     - Only file paths (for token counting)

3. **Update SelectionManager**
   - Updates both `selectedPaths` and `selectedFiles`
   - Returns `SelectionUpdate` with all affected paths

4. **Apply UI updates**
   - `applySelectionUpdate` sets `isSelected` for all affected nodes
   - Both files AND folders now show checkmarks

5. **Background token counting**
   - Only processes files (not directories)
   - Updates token count asynchronously

6. **XML generation**
   - Uses only selected files from `workspace.selectionJSON`
   - Debounced by 500ms to avoid rapid regeneration

## Testing Checklist

✅ Select a folder → Folder shows checkmark
✅ Select a folder → All child files show checkmarks
✅ Select a folder → All child folders show checkmarks
✅ Select a folder → Token count updates
✅ Select a folder → XML context generates
✅ Deselect a folder → All checkmarks removed
✅ Large folder selection → No UI hang

## Console Output to Monitor

```
[SelectionManager] Toggle completed in X.XXXs for Y files
[SelectionManager] Token calculation progress: XX%
[SelectionManager] Token counts updated in X.XXXs for Y files
[Generation Started] Selected files: X
[Generation Complete] Files: X, Tokens: Y
```