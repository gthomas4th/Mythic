import Foundation

public enum WineRegistryValue {
    /// Extract a unique named scalar value, not the whole `reg query` output line.
    public static func parse(_ output: String, name: String, type: String) -> String? {
        guard !name.isEmpty, !type.isEmpty else { return nil }
        let values = output.split(whereSeparator: \.isNewline).compactMap { raw -> String? in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.lowercased().hasPrefix(name.lowercased()) else { return nil }
            let rest = line.dropFirst(name.count)
            guard rest.first?.isWhitespace == true else { return nil }
            let fields = rest.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard fields.first == Substring(type) else { return nil }
            return fields.count == 2 ? fields[1].trimmingCharacters(in: .whitespaces) : ""
        }
        return values.count == 1 ? values[0] : nil
    }
}
