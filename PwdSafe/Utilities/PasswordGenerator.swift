import Foundation

struct PasswordGenerator: Sendable {

    struct Options: Sendable {
        var length: Int = 16
        var includeUppercase: Bool = true
        var includeLowercase: Bool = true
        var includeDigits: Bool = true
        var includeSymbols: Bool = true

        var isValid: Bool {
            length >= 4 && length <= 64
                && (includeUppercase || includeLowercase || includeDigits || includeSymbols)
        }
    }

    enum Strength: String, Sendable, Comparable {
        case veryWeak = "非常弱"
        case weak = "弱"
        case fair = "一般"
        case strong = "强"
        case veryStrong = "非常强"

        private var sortOrder: Int {
            switch self {
            case .veryWeak: return 0
            case .weak: return 1
            case .fair: return 2
            case .strong: return 3
            case .veryStrong: return 4
            }
        }

        static func < (lhs: Strength, rhs: Strength) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }
    }

    private static let uppercaseLetters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    private static let lowercaseLetters = "abcdefghijklmnopqrstuvwxyz"
    private static let digits = "0123456789"
    private static let symbols = "!@#$%^&*()-_=+[]{}|;:,.<>?/~`"

    static func generate(options: Options = Options()) -> String {
        var charset = ""
        if options.includeUppercase { charset += uppercaseLetters }
        if options.includeLowercase { charset += lowercaseLetters }
        if options.includeDigits { charset += digits }
        if options.includeSymbols { charset += symbols }

        guard !charset.isEmpty, options.length > 0 else { return "" }

        var password = ""
        let charsetArray = Array(charset)
        for _ in 0..<options.length {
            let randomIndex = Int.random(in: 0..<charsetArray.count)
            password.append(charsetArray[randomIndex])
        }

        if options.includeUppercase && !password.contains(where: { uppercaseLetters.contains($0) }) {
            password = ensureCharacter(from: uppercaseLetters, in: password, charsetArray: charsetArray)
        }
        if options.includeLowercase && !password.contains(where: { lowercaseLetters.contains($0) }) {
            password = ensureCharacter(from: lowercaseLetters, in: password, charsetArray: charsetArray)
        }
        if options.includeDigits && !password.contains(where: { digits.contains($0) }) {
            password = ensureCharacter(from: digits, in: password, charsetArray: charsetArray)
        }
        if options.includeSymbols && !password.contains(where: { symbols.contains($0) }) {
            password = ensureCharacter(from: symbols, in: password, charsetArray: charsetArray)
        }

        return password
    }

    private static func ensureCharacter(from set: String, in password: String, charsetArray: [Character]) -> String {
        var result = Array(password)
        guard let randomChar = set.randomElement() else { return password }
        let randomPos = Int.random(in: 0..<result.count)
        result[randomPos] = randomChar
        return String(result)
    }

    static func strength(of password: String) -> Strength {
        let length = password.count
        var poolSize = 0

        if password.contains(where: { uppercaseLetters.contains($0) }) { poolSize += 26 }
        if password.contains(where: { lowercaseLetters.contains($0) }) { poolSize += 26 }
        if password.contains(where: { digits.contains($0) }) { poolSize += 10 }
        if password.contains(where: { symbols.contains($0) }) { poolSize += 32 }

        guard poolSize > 0, length > 0 else { return .veryWeak }

        let entropy = Double(length) * log2(Double(poolSize))

        switch entropy {
        case ..<28:  return .veryWeak
        case 28..<36: return .weak
        case 36..<60: return .fair
        case 60..<80: return .strong
        default:      return .veryStrong
        }
    }

    }

