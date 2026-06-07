# Pacific Bell theme

Pacific Bell is the default house style for 5ESS-EMU.  The simulator should
feel like a small central-office craft environment somewhere in California in
the mid-1990s: terse terminals, ROP output, operator notices, service orders,
SCC chatter and a large switching machine implied behind the screen.

This is a simulated setting.  Do not use real customer data, real internal
telephone-company records or real operational secrets.

## Default fictional office

| Field | Value |
| --- | --- |
| Company | Pacific Bell Telephone Company |
| Region | Northern California |
| Office id | SF01 |
| Switch | 5ESS-SF |
| Era | 1993-1998 |
| Environment | Central office craft shell / network operations terminal |

## Desired feel

The project should feel like a recovered Unix account from a central office,
not a modern dashboard.  Favour fixed-width output, simple files, uppercase
operator messages, short error codes, pager prompts and practical docs.

Good atmosphere:

* private-system warning banners;
* clerk and TTY terminology;
* RC/V tickets and terse result lines;
* SCC jobs that complete asynchronously;
* ROP printer-style records;
* MCC page indexes and status summaries;
* simulated alarms for power, modules, trunks, journals and operator actions;
* configuration profiles for different fictional offices.

Avoid:

* cyberpunk excess;
* modern SaaS language;
* real access procedures;
* claims of official compatibility;
* fake corporate provenance.

## Useful simulated screens

Future work should expand the MCC page tree.  Candidate pages:

| Page | Purpose |
| --- | --- |
| 1000 | Master page index |
| 105 | System status summary |
| 110 | Switch environment |
| 123 | Network overview |
| 125 | Trunk summary |
| 1800X | Processor/module status |
| 1850 | Recent-change activity |
| 1960 | Operator event display |

## Wow test

A feature is on-theme if it makes the program more credible to a telecom
history reader, a Perl/Unix person and someone who remembers 1990s terminal
culture, while remaining clearly fictional and safe.
