import Foundation

/// Stable public app versions. Numeric comparison avoids 1.10 sorting below 1.9.
public struct ReleaseVersion:Equatable,Comparable,CustomStringConvertible,Sendable {
    private let components:[UInt64]
    public var description:String {components.map(String.init).joined(separator:".")}

    public init?(_ text:String) {
        var text=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard text.utf8.count<=64 else{return nil}
        if text.hasPrefix("v") {text.removeFirst()}
        let pieces=text.split(separator:".",omittingEmptySubsequences:false)
        guard pieces.count==3 else{return nil}
        var values:[UInt64]=[]
        for piece in pieces {
            guard !piece.isEmpty,piece.utf8.allSatisfy({(48...57).contains($0)}),let value=UInt64(piece) else{return nil}
            values.append(value)
        }
        components=values
    }
    public static func <(lhs:Self,rhs:Self)->Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

public enum ReleaseMetadataSource:CaseIterable,Sendable {case website,github}
public enum ReleaseMetadataError:Error {case invalid,notStable}

public enum ReleaseMetadata {
    public static func version(from data:Data,source:ReleaseMetadataSource)throws->ReleaseVersion {
        guard data.count<=262_144 else{throw ReleaseMetadataError.invalid}
        let text:String
        switch source {
        case .website:
            struct Manifest:Decodable {let version:String}
            text=try JSONDecoder().decode(Manifest.self,from:data).version
        case .github:
            struct Release:Decodable {let tag_name:String;let draft:Bool;let prerelease:Bool}
            let release=try JSONDecoder().decode(Release.self,from:data)
            guard !release.draft,!release.prerelease else{throw ReleaseMetadataError.notStable}
            text=release.tag_name
        }
        guard let value=ReleaseVersion(text) else{throw ReleaseMetadataError.invalid}
        return value
    }
}
