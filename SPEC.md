# Codebase Preparation Utility for LLMs - Technical Specification

## Project Overview

This macOS application serves as a specialized utility for developers who need to efficiently prepare and share codebase context with Large Language Models. The app provides a streamlined workflow for selecting files from a project directory, calculating token counts to manage context limits, and copying formatted output that LLMs can easily parse. The entire experience centers around native macOS design patterns, leveraging SwiftUI as the primary framework while maintaining the performance and polish expected from a modern Mac application.

## Core Architecture and Technology Stack

The application will be built primarily using SwiftUI, only falling back to AppKit in specific instances where SwiftUI causes performance issues or where specific functionality isn't possible with modern SwiftUI. Given SwiftUI's maturity and expanded feature set, these instances should be quite rare. The app targets macOS 26 Tahoe as the minimum deployment target, taking advantage of the new "liquid glass" design language that Apple has introduced across their operating systems.

NSOutlineView from AppKit will be employed specifically for the file tree sidebar due to its proven performance characteristics when handling large directory structures with potentially tens of thousands of files. This hybrid approach ensures optimal performance while maintaining modern Swift development practices. SwiftData serves as the persistence layer from the outset—no local storage approaches or temporary solutions will be used for any data that needs to persist between sessions. The app will be fully sandboxed to comply with both App Store requirements and best practices for distribution flexibility, utilizing security-scoped bookmarks to maintain persistent access to user-selected directories across application launches.

## User Interface Structure

The application adopts a single-window architecture with native tab support. Users can press Command-T to create a new tab where they can have a different codebase open. When switching between tabs, the sidebar automatically updates to show the file tree relevant to that specific codebase's workspace, with each tab maintaining its own independent selection state and preferences. The main window divides into distinct regions: a collapsible sidebar on the left displaying the file tree via NSOutlineView, a central content area containing the output preview, and a toolbar with essential controls.

The sidebar can be toggled on and off using the native Command-Backslash keyboard shortcut. At the top of the sidebar sits a dropdown menu that provides quick access to filtering preferences. This dropdown includes toggles for respecting .gitignore and .ignore files (enabled by default), as well as individual toggles for excluding common build directories and files: node_modules, .git, build, dist, .next, .venv, .DS_Store, and DerivedData. While these are excluded by default, users can selectively re-enable any of them through this same dropdown if they need to include these typically unwanted directories in their selection.

The file tree displays checkboxes for both individual files and entire directories, allowing granular or bulk selection. Next to each file, a token count badge shows the individual file's token contribution, while directories display rolled-up totals for all contained files. This multi-level token display helps users understand both the specific impact of individual files and the aggregate impact of entire folders on their total context budget.

## File Selection and Management

When users open a folder through the native file picker dialog (Command-O), the application performs an initial scan of the directory structure. By default, it respects both .gitignore and .ignore files automatically, though this behavior can be toggled off through the dropdown menu at the top of the sidebar. Hidden files remain hidden by default but can be revealed through a toggle in the same dropdown menu. The app never follows symlinks to prevent infinite loops and unexpected behavior.

The application automatically excludes binary files and files exceeding a reasonable size threshold. When such exclusions occur, a brief dialog appears indicating this action and provides a one-click option to include the files if desired. This dialog disappears automatically after a moment or can be dismissed immediately with an X button—essentially the inverse of showing a warning and requiring action to exclude.

File selection operates through distinct interaction patterns: checkboxes determine inclusion in the output, while clicking on a file itself (not its checkbox) highlights it for preview. With a file highlighted, pressing the spacebar triggers a Quick Look-style preview popup that displays the file contents with appropriate syntax highlighting. This preview can be dismissed by pressing Escape or pressing spacebar again, following native macOS Quick Look conventions.

The application watches for filesystem changes within the opened directory and automatically refreshes token counts and file listings when modifications occur. A manual refresh/sync button remains available in the interface to force a synchronization in case automatic updates don't trigger for any reason.

## Token Counting Implementation

Token counting uses a pure Swift tokenizer implementation that's compatible with OpenAI's GPT-4 family of models, including GPT-4o and GPT-4.1. The tokenizer is designed to be broadly applicable across OpenAI's model updates, running entirely offline to maintain user privacy while delivering responsive performance. Token counts appear at three distinct levels throughout the interface: individual files show their token contribution as badges directly in the tree view, directories display cumulative totals for all their contained files (whether selected or not, giving users insight into the cost of selecting entire folders), and a prominent total in the toolbar shows the aggregate count for all currently selected content.

For example, selecting an entire codebase might show 300,000 tokens in the toolbar, which would dynamically decrease as folders or files are deselected. The per-file badges and per-folder rollups update in real-time as selections change, giving immediate feedback about the token impact of each selection decision.

## Output Format and Structure

