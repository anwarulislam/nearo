//
//  ContactBook.swift
//  Nearo
//
//  The phone's contacts, as vCards from KDE Connect's contacts plugin, for
//  showing names and photos instead of bare numbers.
//

import Foundation

nonisolated public struct Contact: Sendable, Equatable, Identifiable {
    public var id: String
    public let name: String
    public let numbers: [String]
    public let emails: [String]
    /// JPEG or PNG, when the contact has a photo.
    public let photo: Data?

    public init(id: String = UUID().uuidString, name: String, numbers: [String], emails: [String] = [], photo: Data? = nil) {
        self.id = id
        self.name = name
        self.numbers = numbers
        self.emails = emails
        self.photo = photo
    }
}

nonisolated public struct ContactBook: Sendable, Equatable {
    public private(set) var contacts: [String: Contact] = [:]
    /// Number keys (see `key(for:)`) to contact IDs.
    private var byNumber: [String: String] = [:]

    public init(_ contacts: [String: Contact] = [:]) {
        for (id, contact) in contacts { set(contact, for: id) }
    }

    public var isEmpty: Bool { contacts.isEmpty }
    public var count: Int { contacts.count }

    public var allContacts: [Contact] {
        contacts.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public mutating func set(_ contact: Contact?, for id: String) {
        if let old = contacts[id] {
            for number in old.numbers {
                if let key = Self.key(for: number), byNumber[key] == id { byNumber[key] = nil }
            }
        }
        var updated = contact
        if var c = updated {
            c.id = id
            updated = c
        }
        contacts[id] = updated
        for number in updated?.numbers ?? [] {
            if let key = Self.key(for: number) { byNumber[key] = id }
        }
    }

    /// People and numbers matching `query` by name or number, for picking a
    /// recipient. One entry per number.
    public func search(_ query: String, limit: Int = 8) -> [(name: String, number: String)] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        let digits = query.filter(\.isWholeNumber)
        var results: [(name: String, number: String)] = []
        for contact in allContacts {
            let nameMatches = contact.name.localizedCaseInsensitiveContains(query)
            for number in contact.numbers
            where nameMatches || (digits.count >= 3 && number.filter(\.isWholeNumber).contains(digits)) || number.localizedCaseInsensitiveContains(query) {
                results.append((contact.name, number))
                if results.count == limit { return results }
            }
        }
        return results
    }

    /// Search contacts by name, number, or email. Returns all matching contacts.
    public func searchContacts(_ query: String) -> [Contact] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allContacts }
        let digits = trimmed.filter(\.isWholeNumber)
        return allContacts.filter { contact in
            if contact.name.localizedCaseInsensitiveContains(trimmed) { return true }
            if digits.count >= 3 && contact.numbers.contains(where: { $0.filter(\.isWholeNumber).contains(digits) }) {
                return true
            }
            if contact.numbers.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) }) {
                return true
            }
            if contact.emails.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) }) {
                return true
            }
            return false
        }
    }

    /// The contact with this phone number, however it's written.
    public func contact(for number: String) -> Contact? {
        guard let key = Self.key(for: number), let id = byNumber[key] else { return nil }
        return contacts[id]
    }

    /// Numbers match on their last ten digits, so "+91 98765 43210",
    /// "098765 43210" and "9876543210" are the same person. Short codes (banks,
    /// carriers) match exactly. Sender names such as "AX-HDFCBK" have no key.
    public static func key(for number: String) -> String? {
        let digits = number.filter(\.isWholeNumber)
        guard !digits.isEmpty, digits.count * 2 >= number.filter({ !$0.isWhitespace }).count else { return nil }
        return digits.count > 10 ? String(digits.suffix(10)) : digits
    }
}

// MARK: - vCard

nonisolated enum VCard {
    /// Reads the parts Nearo shows. Android writes vCard 2.1 or 3.0, folding
    /// long lines (a photo is thousands of characters) onto lines that start
    /// with a space.
    static func parse(_ text: String) -> Contact? {
        var lines: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else if !raw.isEmpty {
                lines.append(raw)
            }
        }

        var formattedName: String?
        var structuredName: String?
        var organization: String?
        var numbers: [String] = []
        var emails: [String] = []
        var photo: Data?

        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let head = line[..<colon]
            let value = String(line[line.index(after: colon)...])
            let parts = head.split(separator: ";")
            guard let rawProperty = parts.first?.split(separator: ".").last?.uppercased() else { continue }
            let parameters = parts.dropFirst().map { $0.uppercased() }
            let isQuotedPrintable = parameters.contains { $0 == "QUOTED-PRINTABLE" || $0.hasSuffix("=QUOTED-PRINTABLE") }
            let decoded = isQuotedPrintable ? quotedPrintable(value) : unescape(value)

            switch rawProperty {
            case "FN":
                formattedName = decoded
            case "N":
                // Family;Given;Middle;Prefix;Suffix
                let fields = decoded.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
                let given = fields.count > 1 ? fields[1] : ""
                let family = fields.first ?? ""
                structuredName = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
            case "ORG":
                let org = decoded.split(separator: ";").first.map(String.init) ?? decoded
                organization = org.trimmingCharacters(in: .whitespaces)
            case "TEL":
                let number = decoded.hasPrefix("tel:") ? String(decoded.dropFirst(4)) : decoded
                let trimmed = number.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !numbers.contains(trimmed) { numbers.append(trimmed) }
            case "EMAIL":
                let email = decoded.hasPrefix("mailto:") ? String(decoded.dropFirst(7)) : decoded
                let trimmed = email.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !emails.contains(trimmed) { emails.append(trimmed) }
            case "PHOTO":
                photo = photoData(value)
            default:
                continue
            }
        }

        guard let name = [formattedName, structuredName, organization].compactMap({ $0?.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) else {
            return nil
        }
        return Contact(name: name, numbers: numbers, emails: emails, photo: photo)
    }

    /// Base64 (vCard 2.1 and 3.0) or a data: URI (4.0).
    private static func photoData(_ value: String) -> Data? {
        var base64 = value
        if value.hasPrefix("data:"), let comma = value.firstIndex(of: ",") {
            base64 = String(value[value.index(after: comma)...])
        }
        base64.removeAll { $0.isWhitespace }
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters), !data.isEmpty else { return nil }
        return data
    }

    private static func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// vCard 2.1 writes non-ASCII names as quoted-printable UTF-8.
    private static func quotedPrintable(_ value: String) -> String {
        var bytes: [UInt8] = []
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            if character == "=", let end = value.index(index, offsetBy: 3, limitedBy: value.endIndex),
               let byte = UInt8(value[value.index(after: index)..<end], radix: 16) {
                bytes.append(byte)
                index = end
            } else {
                bytes.append(contentsOf: Array(String(character).utf8))
                index = value.index(after: index)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
