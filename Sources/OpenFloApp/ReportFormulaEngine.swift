import Foundation

enum ReportFormulaEngine {
    static func referencedColumnNames(in expression: String) -> Set<String> {
        var lexer = FormulaLexer(expression)
        var names = Set<String>()
        while let token = lexer.nextToken() {
            switch token {
            case .cell(let name):
                names.insert(name)
            case .identifier(let name):
                if !FormulaFunction.isFunctionName(name), !FormulaValue.isBooleanLiteral(name) {
                    names.insert(name)
                }
            default:
                break
            }
        }
        return names
    }

    static func evaluate(
        _ expression: String,
        resolver: @escaping (String) -> ReportValue?
    ) -> ReportValue {
        do {
            var parser = FormulaParser(expression: expression, resolver: resolver)
            return try parser.parse().reportValue
        } catch let error as FormulaError {
            return .error(error.message)
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

private enum FormulaError: Error {
    case message(String)

    var message: String {
        switch self {
        case .message(let value):
            return value
        }
    }
}

private enum FormulaToken: Equatable {
    case number(Double)
    case string(String)
    case identifier(String)
    case cell(String)
    case operatorSymbol(String)
    case leftParen
    case rightParen
    case comma
}

private struct FormulaLexer {
    private let characters: [Character]
    private var index = 0

    init(_ expression: String) {
        self.characters = Array(expression)
    }

    mutating func nextToken() -> FormulaToken? {
        skipWhitespace()
        guard index < characters.count else { return nil }
        let character = characters[index]

        if character == "<", let token = readCellReference() {
            return token
        }
        if character == "\"" {
            return readString()
        }
        if character.isNumber || character == "." {
            return readNumber()
        }
        if character.isLetter || character == "_" || character == "$" {
            return readIdentifier()
        }
        if character == "(" {
            index += 1
            return .leftParen
        }
        if character == ")" {
            index += 1
            return .rightParen
        }
        if character == "," {
            index += 1
            return .comma
        }

        let twoCharacterOperator = index + 1 < characters.count
            ? String([characters[index], characters[index + 1]])
            : ""
        if ["<=", ">=", "!=", "&&", "||"].contains(twoCharacterOperator) {
            index += 2
            return .operatorSymbol(twoCharacterOperator)
        }
        if ["+", "-", "*", "/", "%", "<", ">", "=", "!"].contains(String(character)) {
            index += 1
            return .operatorSymbol(String(character))
        }
        index += 1
        return nil
    }

    private mutating func skipWhitespace() {
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }
    }

    private mutating func readCellReference() -> FormulaToken? {
        let start = index
        while index < characters.count, characters[index] != ">" {
            index += 1
        }
        guard index < characters.count else {
            self.index = start
            return nil
        }
        index += 1
        let text = String(characters[start..<index])
        for key in ["column=\"", "column='"] {
            guard let range = text.range(of: key) else { continue }
            let suffix = text[range.upperBound...]
            let terminator: Character = key.hasSuffix("\"") ? "\"" : "'"
            guard let end = suffix.firstIndex(of: terminator) else { continue }
            return .cell(String(suffix[..<end]))
        }
        return nil
    }

    private mutating func readString() -> FormulaToken {
        index += 1
        var output = ""
        while index < characters.count {
            let character = characters[index]
            index += 1
            if character == "\"" {
                break
            }
            if character == "\\", index < characters.count {
                output.append(characters[index])
                index += 1
            } else {
                output.append(character)
            }
        }
        return .string(output)
    }

    private mutating func readNumber() -> FormulaToken {
        let start = index
        var hasExponent = false
        while index < characters.count {
            let character = characters[index]
            if character.isNumber || character == "." {
                index += 1
                continue
            }
            if (character == "e" || character == "E"), !hasExponent {
                hasExponent = true
                index += 1
                if index < characters.count, characters[index] == "+" || characters[index] == "-" {
                    index += 1
                }
                continue
            }
            break
        }
        return .number(Double(String(characters[start..<index])) ?? .nan)
    }

    private mutating func readIdentifier() -> FormulaToken {
        let start = index
        while index < characters.count {
            let character = characters[index]
            guard character.isLetter || character.isNumber || character == "_" || character == "$" else {
                break
            }
            index += 1
        }
        return .identifier(String(characters[start..<index]))
    }
}

private enum FormulaValue: Equatable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case missing

    var reportValue: ReportValue {
        switch self {
        case .number(let value):
            return value.isFinite ? .number(value) : .missing
        case .string(let value):
            return .string(value)
        case .bool(let value):
            return .bool(value)
        case .missing:
            return .missing
        }
    }

    var number: Double? {
        switch self {
        case .number(let value):
            return value
        case .bool(let value):
            return value ? 1 : 0
        case .string(let value):
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case .missing:
            return nil
        }
    }

    var bool: Bool {
        switch self {
        case .bool(let value):
            return value
        case .number(let value):
            return value != 0
        case .string(let value):
            return !value.isEmpty
        case .missing:
            return false
        }
    }

    var string: String {
        switch self {
        case .number(let value):
            return formatReportNumber(value)
        case .string(let value):
            return value
        case .bool(let value):
            return value ? "TRUE" : "FALSE"
        case .missing:
            return ""
        }
    }

    static func isBooleanLiteral(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower == "true" || lower == "false"
    }
}

private struct FormulaParser {
    private var tokens: [FormulaToken] = []
    private var index = 0
    private let resolver: (String) -> ReportValue?

