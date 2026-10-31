---
name: ingest
description: Close a working session into a markdown second-brain vault — find or update the right note, append the log line, run the validator, make one commit with explicit paths, push — then schedule this pane to close itself after 30 seconds of quiet, with the countdown in the pane title. Use it at the end of any session that produced knowledge worth keeping: when the user says "ingest", "close the session", "save this to the vault", "write it to the brain", "wrap up and commit", or types /skill:ingest. Also use it when a session is about to end and nothing has been written yet.
---

# Ingest at the end of a session

A session that ends without an ingest is lost memory: what was discovered stays only in the
session transcript, and the next session starts from zero. This skill does two things:
**it writes what matters into the vault**, and **it closes the pane on its own** after 30
seconds of quiet, so there is nothing left to kill by hand. The only signal the user sees is
the countdown in the **pane title** — no second pane to watch, nothing to read on the side.

Nothing gets committed before this point. During the session the vault stays dirty; this
skill makes the single commit.

## Config

The protocol below is vault-agnostic; the names are not. They live in a file **outside this
repository**, so you can `git pull` this skill without ever resolving a merge in your own
paths, and so nothing private ends up in a commit here.

Two files, in this order:

1. **Machine file** — where the vault is. `$INGEST_CONFIG`, else
   `$XDG_CONFIG_HOME/vault-ingest/config.toml`, else `~/.config/vault-ingest/config.toml`
   (macOS, Linux) or `%APPDATA%\vault-ingest\config.toml` (Windows):

   ```toml
   vault_root = "/Users/you/dev/vault"
   ```

2. **Vault file** — `<vault_root>/.ingest.md`, everything else. It lives with the vault
   because it describes that vault, so it is private by construction and travels with the
   notes:

   ```toml
   log_dir = "90 System/Log"
   log_file = "<today> pi-<host>.md"
   validator = "node scripts/validate.mjs"
   commit_prefix = "[pi]"
   log_lang = "English"
   ```

Never put the machine file inside the vault, and never commit it: it is the one file that
identifies the machine. `<vault>/.ingest.md` is different — it describes the vault, it holds no
secret, and having it in the vault means it travels with the notes to your other machine.

Read the config through the helper instead of parsing it by hand — it applies the defaults and
tells you when something is missing:

```bash
bash '<skill-dir>/scripts/ingest-config'            # all resolved KEY=value lines
bash '<skill-dir>/scripts/ingest-config' vault_root # one value
bash '<skill-dir>/scripts/ingest-config' --check    # is the vault there and readable?
```

