You are an agent tasked with a full, big-bang refactor of Sinter per the
technical design. Follow TDD and ensure all tests and tooling pass with no
warnings or errors.

Required reading (absolute paths):
- /home/home/p/g/n/sinter/docs/20251227/sinter_big_bang_technical_design.md
- /home/home/p/g/n/sinter/README.md
- /home/home/p/g/n/sinter/CHANGELOG.md
- /home/home/p/g/n/sinter/mix.exs
- /home/home/p/g/n/sinter/lib
- /home/home/p/g/n/sinter/test
- /home/home/p/g/n/sinter/examples
- /home/home/p/g/n/sinter/examples/README.md
- /home/home/p/g/n/sinter/docs
- /home/home/p/g/n/sinter/jsv (local clone for reference; use it to understand APIs)
- /home/home/p/g/North-Shore-AI/tinkex/README.md
- /home/home/p/g/North-Shore-AI/tinkex/lib
- /home/home/p/g/North-Shore-AI/tinkex/test
- /home/home/p/g/North-Shore-AI/tinkex/docs

Core requirements:
- Implement the big-bang refactor described in the technical design, including:
  - String-keyed schema fields as default internal representation.
  - Nested object schema type and DSL support.
  - Dual JSON Schema draft support (Draft 7 + Draft 2020-12).
  - JSON Schema validation via JSV v0.13.1.
  - JSON encode/decode helpers and transform pipeline (aliases/omit/tri-state).
  - Updated provider-specific JSON Schema behaviors (recursive strictness).
  - Fix known bugs: default/required ordering and validate_many path order.
- Replace ex_json_schema with jsv:
  - Add {:jsv, "~> 0.13.1"} in mix.exs.
  - Remove {:ex_json_schema, ...} and related code.
  - Use /home/home/p/g/n/sinter/jsv for API reference.
- TDD: write failing tests first for each new behavior or bug fix, then
  implement.

Examples and docs:
- Add /home/home/p/g/n/sinter/examples/run_all.sh to run all examples.
- Update /home/home/p/g/n/sinter/examples/README.md to include the new runner
  and current example list.
- Fully revamp /home/home/p/g/n/sinter/README.md with updated examples and
  new APIs.
- Update /home/home/p/g/n/sinter/docs to reflect the new architecture and
  remove stale references.

Versioning and changelog:
- Bump version to 0.1.0 in /home/home/p/g/n/sinter/mix.exs.
- Update dependency snippet in /home/home/p/g/n/sinter/README.md to 0.1.0.
- Add a 2025-12-27 entry in /home/home/p/g/n/sinter/CHANGELOG.md that
  summarizes the refactor.

Quality gates (must pass with no warnings/errors):
- mix format --check-formatted
- mix compile --warnings-as-errors
- mix credo --strict
- mix test
- mix dialyzer
- examples/run_all.sh

Output:
- Provide a concise final report summarizing changes, key files, and commands
  run.
- Call out any risks or tradeoffs explicitly.

