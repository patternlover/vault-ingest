# vault-ingest

A skill for coding agents (pi, Claude Code, anything that reads `SKILL.md`) that closes a work
session into a markdown second-brain vault, then closes the terminal pane on its own.

Two things happen, in this order:

1. **Ingest.** The agent writes the session's verified facts into the right notes, appends one
   line per action to the day's log, runs the vault validator, makes **one** commit with
   explicit paths, and pushes. Nothing is committed before this point: a session that ends
   without an ingest leaves its knowledge in the transcript and nowhere else.
2. **Close.** The agent schedules the pane to close itself after 30 seconds of quiet, with a
   countdown in the pane title. No second pane to watch, no manual `kill`.

## Who it is for

You keep a markdown vault as second memory — notes with frontmatter and wikilinks, a per-day
log, `git` as the sync layer — and you run your agent inside [herdr](https://herdr.dev) panes,
on one or two machines. If the vault or `git` is missing, the ingest half does not apply; if
herdr is missing, only the self-closing pane is lost.

## Install

Clone next to your other skills and link it in, so `git pull` is the whole update story:

```bash
git clone https://github.com/patternlover/vault-ingest.git <your-skills-dir>/vault-ingest
ln -s ~/dev/skills/vault-ingest <skills-dir>/ingest      # e.g. ~/.pi/agent/skills/ingest
chmod +x <your-skills-dir>/vault-ingest/scripts/*
```

The directory name decides how you invoke it (`/skill:ingest` if the link is called `ingest`);
the skill's own name is in the `SKILL.md` frontmatter.

Then configure it — nothing private goes in this repository:

```toml
# ~/.config/vault-ingest/config.toml          (%APPDATA%\vault-ingest\config.toml on Windows)
vault_root = "/Users/you/dev/vault"
```

```toml
# <vault_root>/.ingest.toml — travels with the vault, stays private
log_dir = "log"
validator = "<command that exits 0>"
commit_prefix = "[pi]"
log_lang = "English"
```

Check it:

```bash
bash <skills-dir>/ingest/scripts/ingest-config --check
```

## The scripts

| Script | What it does | Why it exists |
| --- | --- | --- |
| `scripts/ingest-config` | Resolves the two config files and prints one `KEY=value` line per setting, with defaults; `--check` verifies the vault is there. | Keeps personal paths out of the repository, so updating the skill is a pull with no local diff to resolve. |
| `scripts/ingest-close` | Resolves the current pane, launches `pane-close-later` detached with `nohup`, prints what it scheduled, returns immediately. Optional first argument = seconds of quiet (default 30). Exits 1 without scheduling anything if the pane cannot be resolved. | One command identical on macOS and Windows. On Windows the agent runs in PowerShell 5.1, where `nohup`, `$(...)` and `"${TMPDIR:-/tmp}"` do not exist, so a hand-written background command breaks. |
| `scripts/pane-close-later` | Waits for N seconds of quiet, then closes the pane. "Quiet" means the pane's agent status is neither `working` nor `blocked`: a new turn restarts the counter, a pane waiting on a question never closes. The countdown is written once per second into the pane title via `herdr pane report-metadata`. Flags: `--pane`, `--tty` (raw panes only), `--idle`, `--poll`, `--log`, `--banner`, `--no-banner`, `--no-title`, `--dry-run`. | It is the whole safety model: the pane closes because the agent is done, not because something killed it. |
| `scripts/ensure-pane-title` | Writes three keys into the `[ui]` section of herdr's `config.toml` — `pane_borders = "always"`, `pane_outer_borders = true`, `show_agent_labels_on_pane_borders = true` — then runs `herdr server reload-config`. If they are already correct it writes nothing and reloads nothing. Optional argument = explicit config path. | The countdown lives in the title, and the title lives inside the border. With a single pane herdr does not draw the border by default, so the countdown would be invisible. |
| `scripts/test-all` | Runs every `*.test.sh` here and fails if any suite fails. | `bash scripts/*.test.sh` is not a test runner: bash executes the first file and passes the rest as arguments. |

`ingest-config --file` prints the two config files it actually read — the fastest way to see
which vault you are about to write into.

Details worth knowing before you trust them:

- `ensure-pane-title` resolves herdr's config with herdr's own precedence:
  `HERDR_CONFIG_PATH`, then `XDG_CONFIG_HOME/herdr/config.toml`, then
  `%APPDATA%\herdr\config.toml`, then `~/.config/herdr/config.toml`. When it finds nothing it
  lists the paths it tried instead of guessing; only an **explicit** path may be created. It
  keeps a `config.toml.before-pane-title` backup, follows symlinks (dotfile repos) instead of
  replacing them, and preserves CRLF.
- It restores the previous file only when herdr *rejects* the config (parse error). A warning —
  an unknown key, a missing sound file — leaves the edit in place, because herdr applies it.
- `pane-close-later` keeps a per-pane lock in `TMPDIR`, so a second call on the same pane exits
  instead of starting a second countdown. The lock only counts if that pid is still running
  this script, so a recycled pid cannot block the close forever. The title has a 15s TTL and is
  cleared on exit.
- Nothing is ever written to the tty of a pane that holds an agent: the text lands inside the
  input box and breaks the TUI. `--tty` exists for raw panes (a shell, a log).

## Test

The tests use a fake `herdr` binary and fake `config.toml` files in a temp dir: no real pane is
closed and no real config is touched. They need `bash` (3.2 is fine).

```bash
bash scripts/test-all
```

It prints each case, a per-suite `N ok, 0 fail`, and a final `4 suites, 0 failed`, returning a
non-zero exit if anything failed — usable as a gate. On macOS with bash 3.2 the current numbers
are `41 ok`, `21 ok`, `13 ok`, `37 ok`, stable over repeated runs.

If you change a script, change its test in the same commit — the suite is the only thing
standing between you and a pane that closes while a turn is still running.

## Known limits

- **Windows: `nohup` survival is untested.** The tests run against a fake herdr, so nothing
  verifies that a `nohup`-detached process outlives its launching pane on Windows. It is needed
  for about one second — the last thing it does is close that pane — and a real check takes ten:
  `bash scripts/ingest-close 5`, then, after five seconds, `herdr pane list` must not show the
  pane. Git Bash is required either way.
- **The countdown exists only in the pane title**, never in the chat transcript: it is
  display-only metadata, it leaves no output and no history, and it disappears with the pane.
- **`ensure-pane-title` edits a config file you own.** It is idempotent and backed up, but it
  does make herdr draw pane borders always. Skip step 11 if you would rather not.
- **Quiet follows the clock, with one-second granularity.** The last title update can show `2s`
  instead of `1s` when a round of `pane get` crosses a second boundary; the close is on time.
- **One commit per ingest, explicit paths.** The skill never runs `git add -A`; files outside
  the paths the agent names stay uncommitted by design.
- **No validator, no gate.** With `validator = none` the guarantee that the vault is consistent
  comes from your vault, not from this skill.

## License

MIT — see `LICENSE`.
