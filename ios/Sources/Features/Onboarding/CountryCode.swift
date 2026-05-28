import Foundation

struct CountryCode: Hashable, Identifiable {
    let id: String          // ISO code
    let name: String
    let dialCode: String
    let flag: String

    static let us = CountryCode(id: "US", name: "United States", dialCode: "+1", flag: "🇺🇸")

    static let all: [CountryCode] = [
        CountryCode(id: "US", name: "United States", dialCode: "+1", flag: "🇺🇸"),
        CountryCode(id: "CA", name: "Canada", dialCode: "+1", flag: "🇨🇦"),
        CountryCode(id: "GB", name: "United Kingdom", dialCode: "+44", flag: "🇬🇧"),
        CountryCode(id: "IN", name: "India", dialCode: "+91", flag: "🇮🇳"),
        CountryCode(id: "AU", name: "Australia", dialCode: "+61", flag: "🇦🇺"),
        CountryCode(id: "DE", name: "Germany", dialCode: "+49", flag: "🇩🇪"),
        CountryCode(id: "FR", name: "France", dialCode: "+33", flag: "🇫🇷"),
        CountryCode(id: "ES", name: "Spain", dialCode: "+34", flag: "🇪🇸"),
        CountryCode(id: "IT", name: "Italy", dialCode: "+39", flag: "🇮🇹"),
        CountryCode(id: "BR", name: "Brazil", dialCode: "+55", flag: "🇧🇷"),
        CountryCode(id: "MX", name: "Mexico", dialCode: "+52", flag: "🇲🇽"),
        CountryCode(id: "JP", name: "Japan", dialCode: "+81", flag: "🇯🇵"),
        CountryCode(id: "CN", name: "China", dialCode: "+86", flag: "🇨🇳"),
        CountryCode(id: "SG", name: "Singapore", dialCode: "+65", flag: "🇸🇬"),
        CountryCode(id: "AE", name: "United Arab Emirates", dialCode: "+971", flag: "🇦🇪"),
        CountryCode(id: "NG", name: "Nigeria", dialCode: "+234", flag: "🇳🇬"),
        CountryCode(id: "ZA", name: "South Africa", dialCode: "+27", flag: "🇿🇦")
    ]
}
