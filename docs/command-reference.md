# Command reference

This is an initial reference for the current terminal craft shell.  It should
be expanded as command parsing is moved into testable modules.

Commands are simulator commands unless a later implementation note identifies
a specific historical source.

## Session

| Command | Purpose |
| --- | --- |
| `HELP` | Show the short command list. |
| `QUIT` | End the current craft-shell session. |
| `/save` | Save a state snapshot. |
| `/reload` | Rebuild state from the journal. |
| `/rclog [n]` | Show recent journal lines. |

## Alarms

| Command | Purpose |
| --- | --- |
| `ALM:LIST;` | List active alarms. |
| `ALM:ACK,<id>;` | Acknowledge an alarm. |
| `ALM:CLEAR,<id>;` | Clear an alarm. |
| `ALM:RAISE,<sev>,<source>,<text>;` | Raise a simulated alarm where permitted. |

## MCC

| Command | Purpose |
| --- | --- |
| `MCC:GUIDE;` | Display a short MCC guide. |
| `MCC:SHOW <page>;` | Display a simulated MCC page. |

## Operator and access

| Command | Purpose |
| --- | --- |
| `OP:CLERK;` | Display current clerk/channel information. |
| `OP:RCACCESS,TTY="ttyV";` | Display access mask for a TTY. |
| `SET:RCACCESS,TTY="ttyV",ACCESS=H'FFFFF';` | Set simulated access mask where permitted. |
| `REQ:AUTH,CLRK="CLERK";` | Request second-clerk authorisation. |

## RC/V

| Command | Purpose |
| --- | --- |
| `RCV:MENU:APPRC` | Enter the RC/V menu. |
| `RCV:OPEN,TKT="ticket";` | Open a recent-change ticket. |
| `RCV:ADD,FIELD=value;` | Stage a change on the open ticket. |
| `RCV:CHECK;` | Validate staged changes. |
| `RCV:COMMIT;` | Commit staged changes where permitted. |
| `RCV:ABORT;` | Abort the open ticket. |

Known staged fields include `TERM`, `DN`, `PAIR`, `COS`, `LINETYPE`, `CLASS`
and `FEATURES`.

## SCC

| Command | Purpose |
| --- | --- |
| `SCC:SUBMIT,JOB="name",PARM="value";` | Submit a simulated SCC job. |
| `SCC:STAT;` | Show SCC job counts and recent jobs. |
| `SCC:OUT,JOBID=<id>;` | Show job output. |

## ROP

| Command | Purpose |
| --- | --- |
| `SHOW:ROP,LINES=n;` | Show the last `n` ROP records. |
