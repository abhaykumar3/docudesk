import Foundation

/// Types with a natural empty value used when an older file lacks a newer field.
public protocol DefaultInitializable {
    init()
}

extension Array: DefaultInitializable {}
extension String: DefaultInitializable {}
extension Bool: DefaultInitializable {}

/// Decodes a missing key as `Value()` so records written by earlier versions still open.
/// Only use it where `Value()` is the intended default (empty array, empty string, `false`).
@propertyWrapper
public struct Defaulted<Value: Codable & Hashable & Sendable & DefaultInitializable>: Codable, Hashable, Sendable {
    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        wrappedValue = try Value(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}

extension KeyedDecodingContainer {
    public func decode<Value>(_ type: Defaulted<Value>.Type, forKey key: Key) throws -> Defaulted<Value> {
        try decodeIfPresent(type, forKey: key) ?? Defaulted(wrappedValue: Value())
    }

    /// Money fields added after a file was written decode as zero.
    public func decode(_ type: DecimalString.Type, forKey key: Key) throws -> DecimalString {
        try decodeIfPresent(type, forKey: key) ?? DecimalString(wrappedValue: 0)
    }
}
