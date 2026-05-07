<div align="center">

# agenda

**Read macOS Calendar data from a small command-line surface.**

EventKit access for agents and humans: permission status, explicit access requests, calendar inventory, and upcoming events without opening Calendar.app.

![runtime: Swift + EventKit](https://img.shields.io/badge/runtime-Swift%20%2B%20EventKit-f05138?style=flat&logo=swift&logoColor=white)
[![shell: mise](https://img.shields.io/badge/shell-mise-7c3aed?style=flat)](https://mise.jdx.dev)
![platform: macOS](https://img.shields.io/badge/platform-macOS-blue?style=flat)
![tests: 3 passing](https://img.shields.io/badge/tests-3%20passing-brightgreen?style=flat)

</div>

## Shape

The read commands do not trigger the macOS permission prompt. Use `agenda request-access` when you want the prompt; use `agenda status` to inspect the current state safely.

```bash
agenda status
agenda request-access
agenda calendars
agenda calendars --json
agenda upcoming --days 14 --limit 20
agenda upcoming --calendar Work --json
```

## Commands

- `status` — show Calendar authorization state without prompting.
- `request-access` — ask macOS for full EventKit calendar access.
- `calendars` — list readable calendars, sources, types, and writability.
- `upcoming` — list events from now through a configurable day window.

## Permission model

Calendar access is attached to the terminal app that runs the command. If you run agenda from Terminal, iTerm, Ghostty, or an agent harness, macOS grants or denies that app. Denied access is fixed in System Settings → Privacy & Security → Calendars.

```bash
# Safe: never prompts
agenda status

# Intentional: may show the macOS permission prompt
agenda request-access

# Requires read access already granted
agenda upcoming --days 7
```

## JSON for agents

Every read surface that returns structured data accepts `--json`. Event timestamps are ISO-8601 strings; all-day events use `YYYY-MM-DD`.

```bash
agenda status --json
agenda calendars --json
agenda upcoming --days 3 --limit 10 --json
```

## Development

```bash
gh repo clone KnickKnackLabs/agenda
cd agenda
mise trust && mise install
mise run test
readme build --check
```

Tests use [BATS](https://github.com/bats-core/bats-core) — 3 tests across 1 suite. CI runs on macOS so the Swift source can typecheck against EventKit.

<div align="center">

README generated from `README.tsx` with [readme](https://github.com/KnickKnackLabs/readme).

</div>