The application generates XML-formatted output specifically structured for optimal LLM parsing. The root element uses `<codebase>` as the parent tag, with individual files wrapped using the equals syntax: `<file=filename.ext>`. Within each file tag, the structure follows this specific format:

```
<file=ComponentHeader.tsx>
Path: /Users/tarek/project/src/components/ComponentHeader.tsx
`````typescript
// Actual file contents here
const ComponentHeader = () => {
  return <div>Header</div>
}
`````
</file=ComponentHeader.tsx>
```

The path appears on its own line prefixed with "Path:", providing the complete file path for context. The actual code content is wrapped in five backticks followed by the language indicator (determined by file extension), with five backticks closing the code block. This five-backtick approach is deliberate—if the file itself is a markdown file containing code blocks with three backticks, using five backticks ensures the LLM can properly parse the boundaries without confusion. The closing tag only needs the base tag name without repeating the equals syntax.

When the optional file tree representation is enabled (toggled via Command-B), an ASCII-style tree diagram appears at the beginning of the output, wrapped in `<fileTree>` tags with proper indentation to show the hierarchical structure. This provides LLMs with a visual overview of the codebase organization before processing individual files. The entire XML output maintains pretty-printed formatting with proper indentation for human readability.

## Output Preview Interface

The central area of the main window contains an output preview with specific behavior constraints. This preview exists within a fixed area with a scrollable text field, preventing the interface from becoming unwieldy when dealing with large codebases. If the preview contains 300,000 tokens worth of content, it won't create a massive window that extends forever—instead, the content remains contained within the scrollable field with defined boundaries.

While not required for the initial version, the architecture accommodates a planned enhancement where a user instructions section with a text field will sit at the top of the preview window. This future feature will allow users to add a prompt that gets wrapped in `<user-instructions>` XML tags and duplicated at both the very beginning and end of the copied context, enabling users to include their specific questions or instructions directly within the context they're sharing with the LLM.

## Data Persistence with SwiftData

SwiftData manages all persistent state from the initial implementation, with no temporary local storage solutions. The data model maintains a minimal structure consisting of Workspace and Preference entities. Workspace entities store security-scoped bookmarks for opened directories along with any workspace-specific settings, while Preference entities manage global application settings.

Recent folders persist across launches with their security-scoped bookmarks ensuring continued filesystem access. Per-workspace settings include selection states, custom ignore patterns, and any workspace-specific preference overrides. While certain options can be toggled temporarily in the dropdown menu (like disabling .gitignore respect), users can modify the defaults through application settings. For instance, if someone knows they always want to include gitignored files, they can toggle a setting to change the default behavior, though they can still override it per-workspace through the dropdown.

## Keyboard Shortcuts and Navigation

The application implements standard macOS keyboard shortcuts with specific modifications for this utility's workflow. Command-O opens the folder picker dialog, Command-F activates the filename filter, Command-B toggles the file tree block in the output, Command-Shift-C copies the XML output to clipboard (using Shift to differentiate from standard copy), Command-Backslash toggles the sidebar visibility using the native convention, and spacebar triggers Quick Look preview for highlighted files. Command-T creates new tabs for working with multiple codebases simultaneously.

## Performance and File Handling

The application targets smooth performance with typical software repositories containing up to 30,000 files. File detection relies solely on extensions for language identification rather than content analysis, keeping the scanning process fast and predictable. The app maintains deterministic ordering of files in the output, ensuring consistent results across multiple exports of the same selection.

When the application cannot read a file due to permissions or other issues, it logs the error and excludes the file from processing without blocking the entire operation. This ensures smooth operation even when encountering locked files or permission restrictions within a codebase.

## Testing Strategy

The implementation includes unit tests using the Swift Testing framework for critical business logic components including tokenization accuracy, XML formatting correctness, and ignore rule processing. XCTest should never be used except for UI testing scenarios that Swift Testing doesn't yet support. The test suite verifies that token counts remain accurate and consistent, that XML output maintains proper structure with edge cases like XML-containing files, and that file filtering rules apply correctly across different scenarios.

## Distribution and Privacy

The application will be distributed as a notarized DMG for direct download and maintains full compatibility for eventual App Store submission. As a certified Apple developer, the app will be signed under the appropriate development profile. The application operates strictly offline, never transmitting file contents or metadata to external services. All tokenization and processing occurs locally on-device.

By default, dotenv files and patterns that appear to be API keys are excluded from selection to prevent accidentally sharing sensitive information, though users can explicitly choose to include them if necessary. The sandboxed architecture ensures the app can only access directories explicitly chosen by users through the native file picker.

## Interface Aesthetics

The application ships with a clean, native macOS appearance using San Francisco fonts, system vibrancy effects, and standard sidebar icons. The interface follows Apple's Human Interface Guidelines closely, ensuring the app feels like a natural extension of the macOS ecosystem rather than a ported or non-native application. The focus remains on functionality and clarity rather than custom visual styling, maintaining the professional appearance expected from a developer utility.