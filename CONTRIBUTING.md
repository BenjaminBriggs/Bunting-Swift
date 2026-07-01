# Contributing to Bunting Swift SDK

## Prerequisites

- Swift 6.0+
- Xcode 16+
- iOS 18 / macOS 15 / watchOS 11 / tvOS 18 / visionOS 2 SDK (for platform targets)

## Build and test gate

All contributions must pass the full test suite before review:

```bash
swift build
swift test
```

No pull request will be merged with build errors or failing tests.

## Doc-comment expectations

Every public type, method, and property requires a `///` doc comment. The bar is set
by the existing comments in `Sources/Bunting/Models/Variant.swift` and `Flag.swift` —
match that depth and style:

- One-line summary on the first line.
- Blank `///` line, then detail paragraphs if the behavior is non-obvious.
- `/// - Parameter name:` / `/// - Returns:` / `/// - Throws:` as appropriate.
- A `/// ## Example` code block for any API that has a non-trivial call site.
- No doc comment on properties whose names are entirely self-explanatory
  (e.g., an internal helper with 5 lines of context). When in doubt, add one.

Run the DocC build locally to confirm your comments render correctly (see below).

## Generating DocC documentation

```bash
swift package generate-documentation --target Bunting
```

The output is an `.doccarchive` in `.build/plugins/Swift-DocC/outputs/`. Open it with
Xcode's **Product → Build Documentation** workflow, or serve it with:

```bash
swift package --disable-sandbox preview-documentation --target Bunting
```

For details on the DocC article and tutorial format used in
`Sources/Bunting/Bunting.docc/`, see the
[DocC documentation](https://www.swift.org/documentation/docc/).

## Adding a new public API

1. Add the implementation in the appropriate file under `Sources/Bunting/`.
2. Write `///` doc comments (see above).
3. Add unit tests in `Tests/BuntingTests/`.
4. Run `swift build && swift test`.
5. If the API is user-facing, update `README.md` and the relevant DocC article.

## Plugins

The SDK ships two SPM plugins. Before modifying them, read
[Plugins reference](docs/plugins.md) for an overview of each plugin's purpose, inputs, and
expected outputs.

Plugin executables live in:
- `Sources/bunting-cli/` — used by `FetchConfigPlugin`
- `Sources/bunting-codegen/` — used by `BuntingCodegenPlugin`

Test plugin changes by running the plugin against the example app:

```bash
swift package plugin fetch-config
swift build
```

## Code style

- Swift 6 strict concurrency (`@Sendable`, `@MainActor`, actor isolation) throughout.
- `bool == false` rather than `!bool`.
- Use `os.Logger` (via `BuntingLog`) rather than `print`.
- No force-unwraps in production paths; use `guard`/`if let`/`try?` with graceful fallbacks.
- Match the surrounding file's comment density and naming conventions.