| Key | Default | Meaning |
| --- | --- | --- |
| `vault_root` | — (required) | absolute path of the markdown vault |
| `vault_marker` | `AGENTS.md` | file whose presence proves a path is the vault root |
| `log_dir` | `log` | directory holding one log file per day |
| `log_file` | — | today's log name; empty means "pick the day's file that already exists" |
| `validator` | `none` | command that must exit 0 before the commit |
| `commit_prefix` | `[pi]` | leading token that marks agent commits |
| `log_lang` | — | language of the log line (empty = the vault's own language) |

Why a config file and not a rewrite: the skill ships as one file per user, but paths differ
per user. Keeping them outside the repo means updates are a pull with no local diff to carry.

## Steps
## Steps

1. **Find the vault.** Start with `bash '<skill-dir>/scripts/ingest-config'`: one
   `key=value` line per setting, defaults applied. Every `<key>` below is one of those
   values, so read it once instead of guessing. If `vault_root` is empty or `--check` fails,
   ask the user for the path and write it in the machine file from the Config section — then
   run it again. Never invent a path: a commit written into the wrong directory is worse than
   no commit.
2. **Sync.** `git -c rebase.autoStash=true pull --rebase`. `autoStash` keeps the vault's own
   editor metadata (graph/workspace JSON that the editor rewrites on its own) out of the way
   — never commit those files.
3. **Read before writing.** The vault's own `AGENTS.md` (or equivalent convention file),
   then look for the note that should already hold this fact by name, aliases, tags and
   text. If it exists, update it. Never create a second note for the same fact.
4. **Decide what to keep** using the table below. Only facts verified during this session:
   no "probably", and nothing another system already owns. The table names buckets that a
   mature vault has; if this vault has none of them, put the fact in the closest note that
   already exists and say which one in the report. Creating a bucket folder is a decision
   about someone's vault, not something to do silently on the first ingest.
5. **Write** following the vault protocol: complete frontmatter, one fact per line, the
   modified date set to today, `reviewed: false`, and wikilinks to people, organizations
   and projects.
6. **The open thread.** If the session leaves something pending — a missing credential, a
   decision that waits for the user, a red test, a step that belongs to someone else —
   record it in an `## Open` section of the project note, or in the log line if there is no
   project note. This is the one thing a fresh session cannot infer; without it the work
   looks finished.
7. **Log line** in `<log_dir>/<log_file>`, one line per action, in `<log_lang>`, with
   wikilinks: `- 18:40 — updated [[Checkout tracking]] with the GA4 checkout events`.
   Before writing, open the most recent file in `<log_dir>` and copy its shape exactly —
   including frontmatter if it has any, because your validator probably walks that folder
   too, and a log file without the required frontmatter turns step 8 red for a reason that
   has nothing to do with the work. If `<log_dir>` does not exist, create it. If `<log_file>`
   is empty and today has no log yet, reuse the naming of the most recent one with today's
   date instead of inventing a second scheme: the log is read by day, not by machine.
8. **Validator.** Run `<validator>`; with `none`, skip the step and say so in the report.
   Exit 0 is mandatory. On a non-zero exit: one attempt to
   fix, then stop, report what is red, and **do not schedule the pane close** — a vault that
   fails its own check should stay open in front of the human.
9. **One commit.** Explicit paths, never `git add -A`: another session may be working in the
   same directory, and `-A` would swallow its half-finished files. Message
   `<commit_prefix> <action>: <description>`, where `<action>` is
   `create | update | move | delete | log` — the dominant one when a session both adds a file
   and edits another. "Yours" means the paths you touched in this session: if those are the
   only thing `git status` lists, commit; if it lists nothing you touched, commit nothing,
   because an empty commit is noise and a commit of someone else's half-work is a conflict.
10. **Push.** `git -c rebase.autoStash=true pull --rebase` then `git push`. Two machines stay
    in sync only this way. If the push fails, say so and do not schedule the pane close.
11. **Visible title.** `bash '<skill-dir>/scripts/ensure-pane-title'`. It resolves the herdr
    config with herdr's own precedence (`HERDR_CONFIG_PATH`, then `XDG_CONFIG_HOME`, on
    Windows `%APPDATA%\herdr\config.toml`) and writes the three keys that make herdr draw
    the border — and therefore the title — even with a single pane, then reloads the config.
    **Once only**: if the keys are already right it writes nothing and reloads nothing, so it
    is safe on every ingest. If it says it could not find the config, do not guess: locate
    the file and pass it as the argument — with an explicit path it creates the file when
    missing, because there the location is your decision, not a guess. If it exits 1 (herdr
    missing, red reload), report it and carry on: you lose the countdown, not the session.
12. **Schedule the close** with `bash '<skill-dir>/scripts/ingest-close'`. It closes this
    pane after 30 seconds of quiet and the countdown runs in the title. Do not retype the
    countdown in the report. To see what it would do without closing anything, use
    `bash '<skill-dir>/scripts/pane-close-later' <idle> --pane <id> --dry-run`: it prints
    nothing on the terminal, everything goes to its log under `TMPDIR`
    (`pane-close-later-<pane>.log`), which is also where a real run leaves its trail.
13. **Report**, at most 8 lines: files touched · what you did not save and why · open thread
    · when the pane closes.

If there is nothing to save, the report is one line and the close is scheduled anyway: the
session is over either way.

## What goes in, what stays out

| In | Out |
| --- | --- |
| How a mechanism works: the method, the terminology, who decides and why | Raw numbers: sessions, conversions, revenue, extracts |
| What is configured for a given client/project: the pieces, key events, where the data lands → a `type: note` page | Raw IDs as content: cite containers, properties, accounts by name or artifact link, not as payload |
| Qualitative context about a client: how they work, who decides, constraints, history, contacts → the organization note | Secrets, credentials, tokens, card data |
| Decisions with their reason, including later-reversed ones | The session transcript: the chat stays in the transcript, the vault keeps the distillate |
| A reusable technique, with the file or command that demonstrates it | What another system already owns (task manager, spreadsheet): link to it, do not copy |

