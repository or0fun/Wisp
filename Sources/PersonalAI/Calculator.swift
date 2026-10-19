import Foundation

enum CalculationResult: Equatable { case value(String), issue(String) }

enum Calculator {
    static func evaluate(_ input: String) -> CalculationResult? {
        var expression = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicit = expression.hasPrefix("=")
        if explicit { expression.removeFirst() }
        if expression.hasSuffix("=") { expression.removeLast() }
        expression = expression.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")")
        let characters = Set("0123456789.eE+-*/^%()")
        guard !expression.isEmpty, expression.allSatisfy({ characters.contains($0) || $0.isWhitespace }),
              explicit || expression.contains(where: { "+-*/^%()".contains($0) }) else { return nil }
        guard expression.count <= 512 else { return .issue("公式过长，最多 512 个字符") }
        do {
            var parser = Parser(expression)
            let value = try parser.parse()
            guard value.isFinite else { return .issue("计算结果超出范围") }
            let formatted = String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value == 0 ? 0 : value)
            return .value(formatted)
        } catch let error as AppError { return .issue(error.localizedDescription) }
        catch { return .issue("继续输入完整公式") }
    }

    private struct Parser {
        let input: [Character]
        var index = 0
        var depth = 0
        init(_ expression: String) { input = Array(expression.filter { !$0.isWhitespace }) }
        var current: Character? { index < input.count ? input[index] : nil }
        mutating func parse() throws -> Double {
            let value = try sum()
            guard index == input.count else { throw AppError.message("公式格式不正确") }
            return value
        }
        mutating func sum() throws -> Double {
            var value = try product()
            while let symbol = current, symbol == "+" || symbol == "-" {
                index += 1; let right = try product(); value = symbol == "+" ? value + right : value - right
            }
            return value
        }
        mutating func product() throws -> Double {
            var value = try unary()
            while let symbol = current, symbol == "*" || symbol == "/" {
                index += 1; let right = try unary()
                if symbol == "/" && right == 0 { throw AppError.message("除数不能为 0") }
                value = symbol == "*" ? value * right : value / right
            }
            return value
        }
        mutating func unary() throws -> Double {
            depth += 1; defer { depth -= 1 }
            guard depth <= 64 else { throw AppError.message("公式嵌套过深") }
            if current == "+" { index += 1; return try unary() }
            if current == "-" { index += 1; return try -unary() }
            var value = try primary()
            while current == "%" { index += 1; value /= 100 }
            if current == "^" { index += 1; value = pow(value, try unary()) }
            return value
        }
        mutating func primary() throws -> Double {
            if current == "(" {
                index += 1; let value = try sum()
                guard current == ")" else { throw AppError.message("继续输入完整括号") }
                index += 1; return value
            }
            let start = index
            while let char = current, ("0"..."9").contains(char) || char == "." { index += 1 }
            if current == "e" || current == "E" {
                index += 1
                if current == "+" || current == "-" { index += 1 }
                while let char = current, ("0"..."9").contains(char) { index += 1 }
            }
            guard index > start, let value = Double(String(input[start..<index])), value.isFinite else { throw AppError.message("继续输入完整公式") }
            return value
        }
    }
}
