/// Options needed to run one wrapped command from the CLI.
struct CommandRunRequest: Sendable {
    let command: String
    let commandKey: String
    let maximumRunCount: Int
    let quiet: Bool
    let color: BarColor
    let progressBarStyle: ProgressBarStyle
}
