# Implementation notes

This file records why simulator features exist and how closely they are tied
to source material.

Use these labels:

* DOCUMENTED - based on identifiable technical documentation.
* PLAUSIBLE - inferred from related systems or operational practice.
* FICTIONAL - invented for the simulator.
* ATMOSPHERIC - included for period flavour only.

## Current simulator choices

### Pacific Bell default theme

Label: ATMOSPHERIC / PLAUSIBLE

The default configuration uses Pacific Bell-flavoured names and a fictional
Northern California office.  This gives the simulator a coherent setting while
remaining clearly separate from real telephone-company systems.

### Journal-backed state

Label: PLAUSIBLE

The simulator keeps a simple append-only journal and replay mechanism.  This
is not a claim about actual 5ESS persistence internals.  It gives the toy
simulator an operator-friendly audit trail and makes later test/demo work
predictable.

### RC/V ticket workflow

Label: PLAUSIBLE

Recent-change/verify work is represented through open, staged changes, check,
commit and abort.  The exact command strings are simulator commands unless
separately documented from source material.

### ROP output

Label: PLAUSIBLE / ATMOSPHERIC

ROP output is implemented as a text log with terse records.  It is intended to
suggest printer/log output from a switching operations environment, not to
reproduce a proprietary format exactly.

### SCC jobs

Label: PLAUSIBLE / FICTIONAL

SCC jobs are represented as queued, running and done tasks.  This creates
background life in the simulator and a useful basis for future batch-style
operations.

## Future notes to add

* MCC page model and page numbering.
* Alarm catalogue and severity rules.
* Trunk group representation.
* Line equipment records.
* CGI craft-console session model.
* Demo office generation.
