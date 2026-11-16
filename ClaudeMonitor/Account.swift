//
//  Account.swift
//  ClaudeMonitor
//

import Foundation

/// Satu akun Claude Code = satu item Keychain `Claude Code-credentials*`.
nonisolated struct Account: Identifiable, Hashable {
    let id: String       // = service
    let service: String
    let label: String
    let command: String
    /// Path absolut folder config; nil untuk akun default (~/.claude).
    let configDir: String?
}

nonisolated enum AccountDiscovery {
    /// Temukan semua akun: daftar item Keychain (tanpa membaca token) dicocokkan
    /// dengan folder `~/.claude*` lewat hash path.
    static func discover(home: String = NSHomeDirectory()) -> [Account] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: home)) ?? []
        let dirs = names.filter { name in
            var isDir: ObjCBool = false
            return name.hasPrefix(".claude")
                && fm.fileExists(atPath: "\(home)/\(name)", isDirectory: &isDir)
                && isDir.boolValue
        }
        return build(services: Credentials.listServices(), dirNames: dirs, home: home)
    }

    /// Bagian murni dari `discover`: item default → "default"; item bersufiks
    /// yang cocok dengan folder → label folder; sufiks tanpa folder (yatim) dibuang.
    static func build(services: [String], dirNames: [String], home: String) -> [Account] {
        var dirBySuffix: [String: String] = [:]
        for name in dirNames {
            if let s = AccountMath.suffix(ofService: AccountMath.serviceName(forConfigDir: "\(home)/\(name)")) {
                dirBySuffix[s] = name
            }
        }
        var accounts: [Account] = []
        for service in Set(services) where AccountMath.isClaudeService(service) {
            if let suffix = AccountMath.suffix(ofService: service) {
                guard let dir = dirBySuffix[suffix] else { continue }  // yatim
                accounts.append(Account(id: service, service: service,
                                        label: AccountMath.label(forDirName: dir),
                                        command: AccountMath.launchCommand(dirName: dir, home: home),
                                        configDir: "\(home)/\(dir)"))
            } else {
                accounts.append(Account(id: service, service: service, label: "default",
                                        command: AccountMath.launchCommand(dirName: nil, home: home),
                                        configDir: nil))
            }
        }
        return accounts.sorted { a, b in
            let ad = a.service == AccountMath.defaultService, bd = b.service == AccountMath.defaultService
            if ad != bd { return ad }
            return a.label < b.label
        }
    }
}
