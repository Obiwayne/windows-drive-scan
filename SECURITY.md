# Security

This skill is read only by design: `scan.ps1` reads file sizes and dates and writes only its own report, on this PC. A simple automated check (`tests\check-readonly.ps1`) runs on every change and fails if the script gains a known command that could delete, move or download, if another script file appears, or if the files no longer match `SHA256SUMS.txt`. It is a guard, not a guarantee, so every change is also reviewed by hand.

Only the maintainers can change this repository. Anyone can copy it and change their own copy, so download only from this repository or its Releases page, and check the hash as the README shows.

## Reporting a problem

Please report security problems privately, not in a public issue: use GitHub's "Report a vulnerability" button on the Security tab, or email hello@repoquarry.dev. We aim to reply within 7 days.
