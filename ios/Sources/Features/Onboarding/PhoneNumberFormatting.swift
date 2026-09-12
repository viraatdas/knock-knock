import Foundation

enum PhoneNumberFormatting {
    static func digits(_ value: String, maxCount: Int = 15) -> String {
        String(value.filter(\.isNumber).prefix(maxCount))
    }

    static func national(_ value: String, country: CountryCode) -> String {
        let d = digits(value)
        if country.dialCode == "+1" {
            return grouped(d, groups: [3, 3, 4])
        }
        return grouped(d, groups: [3, 3, 3, 3, 3])
    }

    private static func grouped(_ digits: String, groups: [Int]) -> String {
        var chunks: [String] = []
        var start = digits.startIndex
        for size in groups {
            guard start < digits.endIndex else { break }
            let end = digits.index(start, offsetBy: size, limitedBy: digits.endIndex) ?? digits.endIndex
            chunks.append(String(digits[start..<end]))
            start = end
        }
        if start < digits.endIndex {
            chunks.append(String(digits[start..<digits.endIndex]))
        }
        return chunks.joined(separator: " ")
    }
}
