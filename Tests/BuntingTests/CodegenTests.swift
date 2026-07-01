import Foundation
import Testing

/// Runs the built `bunting-codegen` executable as a subprocess against fixture
/// seed JSONs and asserts on the generated Swift source. Golden assertions are
/// targeted `#expect(...contains...)` checks on meaningful generated lines
/// rather than byte-exact output, so cosmetic formatting changes don't break
/// these tests.
struct CodegenTests {

    private struct GeneratedOutput {
        let result: SubprocessTestSupport.ProcessResult
        let swiftSource: String
    }

    /// Writes `seedJSON` to a temp file, runs `bunting-codegen <seed> <output>`,
    /// and returns the process result plus the generated Swift source (empty
    /// string if the output file wasn't produced).
    private func generate(seedJSON: String) throws -> GeneratedOutput {
        try SubprocessTestSupport.withTemporaryDirectory { directory in
            let configURL = directory.appendingPathComponent("BuntingConfig.json")
            let outputURL = directory.appendingPathComponent("BuntingGenerated.swift")
            try seedJSON.write(to: configURL, atomically: true, encoding: .utf8)

            let executable = try SubprocessTestSupport.executableURL(named: "bunting-codegen")
            let result = try SubprocessTestSupport.run(
                executable, arguments: [configURL.path, outputURL.path])

            let swiftSource = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
            return GeneratedOutput(result: result, swiftSource: swiftSource)
        }
    }

    // MARK: - Whole-number double default (bug fix)

