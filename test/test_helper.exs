ExUnit.start()

# Configure ExUnit
ExUnit.configure(
  exclude: [:skip, :pending],
  formatters: [ExUnit.CLIFormatter],
  max_failures: 10,
  seed: 0,
  timeout: 30_000,
  trace: false
)
