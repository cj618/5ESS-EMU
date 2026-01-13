# Terminal Realism (Pacific Bell Theme)

## Terminal archetypes and channels

Channels map to terminal archetypes and default TTYs:

| Channel     | Terminal Type | Default TTY |
|-------------|---------------|-------------|
| MCC         | MCC           | ttyV        |
| RCV_LOCAL   | RCV_LOCAL     | ttyV        |
| RCV_REMOTE  | RCV_REMOTE    | ttyW        |
| SCC         | SCC           | ttyS        |
| TEST        | TEST          | ttyT        |

TTY defaults are configurable via `etc/sim.json` under `terminal_map`.

## Poke dispatcher

When `FEATURE_POKES=1`, numeric input at the `CMD<` prompt is treated as a poke. The
default table includes poke **196** to enter RC/V. Poke behavior is defined in
`etc/sim.json` under `pokes`.

On success, the emulator logs STARTING/COMPLETED entries to the ROP stream. On
denial (channel/login/RCACCESS), it prints `RESULT: NG - RC SECURITY DENIED` and
logs the denial.

## RC/V menu flow (compatibility)

Poke 196 is an alias for entering the existing RC/V menu when
`FEATURE_RCV_VIEWS=0`. The current flow remains:

* 1 — Line/Station assignment
* 8 — Directory Number assignment
* 0 — Verify (translation dump)
* Q — Quit back to craft shell

## Records Output Printer (ROP)

ROP is a separate append-only stream stored under the state directory, default
`var/rop.log`. Each line uses a deterministic, paper-style format:

```
YYYY-MM-DD HH:MM:SS  BRAND/OFFICE SWITCH  ROP  SUBSYS SEV  message [key=value...]
```

ROP is viewable via `SHOW:ROP;` (default 20 lines) or
`SHOW:ROP,LINES=50;`.