    init(expression: String, resolver: @escaping (String) -> ReportValue?) {
        self.resolver = resolver
        var lexer = FormulaLexer(expression)
        while let token = lexer.nextToken() {
            tokens.append(token)
        }
    }

    mutating func parse() throws -> FormulaValue {
        let value = try parseOr()
        guard index == tokens.count else {
            throw FormulaError.message("Unexpected token")
        }
        return value
    }

    private mutating func parseOr() throws -> FormulaValue {
        var value = try parseAnd()
        while matchOperator("||") {
            let rhs = try parseAnd()
            value = .bool(value.bool || rhs.bool)
        }
        return value
    }

    private mutating func parseAnd() throws -> FormulaValue {
        var value = try parseEquality()
        while matchOperator("&&") {
            let rhs = try parseEquality()
            value = .bool(value.bool && rhs.bool)
        }
        return value
    }

    private mutating func parseEquality() throws -> FormulaValue {
        var value = try parseComparison()
        while true {
            if matchOperator("=") {
                value = .bool(compare(value, try parseComparison()) == 0)
            } else if matchOperator("!=") {
                value = .bool(compare(value, try parseComparison()) != 0)
            } else {
                return value
            }
        }
    }

    private mutating func parseComparison() throws -> FormulaValue {
        var value = try parseTerm()
        while true {
            if matchOperator("<") {
                value = .bool(compare(value, try parseTerm()) < 0)
            } else if matchOperator(">") {
                value = .bool(compare(value, try parseTerm()) > 0)
            } else if matchOperator("<=") {
                value = .bool(compare(value, try parseTerm()) <= 0)
            } else if matchOperator(">=") {
                value = .bool(compare(value, try parseTerm()) >= 0)
            } else {
                return value
            }
        }
    }

    private mutating func parseTerm() throws -> FormulaValue {
        var value = try parseFactor()
        while true {
            if matchOperator("+") {
                let rhs = try parseFactor()
                if let lhsNumber = value.number, let rhsNumber = rhs.number {
                    value = .number(lhsNumber + rhsNumber)
                } else {
                    value = .string(value.string + rhs.string)
                }
            } else if matchOperator("-") {
                value = .number((value.number ?? 0) - ((try parseFactor()).number ?? 0))
            } else {
                return value
            }
        }
    }

