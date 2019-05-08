//
//  OtpAuthStringParser.swift
//  TwoFaCore
//
//  Created by Janis Kirsteins on 10/03/2019.
//

import Foundation
import Base32

// Spec: https://github.com/google/google-authenticator/wiki/Key-Uri-Format

public class OtpAuthStringParser {
    
    let defaultDigits = OtpDigits.six
    let defaultAlgorithm = OtpAlgorithm.sha1
    
    public enum ParseError : Swift.Error {
        case notAnUrl(String)
        case missingScheme
        case invalidScheme(String)
        case missingType
        case unknownType(String)
        case hotpMissingCounter
        case hotpInvalidCounter
        case totpInvalidPeriod
        case emptyLabel
        case missingSecret
        case invalidSecret(String)
        case invalidDigits(String)
        case mismatchedProviderAndIssuer
        case invalidAlgorithm(String)
    }
    
    public init() {
        
    }
    
    public func parse(label: String, secretStr: String, type: OtpType = .totp(period: nil)) throws -> OtpAuth {
        return OtpAuth(
            type: type,
            label: label,
            secret: try self.decodeSecret(secretStr),
            issuer: nil,
            digits: self.defaultDigits,
            algorithm: self.defaultAlgorithm)
    }
    
    public func parse(_ str: String, label labelOverride: String? = nil) throws -> OtpAuth {
        
        print("Parsing: \(str)")
        
        guard let url = URL(string: str) else {
            throw ParseError.notAnUrl(str)
        }
        
        guard let scheme = url.scheme else {
            throw ParseError.missingScheme
        }
        
        guard scheme.caseInsensitiveCompare("otpauth") == ComparisonResult.orderedSame else {
            throw ParseError.invalidScheme(scheme)
        }
        
        guard let typeStr = url.host else {
            throw ParseError.missingType
        }
        
        let type: OtpType
        
        switch typeStr.lowercased() {
        case "totp":
            if let periodStr = url.valueOf("period") {
                guard let period = Int(periodStr) else {
                    throw ParseError.totpInvalidPeriod
                }
                type = .totp(period: period)
            } else {
                type = .totp(period: nil)
            }
        case "hotp":
            guard let counterStr = url.valueOf("counter") else {
                throw ParseError.hotpMissingCounter
            }
            guard let counter = Int(counterStr) else {
                throw ParseError.hotpInvalidCounter
            }
            type = .hotp(counter: counter)
        default:
            throw ParseError.unknownType(typeStr)
        }
        
        let label: String
        if let labelOverride = labelOverride {
            label = labelOverride
        } else {
            label = String(url.path[url.path.index(after: url.path.startIndex)...])
        }
        
        if label.isEmpty {
            throw ParseError.emptyLabel
        }
        
        let labelParts = label.split(separator: ":")
        let providerBackup: String?
        let finalLabel: String
        if labelParts.count > 1 {
            finalLabel = String(labelParts[1...].joined())
            providerBackup = String(labelParts[0])
            
            if let issuer = url.valueOf("issuer") {
                if providerBackup!.compare(issuer) != .orderedSame {
                    throw ParseError.mismatchedProviderAndIssuer
                }
            }
        } else {
            finalLabel = label
            providerBackup = nil
        }
        
        guard let secretStr = url.valueOf("secret") else {
            throw ParseError.missingSecret
        }
        
        let secret = try self.decodeSecret(secretStr)
        
        let issuer = url.valueOf("issuer") ?? providerBackup
        
        let digits : OtpDigits
        if let digitStr = url.valueOf("digits") {
            guard let digitCandidate = OtpDigits(rawValue: digitStr) else {
                throw ParseError.invalidDigits(digitStr)
            }
            digits = digitCandidate
        } else {
            digits = self.defaultDigits
        }
        
        let algorithm: OtpAlgorithm
        if let algoStr = url.valueOf("algorithm")?.lowercased() {
            guard let parsedAlgorithm = OtpAlgorithm(rawValue: algoStr) else {
                throw ParseError.invalidAlgorithm(algoStr)
            }
            algorithm = parsedAlgorithm
        } else {
            algorithm = self.defaultAlgorithm
        }
        
        return OtpAuth(
            type: type,
            label: finalLabel,
            secret: secret,
            issuer: issuer,
            digits: digits,
            algorithm: algorithm)
    }
    
    public func decodeSecret(_ secretStr: String) throws -> [UInt8] {
        guard let secret = base32Decode(secretStr) else {
            throw ParseError.invalidSecret(secretStr)
        }
        return secret
    }
}