    /// A `double` flag whose seed default is a JSON integer (`2`, not `2.0`)
    /// must still generate a `Double` accessor with a Double-literal default.
    /// Before the fix, the int-before-double decode ordering in `FlagValue`
    /// caused codegen's `case .double` pattern match to miss entirely, so the
    /// emitted default silently fell back to the hardcoded `0.0` — losing the
    /// seed's actual default value, not just its formatting.
    @Test
    func doubleFlagWithWholeNumberSeedGetsDoubleLiteralDefault() throws {
        // The seed value must be nonzero: a seed of `0` can't distinguish the
        // fixed behavior (`0.0`, the correct coercion of the seed) from the
        // pre-fix bug (`0.0`, the hardcoded fallback masking a lost default) —
        // both would print identically. `2` makes the two cases observably
        // different (`2.0` vs. the buggy `0.0`).
        let seed = """
            {
              "flags": {
                "price_multiplier": {
                  "type": "double",
                  "development": {"default": 2},
                  "beta": {"default": 2},
                  "production": {"default": 2}
                }
              }
            }
            """
        let output = try generate(seedJSON: seed)
        #expect(output.result.exitCode == 0)
        #expect(output.swiftSource.contains("var priceMultiplier: Double {"))
        #expect(
            output.swiftSource.contains(
                "bunting.double(\"price_multiplier\", default: 2.0)"))
        // Must not regress to the pre-fix fallback of silently zeroing the default.
        #expect(
            output.swiftSource.contains(
                "bunting.double(\"price_multiplier\", default: 0.0)") == false)
    }

    // MARK: - One flag of every type

    /// A seed with one root-level flag per supported type asserts each generates
    /// the right Swift type and default-value call.
    private static let allTypesSeed = """
        {
          "flags": {
            "is_enabled": {
              "type": "bool",
              "development": {"default": true},
              "beta": {"default": true},
              "production": {"default": false}
            },
            "welcome_message": {
              "type": "string",
              "development": {"default": "hello"},
              "beta": {"default": "hello"},
              "production": {"default": "hello"}
            },
            "max_retries": {
              "type": "int",
              "development": {"default": 3},
              "beta": {"default": 3},
              "production": {"default": 3}
            },
            "price_multiplier": {
              "type": "double",
              "development": {"default": 1.5},
              "beta": {"default": 1.5},
              "production": {"default": 1.5}
            },
            "release_date": {
              "type": "date",
              "development": {"default": "2026-01-01T00:00:00Z"},
              "beta": {"default": "2026-01-01T00:00:00Z"},
              "production": {"default": "2026-01-01T00:00:00Z"}
            },
            "layout_config": {
              "type": "json",
              "development": {"default": "{}"},
              "beta": {"default": "{}"},
              "production": {"default": "{}"}
            }
          }
        }
        """

    @Test
    func generatesEveryFlagType() throws {
        let output = try generate(seedJSON: Self.allTypesSeed)
        #expect(output.result.exitCode == 0)

        #expect(output.swiftSource.contains("var isEnabled: Bool {"))
        #expect(output.swiftSource.contains("bunting.bool(\"is_enabled\", default: true)"))

        #expect(output.swiftSource.contains("var welcomeMessage: String {"))
        #expect(
            output.swiftSource.contains(
                "bunting.string(\"welcome_message\", default: \"hello\")"))

        #expect(output.swiftSource.contains("var maxRetries: Int {"))
        #expect(output.swiftSource.contains("bunting.int(\"max_retries\", default: 3)"))

        #expect(output.swiftSource.contains("var priceMultiplier: Double {"))
        #expect(
            output.swiftSource.contains(
                "bunting.double(\"price_multiplier\", default: 1.5)"))

        #expect(output.swiftSource.contains("var releaseDate: Date {"))
        #expect(output.swiftSource.contains("bunting.date(\"release_date\", default: Date())"))

        #expect(output.swiftSource.contains("var layoutConfig: JSONData? {"))
        #expect(output.swiftSource.contains("bunting.jsonData(\"layout_config\")"))
    }

    // MARK: - Namespacing + snake_case -> camelCase

    /// `store/use_new_paywall_design` must generate a nested `store` namespace
    /// with a camelCased `useNewPaywallDesign` accessor (the exact example used
    /// in the project's own docs).
    @Test
    func namespacedKeyGeneratesNestedCamelCaseAccessor() throws {
        let seed = """
            {
              "flags": {
                "store/use_new_paywall_design": {
                  "type": "bool",
                  "development": {"default": false},
                  "beta": {"default": false},
                  "production": {"default": false}
                }
              }
            }
            """
        let output = try generate(seedJSON: seed)
        #expect(output.result.exitCode == 0)

        // Note: the namespace type name is lowercase ("storeNamespace") today —
        // `camelCase(namespace.capitalized)` lowercases the first character
        // again, so "Store" -> "store". Pinning current behavior, not asserting
        // it's ideal.
        #expect(output.swiftSource.contains("var store: storeNamespace {"))
        #expect(output.swiftSource.contains("struct storeNamespace {"))
        #expect(output.swiftSource.contains("var useNewPaywallDesign: Bool {"))
        #expect(
            output.swiftSource.contains(
                "bunting.bool(\"store/use_new_paywall_design\", default: false)"))
    }

    // MARK: - deprecated flag handling

    /// `deprecated: true` flags currently generate an `@available(*, deprecated, ...)`
    /// annotation directly above the accessor, pinning today's behavior.
    @Test
    func deprecatedFlagGetsAvailabilityAnnotation() throws {
        let seed = """
            {
              "flags": {
                "archived_flag": {
                  "type": "bool",
                  "deprecated": true,
                  "development": {"default": false},
                  "beta": {"default": false},
                  "production": {"default": false}
                }
              }
            }
            """
        let output = try generate(seedJSON: seed)
        #expect(output.result.exitCode == 0)
        #expect(
            output.swiftSource.contains(
                "@available(*, deprecated, message: \"Flag archived\")\n    var archivedFlag: Bool {"
            ))
    }

    /// A flag without `deprecated` (or with it explicitly `false`) must not get
    /// the availability annotation.
    @Test
    func nonDeprecatedFlagHasNoAvailabilityAnnotation() throws {
        let seed = """
            {
              "flags": {
                "active_flag": {
                  "type": "bool",
                  "development": {"default": false},
                  "beta": {"default": false},
                  "production": {"default": false}
                }
              }
            }
            """
        let output = try generate(seedJSON: seed)
        #expect(output.result.exitCode == 0)
        #expect(output.swiftSource.contains("@available") == false)
    }

    // MARK: - Legacy `defaultValue` key

    /// Codegen accepts both `default` and legacy `defaultValue` keys for an
    /// environment's default value (EnvironmentConfig, main.swift:16-54 area).
    @Test
    func legacyDefaultValueKeyIsAccepted() throws {
        let seed = """
            {
              "flags": {
                "legacy_default_flag": {
                  "type": "bool",
                  "development": {"defaultValue": true},
                  "beta": {"defaultValue": true},
                  "production": {"defaultValue": true}
                }
              }
            }
            """
        let output = try generate(seedJSON: seed)
        #expect(output.result.exitCode == 0)
        #expect(output.swiftSource.contains("var legacyDefaultFlag: Bool {"))
        #expect(
            output.swiftSource.contains(
                "bunting.bool(\"legacy_default_flag\", default: true)"))
    }
}
