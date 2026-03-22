# csm_lib — ConfigServer Migration Library

[![CI](https://github.com/rfxn/csm_lib/actions/workflows/ci.yml/badge.svg)](https://github.com/rfxn/csm_lib/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](https://github.com/rfxn/csm_lib)
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

# Translate to APF/BFD/LMD
csm_translate_apf
csm_translate_bfd
csm_translate_lmd

# Apply translated values to target configs
csm_apply_all "/etc/apf/conf.apf"
csm_apply_bfd_pressure "/etc/bfd/rules/custom.conf"

# Migrate trust lists and hooks
csm_migrate_trust_allow "/etc/csf/csf.allow" "/etc/apf/allow_hosts.rules"
csm_migrate_trust_deny  "/etc/csf/csf.deny"  "/etc/apf/deny_hosts.rules"
csm_migrate_hooks "/etc/apf/scripts"

# Neutralize ConfigServer services (non-destructive)
csm_neutralize csf

# Generate migration report
csm_report_emit
csm_report_summary
```

## API Reference

### Detection

| Function | Signature | Description | Returns |
|---|---|---|---|
| `csm_detect_csf` | `csm_detect_csf` | Detect CSF via `CSM_CSF_CONF`; sets `_CSM_CSF_VERSION` | 0 found, 1 absent |
| `csm_detect_lfd` | `csm_detect_lfd` | Detect LFD binary or `LF_*` vars in CSF config | 0 found, 1 absent |
| `csm_detect_cxs` | `csm_detect_cxs` | Detect CXS via `CSM_CXS_DEFAULTS` | 0 found, 1 absent |

### Configuration Parsing

| Function | Signature | Description |
|---|---|---|
| `csm_read_var` | `csm_read_var conf_file var_name` | Read single variable from Perl-style or shell-style config; prints value |
| `csm_read_conf` | `csm_read_conf conf_file` | Bulk-read all variables into `_CSM_RAW_NAMES[]` / `_CSM_RAW_VALUES[]` |

### Translation

| Function | Signature | Description |
|---|---|---|
| `csm_translate_apf` | `csm_translate_apf` | Translate CSF→APF (~40 mapped vars); populates norm store |
| `csm_translate_bfd` | `csm_translate_bfd` | Translate LFD thresholds to BFD pressure model; populates `_CSM_BFD_RULES[]` |
| `csm_translate_lmd` | `csm_translate_lmd` | Translate CXS→LMD (~27 mapped vars); reads `cxs.defaults` + `cxswatch.conf` |

### Config Application

| Function | Signature | Description |
|---|---|---|
| `csm_apply_var` | `csm_apply_var conf_file var_name value` | Set single variable in target config (dry-run safe) |
| `csm_apply_all` | `csm_apply_all conf_file` | Apply all `status=translated` norm store entries to config |
| `csm_apply_bfd_pressure` | `csm_apply_bfd_pressure pressure_conf` | Write `PRESSURE_TRIP` overrides to BFD rule file |

### Trust List Migration

| Function | Signature | Description |
|---|---|---|
| `csm_migrate_trust_allow` | `csm_migrate_trust_allow src_file dst_file` | `csf.allow` → `allow_hosts.rules` (pipe→colon, idempotent) |
| `csm_migrate_trust_deny` | `csm_migrate_trust_deny src_file dst_file` | `csf.deny` → `deny_hosts.rules` (temp entry TTL annotation) |
| `csm_migrate_trust_sips` | `csm_migrate_trust_sips src_file dst_file` | `csf.sips` → `silent_ips.rules` (direct copy, dedup) |
| `csm_migrate_blocklists` | `csm_migrate_blocklists src_file dst_file` | `csf.blocklists` 4-field → rfxn ipset 7-field format |
| `csm_migrate_lfd_ignore` | `csm_migrate_lfd_ignore src_file dst_file` | `csf.ignore` → `allow.hosts` (direct copy, dedup) |
| `csm_migrate_cxs_ignore` | `csm_migrate_cxs_ignore ignore_file dst_dir` | CXS keyword ignore file → LMD ignore `.dat` files |

### Hook Migration

| Function | Signature | Description |
|---|---|---|
| `csm_migrate_hooks` | `csm_migrate_hooks dst_dir` | Copy `csfpre/post.sh` → `hook_pre/post.sh`; chmod 750; rewrite `/etc/csf/` paths |

### Neutralization

| Function | Signature | Description |
|---|---|---|
| `csm_neutralize` | `csm_neutralize product [cron_dir]` | Stop+disable service, chmod 000 crons and executables (dry-run safe) |

### Reporting

| Function | Signature | Description |
|---|---|---|
| `csm_report_add` | `csm_report_add line` | Append a line to the internal report buffer |
| `csm_report_emit` | `csm_report_emit` | Write structured report to `CSM_REPORT_FILE` (or stdout if unset) |
| `csm_report_summary` | `csm_report_summary` | Print one-line summary: `Translated: N \| Gaps: N \| ...` |

### Utility

| Function | Signature | Description |
|---|---|---|
| `csm_reset` | `csm_reset` | Clear all state arrays for re-use across products |

### Report Format

`csm_report_emit` produces a human-readable report with sections for translated
variables, gaps, unmapped vars, trust list migration, hooks, neutralization, and
rollback commands. The final line is machine-parseable:

```
CSM_RESULT:translated=N:gaps=N:captured=N:trust=N:hooks=N:neutralized=N
```

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
