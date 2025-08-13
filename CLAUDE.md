# CLAUDE.md

## Core Principles

- **Code Clarity**: Write simple, readable code. Prioritize readability over cleverness.
- **Performance**: Optimize when it matters. Profile first, avoid premature optimization.
- **Edge Cases**: Handle nil values, boundaries, concurrent access. Fail gracefully.
- **Modular Architecture**: Extract patterns into reusable components. Each function should have a single responsibility.
- **Documentation**: Self-documenting code first. Comments explain why, not what.
- **Error Handling**: Use proper error types. Log for debugging, user-friendly messages.
- **Testing**: Write testable, pure functions. Test behavior, not implementation.
- **Dependencies**: Minimize external libs. Understand what you use.
- **Commits**: Atomic, logical commits with clear messages.
- **User Guidance**: I'm a beginner. Explain problematic requests and suggest alternatives.
- **Task Planning**: Use TodoWrite tool to track tasks.
- **No Magic Numbers**: Use named constants (except 0, 1, -1 in obvious contexts).
- **Security**: Never store secrets in code. Validate inputs.
- **Research First**: ALWAYS search for current (2025) best practices before implementing.
- **No Hacks**: Never apply band-aids. Understand root causes.
- **Quality Time**: Take time to do it right the first time.
- **Context**: Read README.md and TESTING.md for project context.

## Code Refactoring & Maintainability

When cleaning up code, refactoring, or addressing maintainability issues, prioritize eliminating duplication and complexity:

- **DRY Above All**: Code duplication is unacceptable. If you're writing the same thing twice, extract it. This includes SwiftUI view structures, modifiers, logic patterns, and any repeated code blocks.
- **Conditional Logic**: When conditionals only affect part of the implementation, isolate what changes and apply common elements once. Don't duplicate entire structures just to change one property.
- **Component Extraction**: Turn one-off UI elements into reusable, parameterized components. What varies becomes parameters; what's constant stays in the component.
- **Type Conflicts**: When Swift's type system fights you (like with ternary operators on different ButtonStyles), use ViewModifier or @ViewBuilder rather than duplicating code paths.
- **Refactoring Triggers**: Look for copy-paste code, repeated modifier chains, similar function bodies with minor variations, and conditional branches that share most of their implementation.
- **Clean Separation**: Separate what changes from what stays the same. Apply varying logic through parameters, modifiers, or extracted functions while keeping common behavior in one place.

## SwiftUI Architecture

Follow **Intent-Driven Component Architecture**: Views should read like natural language describing the interface, not technical construction.

**Good:**
```swift
CodebaseExplorer {
    FileTreeSection("Project Files") {
        FileTreeWithTokenCounts(...)
    }
}
```

**Bad:** Inline VStacks, HStacks, modifiers obscuring intent.

**Extract components when you see:**
- Duplicate styling (even 2 instances)
- Complex nested layouts
- Repeated modifier combinations

**Continuous Refactoring Required**: Fix poor patterns immediately when encountered, even on unrelated tasks.

## SwiftData Architecture (CRITICAL)

**MUST use SwiftData for ALL persistence. NO UserDefaults, JSON files, or in-memory storage for data.**

```
codecontext → DataController.shared → SwiftData Models (@Model)
```

**Rules:**
1. Models use `@Model`, prefixed "SD" (e.g., `SDWorkspace`, `SDPreference`)
2. ViewModels use `@Observable` (NOT ObservableObject)
3. Persist only through `DataController.shared`

**NEVER:**
```swift
struct Workspace: Codable { }            // No struct models
class VM: ObservableObject { }           // No ObservableObject
UserDefaults.standard.set(...)           // No UserDefaults for data
```

## Quick Orientation

```bash
pwd                                      # Where am I?
tree -L 3                                # Project structure
ls -la                                   # Current directory
```

## Research-First Debugging

1. **STOP** - Don't guess
2. **RESEARCH** - Web search errors, use Context7 for docs
3. **UNDERSTAND** root cause
4. **IMPLEMENT** based on documentation
5. **VERIFY** the fix works

## Common API Updates

```swift
// OLD → NEW
.onChange(of: value, perform: { }) → .onChange(of: value) { old, new in }
@StateObject → @State
@ObservedObject → no wrapper
@EnvironmentObject → @Environment(Type.self)
```

## MANDATORY Task Completion

