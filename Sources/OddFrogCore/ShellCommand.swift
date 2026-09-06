import Foundation

public enum ShellCommand {
    public static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func backgroundArguments(command: String) -> [String] {
        ["-lc", command]
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
