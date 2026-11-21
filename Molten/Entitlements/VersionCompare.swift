//
//  VersionCompare.swift
//  Molten
//
//  Molten 2.0 — M2. Component-by-component integer version comparison.
//  Never compare version strings lexicographically.
//

import Foundation

enum VersionCompare {
    /// Parses dot-separated non-negative integer components.
    /// Returns nil for empty or malformed strings (any non-numeric component).
    static func components(_ version: String) -> [Int]? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var result: [Int] = []
        for part in trimmed.split(separator: ".", omittingEmptySubsequences: false) {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let n = Int(part) else { return nil }
            result.append(n)
        }
        return result
    }

    /// Compares two versions component by component, zero-padding the shorter.
    /// Returns nil when either side is malformed.
    static func compare(_ a: String, _ b: String) -> ComparisonResult? {
        guard let ca = components(a), let cb = components(b) else { return nil }
        let count = max(ca.count, cb.count)
        for i in 0..<count {
            let x = i < ca.count ? ca[i] : 0
            let y = i < cb.count ? cb[i] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }

    /// True when `version` is strictly before `cutoff`; nil when malformed.
    static func isBefore(_ version: String, cutoff: String) -> Bool? {
        compare(version, cutoff).map { $0 == .orderedAscending }
    }
}
