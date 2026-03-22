# csm_lib — ConfigServer Migration Library

[![CI](https://github.com/rfxn/csm_lib/actions/workflows/ci.yml/badge.svg)](https://github.com/rfxn/csm_lib/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/rfxn/csm_lib)
[![Bash](https://img.shields.io/badge/bash-4.1%2B-green.svg)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-GPL%20v2-orange.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

A standalone shared Bash library for detecting and migrating ConfigServer products
(CSF, LFD, CXS) to rfxn equivalents (APF, BFD, LMD). Provides detection, config
parsing, variable translation, trust list migration, hook migration, non-destructive
neutralization, and structured migration reports.

Consumed by [APF](https://github.com/rfxn/advanced-policy-firewall),
[BFD](https://github.com/rfxn/linux-brute-force-detection), and
[LMD](https://github.com/rfxn/linux-malware-detect) via source inclusion.

## Features

- **CSF/LFD/CXS detection** — config file and binary presence checks
- **Perl-style and shell-style config parser** — handles both CSF and CXS formats
- **CSF→APF variable translation** — ~40 mapped variables, data-driven tables
- **LFD→BFD pressure model translation** — threshold-to-trip formula
- **CXS→LMD variable translation** — ~30 mapped variables, multi-file scan
- **Trust list migration** — allow, deny, silent IPs, blocklists to rfxn format
- **Hook script migration** — copy, chmod 750, path rewrite for pre/post hooks
- **CXS ignore file translation** — converts CXS ignore entries to LMD format
- **Non-destructive neutralization** — disables services, crons, executables safely
- **Full dry-run mode** via `CSM_DRY_RUN=1` — no filesystem writes
- **Structured migration report** — machine-parseable `CSM_RESULT` output lines
- **Full variable normalization** — all vars captured even without a mapping
- **Zero project-specific references** — all context via `CSM_*` environment variables
- **Bash 4.1+ compatible** — runs on CentOS 6 through Rocky 9/Debian 12

## Platform Support

| Distribution | Versions | Bash |
|---|---|---|
| CentOS | 6, 7 | 4.1, 4.2 |
| Rocky Linux | 8, 9 | 4.4, 5.1 |
| Debian | 12 | 5.2 |
| Ubuntu | 20.04, 24.04 | 5.0, 5.2 |
| Slackware, Gentoo, FreeBSD | Various | 4.1+ |

**Minimum requirement: Bash 4.1** (CentOS 6, 2011). Hard dependency on
[pkg_lib](https://github.com/rfxn/pkg_lib).

## Quick Start

```bash
# Source dependencies
source /opt/myapp/lib/pkg_lib.sh
source /opt/myapp/lib/csm_lib.sh

# Optional: override config paths (default: /etc/csf/, /etc/cxs/)
CSM_CSF_CONF="/etc/csf/csf.conf"
CSM_REPORT_FILE="/var/log/myapp/csm-migration.log"

# Detect what's installed
csm_detect_csf && echo "CSF detected"
csm_detect_cxs && echo "CXS detected"

# Read and normalize CSF configuration
csm_read_conf
csm_normalize_csf

# Translate to APF/BFD
csm_translate_apf
csm_translate_bfd

# Migrate trust lists and hooks
csm_migrate_trust
csm_migrate_hooks

# Neutralize ConfigServer services (non-destructive)
csm_neutralize

# Generate migration report
csm_report
```

## API Reference

### Detection

| Function | Description | Returns |
|---|---|---|
| `csm_detect_csf` | Detect CSF via config file | 0 if found, 1 if not |
| `csm_detect_lfd` | Detect LFD daemon | 0 if found, 1 if not |
| `csm_detect_cxs` | Detect CXS via config file | 0 if found, 1 if not |

### Configuration Parsing

| Function | Description |
|---|---|
| `csm_read_var VAR FILE` | Read single variable from Perl-style or shell-style config |
| `csm_read_conf` | Read all variables from `CSM_CSF_CONF` into `_CSM_RAW_*` arrays |

### Translation

| Function | Description |
|---|---|
| `csm_translate_apf` | Translate CSF variables to APF equivalents |
| `csm_translate_bfd` | Translate LFD thresholds to BFD pressure model |
| `csm_translate_lmd` | Translate CXS variables to LMD equivalents |

### Migration

| Function | Description |
|---|---|
| `csm_migrate_trust` | Migrate allow/deny/sips/blocklist entries |
| `csm_migrate_hooks` | Copy and rewrite pre/post hook scripts |

### Neutralization and Reporting

| Function | Description |
|---|---|
| `csm_neutralize` | Non-destructively disable ConfigServer services/crons |
| `csm_report` | Write structured migration report to `CSM_REPORT_FILE` |
| `csm_reset` | Clear all state arrays for re-use |

## Configuration Variables

| Variable | Default | Description |
|---|---|---|
| `CSM_CSF_CONF` | `/etc/csf/csf.conf` | Path to CSF configuration file |
| `CSM_CSF_DIR` | `/etc/csf` | CSF configuration directory |
| `CSM_CXS_DIR` | `/etc/cxs` | CXS configuration directory |
| `CSM_CXS_DEFAULTS` | `/etc/cxs/cxs.defaults` | CXS defaults file |
| `CSM_CXS_WATCHCONF` | `/etc/cxs/cxswatch.conf` | CXS watch configuration |
| `CSM_REPORT_FILE` | `` (empty) | Migration report output path |
| `CSM_DRY_RUN` | `0` | Set to `1` for dry-run (no filesystem writes) |

## License

GNU General Public License v2. See [COPYING.GPL](COPYING.GPL).

Copyright (C) 2026 R-fx Networks &lt;proj@rfxn.com&gt;
