# LLM Tooling Auth Expectations

## Codex CLI

- CLI installation is manual for now and is not performed by bootstrap.
- VM-local auth can use ChatGPT login or `OPENAI_API_KEY`.
- Mixed-auth provider configuration lives at `~/.codex/config.toml`.
- Proxy-capable Codex provider blocks must keep `requires_openai_auth = true` so OpenAI auth remains enforced when routing through a custom provider.
- Credential and config state should remain under `~/.codex`.

## Claude Code

- CLI installation is manual for now and is not performed by bootstrap.
- VM-local auth can use Claude browser login or `ANTHROPIC_API_KEY`.
- Proxy or gateway usage can export `ANTHROPIC_AUTH_TOKEN`.
- Browser-based auth caches land in `~/.claude/.credentials.json`.
- Tool-managed state should remain under `~/.claude`.

## Gemini CLI

- CLI installation is manual for now and is not performed by bootstrap.
- VM-local auth can use Google OAuth or `GEMINI_API_KEY`.
- Alternative hosted routing can use Vertex configuration rather than a local API key.
- Gemini-managed state should remain under `~/.config/gemini`.

## Privilege Rules

- Codex, Claude, and Gemini authenticate as the target user, not root.
- Bootstrap deploys documentation and templates only; it does not copy tokens, browser sessions, or API keys.
- No credential files should be copied into the repo or `.bootstrap/state.json`.
