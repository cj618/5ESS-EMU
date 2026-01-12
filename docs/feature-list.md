# Feature List v0

Initial inventory of feature domains referenced in the 5ESS maintenance manual and their current emulator coverage.

## Operator UI/workflows

| Feature domain | Description | Emulator status |
| --- | --- | --- |
| Craft shell commands | Shell-style prompt with core commands (HELP, QUIT, ALM:LIST, RC/V entry). | **Present** (CRAFT prompt, HELP/QUIT/ALM:LIST). |
| Recent Change/Verify (RC/V) menu | Menu-driven Recent Change/Verify workflow (Line/Station, Directory-Number, Verify). | **Present** (RCV menu with Line/Station, Directory-Number, Verify). |
| MCC pages | Master Control Center (MCC) page display system and location guide. | **Missing**. |
| MCC page location guide | Index of MCC pages by release/version. | **Missing**. |
| TLWS task selection pages | Trunk and Line Work Station task selection pages and commands. | **Missing**. |
| STLWS | Supplementary TLWS terminal workflows. | **Missing**. |
| DAP / Non-DAP terminal | Display Administration Process or non-DAP terminal access. | **Missing**. |
| MCC/SCCS terminal channels | Maintenance Control Center / Switching Control Center System terminal workflows. | **Missing**. |
| RC/V terminal roles | Local/remote RC/V terminals and repair service bureau/switching control center RC/V roles. | **Partial** (single local RC/V flow only). |
| Screen program user's guide / I/O messages | Screen program and input/output message usage; input message editing/history. | **Missing**. |
| Call Monitor | Call Monitor tools and reports. | **Missing**. |

## Data/translation management

| Feature domain | Description | Emulator status |
| --- | --- | --- |
| Line/terminal records | Line/Station assignment workflow and storage for terminal data. | **Present** (in-memory line records). |
| Directory number (DN) assignment | Assign DN to a terminal. | **Present**. |
| Translation verification dump | Verify/translation database dump of line/DN records. | **Present**. |
| Office Data Base Editor (ODBE) | Database editor for office data/translation records. | **Missing**. |
| Access Editor (ACCED) | Access editor for line/feature configuration. | **Missing**. |
| Current Update Data Base/History Editor (UPedcud) | Update/history editor for translation updates. | **Missing**. |
| Common Network Interface DB Consolidator (CNIDBOC) | Consolidation utility for network interface database. | **Missing**. |
| Generic Access Package (GRASP) / Ring GRASP (RGRASP) | Generic access provisioning packages. | **Missing**. |
| BROWSE | Browse utility referenced in maintenance tooling updates. | **Missing**. |
| Recent change/verify (RC/V) data model | Storage for RC/V changes beyond line/DN basics (classes, features). | **Partial** (minimal line + DN only). |
| Verification dumps / audits (dynamic/static) | Data integrity checks and audit workflows. | **Missing**. |
| Automatic Message Accounting (AMA) | AMA collection/formatting for billing records. | **Missing**. |

## Alarms/maintenance/diagnostics

| Feature domain | Description | Emulator status |
| --- | --- | --- |
| Alarm listing | Outstanding alarm listing. | **Present** (ALM:LIST). |
| Routine exercise (REX) | Routine exercises and scheduling, including OSS REX scheduler. | **Missing**. |
| Automatic REX scheduler | Automated REX scheduling. | **Missing**. |
| Automatic trunk test scheduler (ATTS) | Scheduled trunk test automation. | **Missing**. |
| Trunk/line maintenance and testing | Per-call tests, routine tests, test access units (TAU/DCTU/ROTL). | **Missing**. |
| Diagnostics + fault recovery messages | Diagnostic types and verbose fault recovery messaging. | **Missing**. |
| System log files | Log file access/display. | **Missing**. |
| Circuit pack handling/repair | Handling, spare packs, repair/return procedures, RTAG. | **Missing**. |
| OMS5 / ROP summaries | OMS5 program summaries of receive-only printer (ROP) output. | **Missing**. |
| Automatic line insulation testing (ALIT) | Line insulation testing workflows tied to repair service bureau. | **Missing**. |
| Automated Static ODD Audit (SODD) | Static audit tool for ODD. | **Missing**. |
| Test lines (108-type, BRI access) | Test line provisioning/use. | **Missing**. |
| Software debugging tools / generic utilities | Debug tooling and generic utilities (incl. IDCU/IDCULSI). | **Missing**. |

## Sources & Attribution

* `raw docs/5ESSManual1.txt` (AT&T 235-105-110 System Maintenance Requirements and Tools, Issue 7.00/7.00A/7.00B updates).
* `raw docs/Phrack43 - Guide to ESS.txt` (Phrack Magazine guide covering 5ESS architecture/terminals and AMA references).
* `raw docs/5ESS.pdf` (PDF source; text extraction not available in this environment).
* `raw docs/447699.pdf` (PDF source; text extraction not available in this environment).
* `raw docs/BSTJ_V64N06_198507_Part_2.pdf` (PDF source; text extraction not available in this environment).
* `raw docs/pacbell application.pdf` (PDF source; text extraction not available in this environment).
* `raw docs/rtrman_issue_10.pdf` (PDF source; text extraction not available in this environment).
* Placeholder: Additional Bell/AT&T/Lucent manuals and switch-specific documentation (to be added when provided).
