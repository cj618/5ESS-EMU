# Research index

This file tracks source material used to guide 5ESS-EMU. It should separate
technical documentation from secondary reporting, folklore and atmosphere.

Do not copy long passages from manuals into this tree. Convert research into
implementation notes, command references, example transcripts and clearly
marked simulated data.

## Source classes

| Class | Meaning |
| --- | --- |
| PRIMARY | Official manuals, technical papers, legal records or vendor documentation. |
| SECONDARY | Books, reputable articles, retrospectives and technical histories. |
| LORE | Zines, BBS posts, anecdotes and culture memory. |
| INSPIRATION | Aesthetic references that are not factual authority. |

## Implementation confidence

| Label | Meaning |
| --- | --- |
| DOCUMENTED | Based on identifiable technical documentation. |
| PLAUSIBLE | Inferred from related systems or operational practice. |
| FICTIONAL | Invented for the simulator. |
| ATMOSPHERIC | Included for period flavour only. |

## Current local sources

| Source | Class | Notes |
| --- | --- | --- |
| `raw docs/5ESS.pdf` | PRIMARY/REFERENCE | Historical 5ESS source material. Use to guide terminology and screen behaviour, not as BSD-licensed project text. |
| `raw docs/5ESSManual1.txt` | PRIMARY/REFERENCE | Extracted text reference. Needs review and indexing before feature work relies on it. |

## Research targets

* AT&T/Lucent 5ESS craft and operations documentation.
* 5ESS architecture material: AM, CM, SM, OAMP, craft terminals and maintenance workflows.
* Bell System and Pacific Bell operations culture.
* Period Unix, Perl and CGI deployment practices.
* 1990s phone culture and reporting as atmosphere only.
* Public reporting from the Mitnick era as cultural context, not operational instruction.

## Safety boundary

The simulator may evoke telco culture and 1990s lore, but must not include
real-world access procedures, real credentials, real dial-in numbers, real
bypass methods or instructions for abusing telecommunications systems.