    private mutating func parseFactor() throws -> FormulaValue {
        var value = try parseUnary()
        while true {
            if matchOperator("*") {
                value = .number((value.number ?? 0) * ((try parseUnary()).number ?? 0))
            } else if matchOperator("/") {
                let rhs = (try parseUnary()).number ?? 0
                guard rhs != 0 else { return .missing }
                value = .number((value.number ?? 0) / rhs)
            } else if matchOperator("%") {
                let rhs = (try parseUnary()).number ?? 0
                guard rhs != 0 else { return .missing }
                value = .number((value.number ?? 0).truncatingRemainder(dividingBy: rhs))
            } else {
                return value
            }
        }
    }

    private mutating func parseUnary() throws -> FormulaValue {
        if matchOperator("-") {
            return .number(-((try parseUnary()).number ?? 0))
        }
        if matchOperator("!") {
            return .bool(!(try parseUnary()).bool)
        }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> FormulaValue {
        guard index < tokens.count else { throw FormulaError.message("Unexpected end of formula") }
        let token = tokens[index]
        index += 1
        switch token {
        case .number(let value):
            return .number(value)
        case .string(let value):
            return .string(value)
        case .cell(let name):
            return formulaValue(resolver(name))
        case .identifier(let name):
            if match(.leftParen) {
                return try parseFunction(name)
            }
            switch name.lowercased() {
            case "true":
                return .bool(true)
            case "false":
                return .bool(false)
            default:
                return formulaValue(resolver(name))
            }
        case .leftParen:
            let value = try parseOr()
            guard match(.rightParen) else { throw FormulaError.message("Missing closing parenthesis") }
            return value
        case .rightParen, .comma, .operatorSymbol:
            throw FormulaError.message("Unexpected token")
        }
    }

    private mutating func parseFunction(_ name: String) throws -> FormulaValue {
        var arguments: [FormulaValue] = []
        if !match(.rightParen) {
            repeat {
                arguments.append(try parseOr())
            } while match(.comma)
            guard match(.rightParen) else { throw FormulaError.message("Missing closing parenthesis") }
        }
        return try FormulaFunction.evaluate(name: name, arguments: arguments)
    }

    private func formulaValue(_ value: ReportValue?) -> FormulaValue {
        switch value {
        case .number(let number):
            return .number(number)
        case .string(let string):
            return .string(string)
        case .bool(let bool):
            return .bool(bool)
        case .missing, .error, nil:
            return .missing
        }
    }

    private mutating func match(_ token: FormulaToken) -> Bool {
        guard index < tokens.count, tokens[index] == token else { return false }
        index += 1
        return true
    }

    private mutating func matchOperator(_ symbol: String) -> Bool {
        guard index < tokens.count, case .operatorSymbol(let value) = tokens[index], value == symbol else { return false }
        index += 1
        return true
    }

    private func compare(_ lhs: FormulaValue, _ rhs: FormulaValue) -> Int {
        if let lhsNumber = lhs.number, let rhsNumber = rhs.number {
            if lhsNumber == rhsNumber { return 0 }
            return lhsNumber < rhsNumber ? -1 : 1
        }
        return lhs.string.localizedStandardCompare(rhs.string).rawValue
    }
}

private enum FormulaFunction {
    static func isFunctionName(_ name: String) -> Bool {
        supportedNames.contains(name.lowercased())
    }

