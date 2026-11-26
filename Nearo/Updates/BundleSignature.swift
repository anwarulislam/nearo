//
//  BundleSignature.swift
//  Nearo
//
//  Proves a downloaded Nearo is ours before it replaces the running one.
//
//  A stable update must have an intact signature from the same certificate
//  as the installed app, including the seals on the embedded extensions.
//

import Foundation
import Security

nonisolated enum BundleSignature {
    static func isTrusted(_ bundleURL: URL, installedAt installedURL: URL) -> Bool {
        guard let expected = certificate(at: installedURL),
              let candidate = staticCode(at: bundleURL) else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(candidate, flags, nil) == errSecSuccess
            && certificate(of: candidate) == expected
    }

    static var canVerifyUpdates: Bool {
        certificate(at: Bundle.main.bundleURL) != nil
    }

    private static func staticCode(at url: URL) -> SecStaticCode? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess else { return nil }
        return code
    }

    private static func certificate(at url: URL) -> Data? {
        staticCode(at: url).flatMap(certificate(of:))
    }

    /// The leaf certificate's bytes.
    private static func certificate(of code: SecStaticCode) -> Data? {
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else { return nil }
        return SecCertificateCopyData(leaf) as Data
    }
}
