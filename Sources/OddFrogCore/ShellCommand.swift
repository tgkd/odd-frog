import Foundation

public enum ShellCommand {
    public static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func backgroundArguments(command: String) -> [String] {
        ["-lc", command]
    }

    public static func customTerminalCommand(template: String, shell: String, cwd: String, command: String) -> String? {
        let trimmed = template.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.contains("{command}") else { return nil }
        var result = ""
        var index = template.startIndex
        while index < template.endIndex {
            if template[index] == "{" {
                let rest = template[index...]
                if rest.hasPrefix("{cwd}") {
                    result += quote(cwd)
                    index = template.index(index, offsetBy: 5)
                    continue
                }
                if rest.hasPrefix("{shell}") {
                    result += quote(shell)
                    index = template.index(index, offsetBy: 7)
                    continue
                }
                if rest.hasPrefix("{command}") {
                    result += quote(command)
                    index = template.index(index, offsetBy: 9)
                    continue
                }
            }
            result.append(template[index])
            index = template.index(after: index)
        }
        return result
    }

    public static func terminalCommandString(shell: String, command: String) -> String {
        "\(quote(shell)) -lc \(quote(command))"
    }

    public static func agtermArguments(cwd: String, name: String, shell: String, command: String) -> [String] {
        [
            "session", "new",
            "--json",
            "--cwd", cwd,
            "--name", name,
            "--wait",
            "--command", terminalCommandString(shell: shell, command: command),
        ]
    }

    public static func commandFileContents(shell: String, cwd: String, command: String) -> String {
        """
        #!\(shell) -l
        cd \(quote(cwd)) || exit 1
        exec \(quote(shell)) -lc \(quote(command))

        """
    }

    public static func isAgtermUnavailable(stderr: String) -> Bool {
        stderr.contains("is agterm running?") || stderr.contains("connect(")
    }
}