    static func evaluate(name: String, arguments: [FormulaValue]) throws -> FormulaValue {
        let lowerName = name.lowercased()
        switch lowerName {
        case "abs":
            return .number(abs(number(arguments, 0)))
        case "ceil":
            return .number(ceil(number(arguments, 0)))
        case "floor":
            return .number(floor(number(arguments, 0)))
        case "neg":
            return .number(-number(arguments, 0))
        case "min":
            return .number(arguments.compactMap(\.number).min() ?? .nan)
        case "max":
            return .number(arguments.compactMap(\.number).max() ?? .nan)
        case "round":
            return .number(round(number(arguments, 0)))
        case "pow":
            return .number(pow(number(arguments, 0), number(arguments, 1)))
        case "exp":
            return .number(exp(number(arguments, 0)))
        case "ln":
            return .number(log(number(arguments, 0)))
        case "log":
            return .number(log10(number(arguments, 0)))
        case "sqrt":
            return .number(sqrt(number(arguments, 0)))
        case "sin":
            return .number(sin(number(arguments, 0)))
        case "cos":
            return .number(cos(number(arguments, 0)))
        case "tan":
            return .number(tan(number(arguments, 0)))
        case "ifthen":
            guard arguments.count >= 3 else { return .missing }
            return arguments[0].bool ? arguments[1] : arguments[2]
        case "concat":
            return .string(arguments.map(\.string).joined())
        case "contains":
            return .bool(string(arguments, 0).localizedCaseInsensitiveContains(string(arguments, 1)))
        case "startswith":
            return .bool(string(arguments, 0).lowercased().hasPrefix(string(arguments, 1).lowercased()))
        case "endswith":
            return .bool(string(arguments, 0).lowercased().hasSuffix(string(arguments, 1).lowercased()))
        case "find":
            let haystack = string(arguments, 0)
            let needle = string(arguments, 1)
            guard let range = haystack.range(of: needle) else { return .number(0) }
            return .number(Double(haystack.distance(from: haystack.startIndex, to: range.lowerBound) + 1))
        case "insert":
            var base = string(arguments, 0)
            let insertion = string(arguments, 1)
            let offset = min(max(Int(number(arguments, 2)) - 1, 0), base.count)
            base.insert(contentsOf: insertion, at: base.index(base.startIndex, offsetBy: offset))
            return .string(base)
        case "delete":
            var base = string(arguments, 0)
            let start = min(max(Int(number(arguments, 1)) - 1, 0), base.count)
            let length = max(Int(number(arguments, 2)), 0)
            let lower = base.index(base.startIndex, offsetBy: start)
            let upper = base.index(lower, offsetBy: min(length, base.distance(from: lower, to: base.endIndex)))
            base.removeSubrange(lower..<upper)
            return .string(base)
        case "replace":
            return .string(string(arguments, 0).replacingOccurrences(of: string(arguments, 1), with: string(arguments, 2)))
        case "substring":
            let base = string(arguments, 0)
            let start = min(max(Int(number(arguments, 1)) - 1, 0), base.count)
            let length = arguments.count > 2 ? max(Int(number(arguments, 2)), 0) : base.count - start
            let lower = base.index(base.startIndex, offsetBy: start)
            let upper = base.index(lower, offsetBy: min(length, base.distance(from: lower, to: base.endIndex)))
            return .string(String(base[lower..<upper]))
        case "upper":
            return .string(string(arguments, 0).uppercased())
        case "lower":
            return .string(string(arguments, 0).lowercased())
        case "word":
            let words = string(arguments, 0).split(whereSeparator: \.isWhitespace).map(String.init)
            let index = Int(number(arguments, 1)) - 1
            guard words.indices.contains(index) else { return .missing }
            return .string(words[index])
        default:
            throw FormulaError.message("Unknown function \(name)")
        }
    }

    private static let supportedNames: Set<String> = [
        "abs", "ceil", "floor", "neg", "min", "max", "round", "pow", "exp", "ln", "log", "sqrt", "sin", "cos", "tan",
        "ifthen", "concat", "contains", "startswith", "endswith", "find", "insert", "delete", "replace", "substring",
        "upper", "lower", "word"
    ]

    private static func number(_ arguments: [FormulaValue], _ index: Int) -> Double {
        guard arguments.indices.contains(index) else { return 0 }
        return arguments[index].number ?? 0
    }

    private static func string(_ arguments: [FormulaValue], _ index: Int) -> String {
        guard arguments.indices.contains(index) else { return "" }
        return arguments[index].string
    }
}