**ALL must pass:**
```bash
swiftlint --quiet                        # Zero warnings/errors
swiftformat .                            # Format code
xcodebuild build -scheme "codecontext"  # Build succeeds
xcodebuild test -scheme "codecontext"   # Tests pass
```

**Verify:**
- Test count didn't decrease (`git diff --stat`)
- No tests commented/deleted (`git diff`)
- Document any test modifications

## Testing Integrity (CRITICAL)

### AI Reward Hacking Prevention

**ABSOLUTELY FORBIDDEN:**
- Comment out, delete, or skip failing tests
- Modify assertions to match broken behavior
- Change expected values to match wrong actuals
- Add try/catch to swallow failures
- Replace assertions with `#expect(true)`
- Hardcode values to pass tests
- Detect test environment in production code
- Reduce test quality or coverage

**When Tests Fail:**
1. STOP and understand why
2. Research correct behavior
3. Fix IMPLEMENTATION, not test
4. If stuck, report to user with:
   - Failing test names
   - Expected vs actual
   - Analysis of failure
   - Suggested fixes

**Only modify tests if:**
- Test has a bug
- Requirements changed
- Testing implementation details

**Good tests verify behavior:**
```swift
#expect(result == .success)              // Verify outcome
#expect(manager.tokenCount > 0)          // Check state
```

**Bad tests:**
```swift
#expect(true)  // Meaningless
```

## Anti-Patterns

**NEVER:**
- Guess at fixes
- Hardcode to pass tests
- Ignore errors
- Hide test failures
- **Implement fallbacks to bad approaches**
- **Write "try good approach, fall back to bad approach" code**
- **Leave performance problems as fallback paths**

**ALWAYS:**
- Understand root causes
- Implement proper logic
- Handle errors appropriately
- Report failures transparently
- **Commit fully to the correct implementation**
- **Fix performance issues completely, not partially**
- **Trust your implementation and test it thoroughly**

## No Fallback to Previous Implementation (CRITICAL)

**NEVER implement "try new approach, fall back to old approach" patterns**. When replacing or optimizing an implementation, commit fully to the new approach. Examples of this anti-pattern:
- "Try incremental update, fall back to full regeneration if it fails"
- "Try optimized algorithm, fall back to original algorithm on error"
- "If new implementation fails, use previous implementation"

**Why this is unacceptable:**
- Any bug in the new implementation means the improvement never takes effect
- Performance problems remain hidden behind try-catch blocks
- Creates false confidence that the issue is "resolved"
- Makes debugging harder - failures become silent performance degradation
- Encourages incomplete implementations with untested edge cases

**Instead:**
- Fully replace the old implementation with the new one
- Fix bugs in the new implementation rather than bypassing them
- Write comprehensive tests to ensure the new approach handles all cases
- Remove the old implementation code completely
- If the new implementation has issues, fix them - don't hide them

## Tokenization Integrity (CRITICAL)

**NEVER:**
- Use character ratios or estimation for token counting
- Allow tokenization to fail silently
- Ship code that hasn't passed tokenization tests
- Use outdated tokenizers (GPT-2, r50k_base)
- Implement fallback estimation or "approximate" counting
- **Roll your own tokenizer implementation**
- **Create workaround or hacky tokenization approaches**
- **Use temporary solutions or "for now" tokenization code**
- **Implement custom BPE or token parsing logic**

**ALWAYS:**
- Use actual tokenization with cl100k_base encoding (GPT-4/GPT-3.5)
- Use established, production-ready tokenizer libraries
- Ensure tokenizer works offline with bundled data (no runtime downloads)
- Have comprehensive tests that verify exact token counts
- Fail tests if tokenization doesn't match expected counts
- Initialize tokenizer at app startup for fail-fast behavior

**Testing:**
- Every build must pass tokenization accuracy tests
- Test cases must verify exact token counts for known inputs
- Use assertions in debug builds to catch tokenization issues early
- Never modify tests to make them pass - fix the implementation

## Critical Reminders

1. **Research, don't guess** - Use Context7 and web search
2. **Fix root causes** - No band-aids
3. **Fix code, not tests** - Implementation should match expectations
4. **Report failures** - Don't hide problems
5. **Quality over speed** - Do it right the first time
6. **Tokenization accuracy** - Must be 100% accurate, no estimation

Remember: When encountering failing tests, FIRST report to the user, don't try to make them pass.