# GameHubCore

macOS 14+, Swift 6; no external dependencies. Run `swift test` in this directory.
The Xcode application compiles these same sources directly during the first slice.

Supported VDF dialect: Steam text manifests with objects, strings, unquoted tokens,
line comments and standard string escapes. Includes/inheritance/platform directives
are rejected, never executed. Singleton fields reject ambiguous repeated keys.
Reads are capped at 8 MB; nesting at 64; native bundle searches at depth 6 / 20,000 entries.
Unknown layouts produce diagnostics rather than guessed compatibility.
