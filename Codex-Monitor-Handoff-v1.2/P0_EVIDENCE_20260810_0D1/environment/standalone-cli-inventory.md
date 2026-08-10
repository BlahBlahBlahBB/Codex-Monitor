# Standalone CLI inventory (sanitized)

- Installer: OpenAI official standalone installer, invoked after user approval: `curl -fsSL https://chatgpt.com/codex/install.sh | sh`.
- Resolved standalone version: `codex-cli 0.147.0`.
- PATH resolution after installer: standalone CLI in `<HOME>/.local/bin/codex`.
- Managed package: `<CODEX_HOME>/packages/standalone/current/codex`, linked to standalone release `0.147.0` for Apple Silicon.
- The previous PATH target was the ChatGPT.app-bundled executable. It was neither modified nor replaced.
- The installer added the standalone PATH entry for future login shells. Its warning about inability to create PATH aliases did not prevent standalone installation or PATH resolution.