A tracking map is a `type: note` page, and the organization note carries the link to it.
A map keeps growing and is not a fact about the company: that is why it does not live inside
the organization note.

## Rules

- One verifiable fact per line. If it is not verified: `[TODO]` or nothing.
- If the session contradicts the vault, the session wins: fix it, and write in the log line
  what you corrected and why.
- Do not delete notes and do not invent facts about people: at most propose them in the
  report.
- Do not rewrite the prose of existing notes: add the new fact, remove the refuted one.

## Closing the pane

One command, same on macOS and Windows: `<skill-dir>` is the path of this skill.

```bash
bash '<skill-dir>/scripts/ingest-close'
```

It does three things: resolves the current pane, launches `scripts/pane-close-later`
detached with `nohup` (30s of quiet by default, `ingest-close 60` to change it), and returns
immediately. If the pane cannot be resolved it exits 1 without scheduling anything: **no
half-done close**.

In the pane the user reads the countdown in the **title** (herdr `report-metadata`, one line
per second). The title lives inside the border, and with a single pane herdr does not draw
the border, so the countdown would be invisible — that is why step 11 runs
`ensure-pane-title` once. The three keys are needed together: `pane_borders = "always"`
without `pane_outer_borders` does nothing, and without the agent-label key there is no label
when the pane has no manual name. Before writing, the script leaves a
`config.toml.before-pane-title` backup; if the reload is red it restores it and exits 1.

```text
[LOG] Ingest Completed · Pane closing in: 30s
[LOG] Ingest Completed · Pane closing in: 29s
...
[LOG] Pane closing now
```

- **No second pane.** One pane, the agent's own: what the script writes goes into the title
  and into its log under `TMPDIR`, not on screen.
- **Never write to the tty of a pane with an agent in it**: the text lands above the prompt,
  inside the input box, and breaks the TUI drawing. `--tty /dev/ttysNNN` stays for raw panes
  — a shell, a log — not for an agent.
- It closes only after **30 seconds of quiet**: if another prompt arrives, the status goes
  back to `working`, the title becomes `[LOG] activity detected (...): countdown cancelled`
  and the counter restarts, so a live turn never dies. A pane sitting on a question
  (`blocked`) never closes. A single silent answer from herdr is retried, not treated as a
  dead pane.
- `--banner '<text>'` changes the prefix, `--no-banner` removes it, `--no-title` leaves the
  title alone (log only), `--idle N` changes the seconds, `--log <path>` moves the log,
  `--dry-run` says what it would do without closing or touching anything.
- The title has a 15s TTL and is cleared on exit: if the script dies, the title does not stay
  stuck on the pane.
- Do not use `herdr pane close` by hand: the guard lives in the script.
- If the script or `herdr` is missing, say so and close nothing: better a leftover pane than
  a half-closed session. Every run leaves its trail in `TMPDIR/pane-close-later-<pane>.log`:
  read that, not the pane, when you need to know what happened.
- The countdown never appears in the chat transcript: it is a title, not agent output, and it
  disappears with the pane.
- A second `ingest-close` on the same pane does nothing: the lock in `TMPDIR` stops it.
- `pane-close-later` can be launched on its own
  (`bash '<skill-dir>/scripts/pane-close-later' 30 --pane w5:p3`) to close a pane that is not
  the ingest's.
- **Windows**: Git Bash is required. Never hand-write `nohup`, `$(...)` or
  `"${TMPDIR:-/tmp}"` in a command for the user — PowerShell 5.1 has none of them. The only
  commands you give are `bash '<skill-dir>/scripts/ingest-close'` and, when closing a pane
  that is not this one, `bash '<skill-dir>/scripts/pane-close-later'`.
- Changing the scripts? `bash '<skill-dir>/scripts/test-all'` must end with `3 suites, 0 failed`.
  The suites run against a fake herdr and fake `config.toml` files in a temp dir: no real
  pane, no real config, no risk.
