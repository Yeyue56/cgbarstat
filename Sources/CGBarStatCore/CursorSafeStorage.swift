import CommonCrypto
import Foundation

enum CursorSafeStorage {
    static let prefix = "cursor-safe-storage:v1:"
    private static let keychainService = "Cursor Safe Storage"
    private static let keychainAccount = "Cursor Key"
    private static let version = Data("v10".utf8)
    private static let salt = Data("saltysalt".utf8)
    private static let iterations: UInt32 = 1003

    static func isSealed(_ value: String) -> Bool {
        value.hasPrefix(prefix)
    }

    /// 用 Cursor 钥匙串里的 Safe Storage 口令解开。口令只留在内存里，同一轮启动只向钥匙串要一次。
    static func open(_ stored: String) -> String? {
        guard isSealed(stored), let password = cachedPassword() else { return nil }
        return open(stored, password: password)
    }

    static func open(_ stored: String, password: String) -> String? {
        guard stored.hasPrefix(prefix) else { return stored }
        let payload = String(stored.dropFirst(prefix.count))
        guard let encrypted = Data(base64Encoded: payload), encrypted.starts(with: version) else { return nil }
        guard let plain = decrypt(Data(encrypted.dropFirst(version.count)), password: password),
              let text = String(data: plain, encoding: .utf8) else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func seal(_ token: String, password: String) -> String? {
        guard let cipher = encrypt(Data(token.utf8), password: password) else { return nil }
        var blob = version
        blob.append(cipher)
        return prefix + blob.base64EncodedString()
    }

    private static let passwords = PasswordCache()

    private static func cachedPassword() -> String? {
        if let password = passwords.get() { return password }
        guard let password = keychainPassword() else { return nil }
        passwords.set(password)
        return password
    }

    private static func keychainPassword() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", keychainService,
            "-a", keychainAccount,
            "-w",
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        _ = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let password = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines),
              !password.isEmpty else {
            return nil
        }
        return password
    }

    private static func decrypt(_ cipher: Data, password: String) -> Data? {
        crypt(cipher, password: password, operation: CCOperation(kCCDecrypt))
    }

    private static func encrypt(_ plain: Data, password: String) -> Data? {
        crypt(plain, password: password, operation: CCOperation(kCCEncrypt))
    }

    /// Chromium / Electron safeStorage：PBKDF2-SHA1，AES-128-CBC，初始向量是 16 个空格。
    private static func crypt(_ input: Data, password: String, operation: CCOperation) -> Data? {
        guard let key = derivedKey(password: password) else { return nil }
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: input.count + kCCBlockSizeAES128)
        var written = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            kCCKeySizeAES128,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress,
                            input.count,
                            outputBytes.baseAddress,
                            outputBytes.count,
                            &written
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return output.prefix(written)
    }

    private static func derivedKey(password: String) -> Data? {
        let passwordData = Data(password.utf8)
        var key = Data(count: kCCKeySizeAES128)
        let status = key.withUnsafeMutableBytes { keyBytes in
            passwordData.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        iterations,
                        keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        kCCKeySizeAES128
                    )
                }
            }
        }
        return status == kCCSuccess ? key : nil
    }

    /// 口令不出进程。失败不缓存，用户拒绝后下一次刷新还可以再问。
    private final class PasswordCache: @unchecked Sendable {
        private let lock = NSLock()
        private var password: String?

        func get() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return password
        }

        func set(_ password: String) {
            lock.lock()
            self.password = password
            lock.unlock()
        }
    }
}
