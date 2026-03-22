#!/bin/bash
#
# csm_lib.sh — ConfigServer Migration Library 1.0.0
###
# Copyright (C) 2026 R-fx Networks <proj@rfxn.com>
#                     Ryan MacDonald <ryan@rfxn.com>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
###
#
# Shared ConfigServer migration library for rfxn projects.
# Source this file to access CSF/LFD/CXS detection, translation, and migration.
# No project-specific code — all behavior controlled via CSM_* variables.

# Source guard — safe for repeated sourcing
[[ -n "${_CSM_LIB_LOADED:-}" ]] && return 0 2>/dev/null  # suppresses "return outside function" when script is executed directly
_CSM_LIB_LOADED=1

# Hard require pkg_lib
if [[ -z "${_PKG_LIB_LOADED:-}" ]]; then
    echo "csm_lib: FATAL: pkg_lib must be sourced before csm_lib" >&2
    # shellcheck disable=SC2317  # exit 1 reachable when script is executed (not sourced)
    return 1 2>/dev/null || exit 1  # suppresses "return outside function" when executed directly
fi

# shellcheck disable=SC2034
CSM_LIB_VERSION="1.0.0"

# --- Configuration variables (set by consumer before sourcing) ---
CSM_CSF_CONF="${CSM_CSF_CONF:-/etc/csf/csf.conf}"
CSM_CSF_DIR="${CSM_CSF_DIR:-/etc/csf}"
CSM_CXS_DIR="${CSM_CXS_DIR:-/etc/cxs}"
CSM_CXS_DEFAULTS="${CSM_CXS_DEFAULTS:-/etc/cxs/cxs.defaults}"
CSM_CXS_WATCHCONF="${CSM_CXS_WATCHCONF:-/etc/cxs/cxswatch.conf}"
CSM_REPORT_FILE="${CSM_REPORT_FILE:-}"
CSM_DRY_RUN="${CSM_DRY_RUN:-0}"

# --- Internal state (parallel indexed arrays) ---
_CSM_RAW_NAMES=()
_CSM_RAW_VALUES=()
_CSM_NORM_NAMES=()
_CSM_NORM_VALUES=()
_CSM_NORM_STATUS=()
_CSM_NORM_TARGET=()
_CSM_BFD_RULES=()
_CSM_BFD_TRIPS=()
_CSM_REPORT_LINES=()
_CSM_NEUTRALIZE_LOG=()
_CSM_CXS_IGNORE_TYPES=()
_CSM_CXS_IGNORE_VALUES=()

# --- Detection state ---
_CSM_CSF_VERSION=""
_CSM_LFD_FOUND=0
_CSM_CXS_FOUND=0

# ---------------------------------------------------------------------------
# csm_reset — clear all state arrays for re-use across products
# ---------------------------------------------------------------------------
csm_reset() {
    _CSM_RAW_NAMES=()
    _CSM_RAW_VALUES=()
    _CSM_NORM_NAMES=()
    _CSM_NORM_VALUES=()
    _CSM_NORM_STATUS=()
    _CSM_NORM_TARGET=()
    _CSM_BFD_RULES=()
    _CSM_BFD_TRIPS=()
    _CSM_REPORT_LINES=()
    _CSM_NEUTRALIZE_LOG=()
    _CSM_CXS_IGNORE_TYPES=()
    _CSM_CXS_IGNORE_VALUES=()
    _CSM_CSF_VERSION=""
    _CSM_LFD_FOUND=0
    _CSM_CXS_FOUND=0
}

# ---------------------------------------------------------------------------
# Section 1: Detection
# ---------------------------------------------------------------------------

# csm_detect_csf — check for CSF config and binary
# Returns: 0 if CSF detected, 1 if absent
# Sets: _CSM_CSF_VERSION
csm_detect_csf() {
    if [[ ! -f "$CSM_CSF_CONF" ]]; then
        return 1
    fi
    local ver
    ver=$(csm_read_var "$CSM_CSF_CONF" "VERSION")
    _CSM_CSF_VERSION="${ver:-unknown}"
    return 0
}

# csm_detect_lfd — check for LFD binary (co-resident with CSF)
# Returns: 0 if LFD detected, 1 if absent
csm_detect_lfd() {
    if command -v lfd >/dev/null 2>&1; then  # lfd binary exists
        _CSM_LFD_FOUND=1
        return 0
    fi
    # LFD is co-resident with CSF — check CSF config for LF_ vars
    if [[ -f "$CSM_CSF_CONF" ]]; then
        local lf_val
        lf_val=$(csm_read_var "$CSM_CSF_CONF" "LF_SSHD")
        if [[ -n "$lf_val" ]]; then
            _CSM_LFD_FOUND=1
            return 0
        fi
    fi
    return 1
}

# csm_detect_cxs — check for CXS config and binary
# Returns: 0 if CXS detected, 1 if absent
csm_detect_cxs() {
    if [[ ! -f "$CSM_CXS_DEFAULTS" ]]; then
        return 1
    fi
    _CSM_CXS_FOUND=1
    return 0
}

# ---------------------------------------------------------------------------
# Section 2: Config Parsing
# ---------------------------------------------------------------------------

# csm_read_var — read single variable from config file
# Handles both Perl-style (VAR = "val") and shell-style (VAR="val")
# Args: $1=conf_file  $2=var_name
# Prints: value (stripped of quotes)
# Returns: 0 if found, 1 if not found or file missing
csm_read_var() {
    local conf_file="$1" var_name="$2"
    [[ -z "$conf_file" || -z "$var_name" ]] && return 1
    [[ ! -f "$conf_file" ]] && return 1
    awk -v var="$var_name" '
    { gsub(/\r$/, "", $0) }   # strip CRLF
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
        # Match VAR = "val" or VAR="val" or VAR = val
        if (match($0, "^[[:space:]]*" var "[[:space:]]*=[[:space:]]*")) {
            val = substr($0, RSTART + RLENGTH)
            # Strip leading/trailing quotes
            gsub(/^["'"'"']|["'"'"']$/, "", val)
            # Strip trailing comments (only if preceded by whitespace+#)
            sub(/[[:space:]]+#.*$/, "", val)
            print val
            found = 1
            exit
        }
    }
    END { exit (found ? 0 : 1) }
    ' "$conf_file"
}

# csm_read_conf — bulk-read all variables from config file
# Populates: _CSM_RAW_NAMES[], _CSM_RAW_VALUES[]
# Args: $1=conf_file
# Returns: 0 on success, 1 on error
csm_read_conf() {
    local conf_file="$1"
    [[ -z "$conf_file" || ! -f "$conf_file" ]] && return 1
    _CSM_RAW_NAMES=()
    _CSM_RAW_VALUES=()
    local line name val
    local var_pat='^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)'
    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        # Match VAR = "val" or VAR="val"
        if [[ "$line" =~ $var_pat ]]; then
            name="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            # Strip quotes
            val="${val#\"}"
            val="${val%\"}"
            val="${val#\'}"
            val="${val%\'}"
            # Strip trailing comment
            val="${val%%[[:space:]]#*}"
            _CSM_RAW_NAMES+=("$name")
            _CSM_RAW_VALUES+=("$val")
        fi
    done < <(sed 's/\r$//' "$conf_file")  # strip CRLF
}

# _csm_read_cxs_ignore — parse CXS keyword-based ignore file
# Populates: _CSM_CXS_IGNORE_TYPES[], _CSM_CXS_IGNORE_VALUES[]
# Args: $1=ignore_file
_csm_read_cxs_ignore() {
    local ignore_file="$1"
    [[ -z "$ignore_file" || ! -f "$ignore_file" ]] && return 1
    _CSM_CXS_IGNORE_TYPES=()
    _CSM_CXS_IGNORE_VALUES=()
    local line ktype kval
    while IFS= read -r line; do
        line="${line%%[[:space:]]#*}"  # strip trailing comment
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        if [[ "$line" == *:* ]]; then
            ktype="${line%%:*}"
            kval="${line#*:}"
            _CSM_CXS_IGNORE_TYPES+=("$ktype")
            _CSM_CXS_IGNORE_VALUES+=("$kval")
        fi
    done < "$ignore_file"
}

# ---------------------------------------------------------------------------
# Section 3: Normalization Store
# ---------------------------------------------------------------------------

# _csm_norm_add — add entry to normalized store
# Args: $1=src_name  $2=src_value  $3=status  $4=target
_csm_norm_add() {
    local src_name="$1" src_value="$2" status="$3" target="${4:-}"
    _CSM_NORM_NAMES+=("$src_name")
    _CSM_NORM_VALUES+=("$src_value")
    _CSM_NORM_STATUS+=("$status")
    _CSM_NORM_TARGET+=("$target")
}

# _csm_norm_find — find index of entry by source name
# Sets: _CSM_NORM_RESULT (index or -1)
# Args: $1=src_name
_csm_norm_find() {
    local src_name="$1" i
    _CSM_NORM_RESULT=-1
    for i in "${!_CSM_NORM_NAMES[@]}"; do
        if [[ "${_CSM_NORM_NAMES[$i]}" == "$src_name" ]]; then
            _CSM_NORM_RESULT="$i"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Section 4: CSF→APF Translation
# ---------------------------------------------------------------------------

# Internal transform state
_CSM_XFM_RESULT=""
_CSM_XFM_SIDE_EFFECTS=()

# Mapping table arrays (populated by _csm_map_apf_init)
_CSM_MAP_APF_SRC=()
_CSM_MAP_APF_DST=()
_CSM_MAP_APF_XFM=()

# _csm_xfm_apply — apply a single transform to a value
# Args: $1=transform_type  $2=src_value  $3=dst_var_name
# Sets: _CSM_XFM_RESULT (transformed value)
#       _CSM_XFM_SIDE_EFFECTS (array of "VAR=value" pairs for compound transforms)
_csm_xfm_apply() {
    local xfm="$1" val="$2" dst="$3"
    _CSM_XFM_RESULT=""
    _CSM_XFM_SIDE_EFFECTS=()

    case "$xfm" in
        direct)
            _CSM_XFM_RESULT="$val"
            ;;
        direct+egf)
            _CSM_XFM_RESULT="$val"
            _CSM_XFM_SIDE_EFFECTS+=("EGF=1")
            ;;
        direct+rgt)
            _CSM_XFM_RESULT="$val"
            _CSM_XFM_SIDE_EFFECTS+=("RGT=1")
            ;;
        append_s)
            # Append /s only if not already present
            if [[ "$val" == *"/s" ]]; then
                _CSM_XFM_RESULT="$val"
            else
                _CSM_XFM_RESULT="${val}/s"
            fi
            ;;
        sep_semi_colon)
            # Replace all ";" with ":" in delimiter
            local rep=":"
            _CSM_XFM_RESULT="${val//;/$rep}"
            ;;
        expand_drop)
            # Expand DROP value to TCP_STOP, UDP_STOP, ALL_STOP — stored via side effects
            # _CSM_XFM_RESULT carries the value; caller handles multi-target
            _CSM_XFM_RESULT="$val"
            ;;
        parse_rate)
            # Extract numeric part from rate string (e.g. "1/s" → "1")
            local numeric_pat='^([0-9]+)'
            if [[ "$val" =~ $numeric_pat ]]; then
                _CSM_XFM_RESULT="${BASH_REMATCH[1]}"
            else
                _CSM_XFM_RESULT="$val"
            fi
            ;;
        gap)
            # No translation — record target version string as-is
            _CSM_XFM_RESULT="$val"
            ;;
        log_bfd)
            # LFD feature — redirect to BFD, value preserved
            _CSM_XFM_RESULT="$val"
            ;;
        *)
            # Unknown transform — pass value through
            _CSM_XFM_RESULT="$val"
            ;;
    esac
}

# _csm_map_apf_init — populate CSF→APF mapping table
# Populates: _CSM_MAP_APF_SRC[], _CSM_MAP_APF_DST[], _CSM_MAP_APF_XFM[]
_csm_map_apf_init() {
    # Format: SRC (CSF var) | DST (APF var) | XFM (transform type)
    _CSM_MAP_APF_SRC=(); _CSM_MAP_APF_DST=(); _CSM_MAP_APF_XFM=()
    # --- Port Filtering ---
    _CSM_MAP_APF_SRC+=("TCP_IN");        _CSM_MAP_APF_DST+=("IG_TCP_CPORTS");  _CSM_MAP_APF_XFM+=("direct")
    _CSM_MAP_APF_SRC+=("TCP_OUT");       _CSM_MAP_APF_DST+=("EG_TCP_CPORTS");  _CSM_MAP_APF_XFM+=("direct+egf")
    _CSM_MAP_APF_SRC+=("UDP_IN");        _CSM_MAP_APF_DST+=("IG_UDP_CPORTS");  _CSM_MAP_APF_XFM+=("direct")
    _CSM_MAP_APF_SRC+=("UDP_OUT");       _CSM_MAP_APF_DST+=("EG_UDP_CPORTS");  _CSM_MAP_APF_XFM+=("direct+egf")
    # --- Network Settings ---
    _CSM_MAP_APF_SRC+=("ETH_DEVICE");    _CSM_MAP_APF_DST+=("IFACE_UNTRUSTED"); _CSM_MAP_APF_XFM+=("direct")
    _CSM_MAP_APF_SRC+=("ETH_DEVICE_SKIP"); _CSM_MAP_APF_DST+=("IFACE_TRUSTED"); _CSM_MAP_APF_XFM+=("direct")
    _CSM_MAP_APF_SRC+=("IPV6");          _CSM_MAP_APF_DST+=("USE_IPV6");       _CSM_MAP_APF_XFM+=("direct")
    _CSM_MAP_APF_SRC+=("DOCKER");        _CSM_MAP_APF_DST+=("DOCKER_COMPAT");  _CSM_MAP_APF_XFM+=("direct")
    # --- Protection Features ---
    _CSM_MAP_APF_SRC+=("SYNFLOOD");      _CSM_MAP_APF_DST+=("SYNFLOOD");       _CSM_MAP_APF_XFM+=("direct")
    _CSM_MAP_APF_SRC+=("SYNFLOOD_RATE"); _CSM_MAP_APF_DST+=("SYNFLOOD_RATE");  _CSM_MAP_APF_XFM+=("append_s")
    _CSM_MAP_APF_SRC+=("SYNFLOOD_BURST"); _CSM_MAP_APF_DST+=("SYNFLOOD_BURST"); _CSM_MAP_APF_XFM+=("direct")
    _CSM_MAP_APF_SRC+=("PACKET_FILTER"); _CSM_MAP_APF_DST+=("PKT_SANITY");    _CSM_MAP_APF_XFM+=("direct")
    _CSM_MAP_APF_SRC+=("ICMP_IN_RATE");  _CSM_MAP_APF_DST+=("ICMP_LIM");      _CSM_MAP_APF_XFM+=("parse_rate")
    _CSM_MAP_APF_SRC+=("CONNLIMIT");     _CSM_MAP_APF_DST+=("IG_TCP_CLIMIT"); _CSM_MAP_APF_XFM+=("sep_semi_colon")
    # --- SMTP ---
    _CSM_MAP_APF_SRC+=("SMTP_BLOCK");    _CSM_MAP_APF_DST+=("SMTP_BLOCK");    _CSM_MAP_APF_XFM+=("direct")
    _CSM_MAP_APF_SRC+=("SMTP_ALLOWUSER"); _CSM_MAP_APF_DST+=("SMTP_ALLOWUSER"); _CSM_MAP_APF_XFM+=("direct")
    _CSM_MAP_APF_SRC+=("SMTP_ALLOWGROUP"); _CSM_MAP_APF_DST+=("SMTP_ALLOWGROUP"); _CSM_MAP_APF_XFM+=("direct")
    # --- Deny/Expiry/Misc ---
    _CSM_MAP_APF_SRC+=("DENY_IP_LIMIT"); _CSM_MAP_APF_DST+=("SET_TRIM");      _CSM_MAP_APF_XFM+=("direct")
    _CSM_MAP_APF_SRC+=("LF_IPSET");      _CSM_MAP_APF_DST+=("USE_IPSET");     _CSM_MAP_APF_XFM+=("direct")
    _CSM_MAP_APF_SRC+=("TESTING");       _CSM_MAP_APF_DST+=("DEVEL_MODE");    _CSM_MAP_APF_XFM+=("direct")
    _CSM_MAP_APF_SRC+=("FASTSTART");     _CSM_MAP_APF_DST+=("SET_FASTLOAD");  _CSM_MAP_APF_XFM+=("direct")
    _CSM_MAP_APF_SRC+=("DROP");          _CSM_MAP_APF_DST+=("TCP_STOP,UDP_STOP,ALL_STOP"); _CSM_MAP_APF_XFM+=("expand_drop")
    _CSM_MAP_APF_SRC+=("DROP_LOGGING");  _CSM_MAP_APF_DST+=("LOG_DROP");      _CSM_MAP_APF_XFM+=("direct")
    _CSM_MAP_APF_SRC+=("GLOBAL_ALLOW");  _CSM_MAP_APF_DST+=("GA_URL");        _CSM_MAP_APF_XFM+=("direct+rgt")
    _CSM_MAP_APF_SRC+=("GLOBAL_DENY");   _CSM_MAP_APF_DST+=("GD_URL");        _CSM_MAP_APF_XFM+=("direct+rgt")
    _CSM_MAP_APF_SRC+=("WAITLOCK");      _CSM_MAP_APF_DST+=("IPT_LOCK_TIMEOUT"); _CSM_MAP_APF_XFM+=("direct")
    # --- Gap Variables (known CSF features, no APF equivalent yet) ---
    _CSM_MAP_APF_SRC+=("PORTFLOOD");     _CSM_MAP_APF_DST+=("planned APF 2.1.0"); _CSM_MAP_APF_XFM+=("gap")
    _CSM_MAP_APF_SRC+=("UDPFLOOD");      _CSM_MAP_APF_DST+=("planned APF 2.1.0"); _CSM_MAP_APF_XFM+=("gap")
    _CSM_MAP_APF_SRC+=("UDPFLOOD_LIMIT"); _CSM_MAP_APF_DST+=("planned APF 2.1.0"); _CSM_MAP_APF_XFM+=("gap")
    _CSM_MAP_APF_SRC+=("UDPFLOOD_BURST"); _CSM_MAP_APF_DST+=("planned APF 2.1.0"); _CSM_MAP_APF_XFM+=("gap")
    _CSM_MAP_APF_SRC+=("UDPFLOOD_ALLOWUSER"); _CSM_MAP_APF_DST+=("planned APF 2.1.0"); _CSM_MAP_APF_XFM+=("gap")
    _CSM_MAP_APF_SRC+=("CC_DENY");       _CSM_MAP_APF_DST+=("planned APF 2.2.0"); _CSM_MAP_APF_XFM+=("gap")
    _CSM_MAP_APF_SRC+=("CC_ALLOW");      _CSM_MAP_APF_DST+=("planned APF 2.2.0"); _CSM_MAP_APF_XFM+=("gap")
    # --- LFD features (redirect to BFD) ---
    _CSM_MAP_APF_SRC+=("LF_SSHD");       _CSM_MAP_APF_DST+=("LFD feature → see BFD"); _CSM_MAP_APF_XFM+=("log_bfd")
    _CSM_MAP_APF_SRC+=("LF_FTPD");       _CSM_MAP_APF_DST+=("LFD feature → see BFD"); _CSM_MAP_APF_XFM+=("log_bfd")
    _CSM_MAP_APF_SRC+=("LF_SMTPAUTH");   _CSM_MAP_APF_DST+=("LFD feature → see BFD"); _CSM_MAP_APF_XFM+=("log_bfd")
    _CSM_MAP_APF_SRC+=("LF_POP3D");      _CSM_MAP_APF_DST+=("LFD feature → see BFD"); _CSM_MAP_APF_XFM+=("log_bfd")
    _CSM_MAP_APF_SRC+=("LF_IMAPD");      _CSM_MAP_APF_DST+=("LFD feature → see BFD"); _CSM_MAP_APF_XFM+=("log_bfd")
    _CSM_MAP_APF_SRC+=("LF_TRIGGER_PERM"); _CSM_MAP_APF_DST+=("LFD feature → see BFD"); _CSM_MAP_APF_XFM+=("log_bfd")
    _CSM_MAP_APF_SRC+=("LF_ALERT_TO");   _CSM_MAP_APF_DST+=("LFD feature → see BFD"); _CSM_MAP_APF_XFM+=("log_bfd")
}

# csm_translate_apf — translate CSF config to APF equivalents
# 1. Reads raw config from CSM_CSF_CONF
# 2. Applies mapping table transforms
# 3. Normalization pass: any unmapped var gets status "unmapped"
# Sets: _CSM_NORM_NAMES[], _CSM_NORM_VALUES[], _CSM_NORM_STATUS[], _CSM_NORM_TARGET[]
# Returns: 0 on success, 1 if config file missing
csm_translate_apf() {
    # Reset norm store for re-entry safety
    _CSM_NORM_NAMES=()
    _CSM_NORM_VALUES=()
    _CSM_NORM_STATUS=()
    _CSM_NORM_TARGET=()

    csm_read_conf "$CSM_CSF_CONF" || return 1
    _csm_map_apf_init

    # Build a lookup: which raw var names have been consumed by a mapping
    local -a _mapped_srcs=()
    local mi raw_val raw_idx xfm dst

    for mi in "${!_CSM_MAP_APF_SRC[@]}"; do
        local src="${_CSM_MAP_APF_SRC[$mi]}"
        dst="${_CSM_MAP_APF_DST[$mi]}"
        xfm="${_CSM_MAP_APF_XFM[$mi]}"

        # Find this src var in the raw array
        raw_val=""
        raw_idx=-1
        local ri
        for ri in "${!_CSM_RAW_NAMES[@]}"; do
            if [[ "${_CSM_RAW_NAMES[$ri]}" == "$src" ]]; then
                raw_val="${_CSM_RAW_VALUES[$ri]}"
                raw_idx="$ri"
                break
            fi
        done

        # Skip mapping entry if src var not present in the config
        [[ "$raw_idx" -eq -1 ]] && continue

        _mapped_srcs+=("$src")

        # Apply transform
        _csm_xfm_apply "$xfm" "$raw_val" "$dst"

        case "$xfm" in
            gap)
                _csm_norm_add "$src" "$raw_val" "gap" "$dst"
                ;;
            log_bfd)
                _csm_norm_add "$src" "$raw_val" "log_bfd" "$dst"
                ;;
            expand_drop)
                # Expand one source var to three destination vars
                local t
                for t in TCP_STOP UDP_STOP ALL_STOP; do
                    _csm_norm_add "$t" "$_CSM_XFM_RESULT" "translated" "$t"
                done
                ;;
            direct+egf|direct+rgt)
                _csm_norm_add "$src" "$_CSM_XFM_RESULT" "translated" "$dst"
                # Add side-effect entries
                local se
                for se in "${_CSM_XFM_SIDE_EFFECTS[@]}"; do
                    local se_var="${se%%=*}"
                    local se_val="${se#*=}"
                    _csm_norm_add "$se_var" "$se_val" "translated" "$se_var"
                done
                ;;
            *)
                _csm_norm_add "$src" "$_CSM_XFM_RESULT" "translated" "$dst"
                ;;
        esac
    done

    # Normalization pass: any raw var not in the mapping table → unmapped
    local rn
    for rn in "${!_CSM_RAW_NAMES[@]}"; do
        local rname="${_CSM_RAW_NAMES[$rn]}"
        local found=0
        local ms
        for ms in "${_mapped_srcs[@]}"; do
            if [[ "$ms" == "$rname" ]]; then
                found=1
                break
            fi
        done
        if [[ "$found" -eq 0 ]]; then
            _csm_norm_add "$rname" "${_CSM_RAW_VALUES[$rn]}" "unmapped" ""
        fi
    done

    return 0
}

# ---------------------------------------------------------------------------
# Section 5: LFD→BFD Translation
# ---------------------------------------------------------------------------

# Mapping table arrays (populated by _csm_map_bfd_init)
# Type "pressure": trip = min(trigger * 3, 200)
# Type "direct":   trip = raw value verbatim
# Type "fixed":    trip = fixed string override (ignores CSF value)
_CSM_MAP_BFD_LF=()
_CSM_MAP_BFD_RULE=()
_CSM_MAP_BFD_TYPE=()
_CSM_MAP_BFD_FIXED=()

# _csm_map_bfd_init — populate LFD→BFD mapping table
# Populates: _CSM_MAP_BFD_LF[], _CSM_MAP_BFD_RULE[], _CSM_MAP_BFD_TYPE[], _CSM_MAP_BFD_FIXED[]
_csm_map_bfd_init() {
    _CSM_MAP_BFD_LF=(); _CSM_MAP_BFD_RULE=(); _CSM_MAP_BFD_TYPE=(); _CSM_MAP_BFD_FIXED=()
    # Format: LF_VAR | BFD_RULE | type | fixed_value (empty unless type=fixed)

    # --- Pressure formula: trip = min(trigger * 3, 200) ---
    _CSM_MAP_BFD_LF+=("LF_SSHD");        _CSM_MAP_BFD_RULE+=("SSHD");             _CSM_MAP_BFD_TYPE+=("pressure"); _CSM_MAP_BFD_FIXED+=("")
    _CSM_MAP_BFD_LF+=("LF_FTPD");        _CSM_MAP_BFD_RULE+=("FTPD");             _CSM_MAP_BFD_TYPE+=("pressure"); _CSM_MAP_BFD_FIXED+=("")
    _CSM_MAP_BFD_LF+=("LF_SMTPAUTH");    _CSM_MAP_BFD_RULE+=("SMTPAUTH");         _CSM_MAP_BFD_TYPE+=("pressure"); _CSM_MAP_BFD_FIXED+=("")
    _CSM_MAP_BFD_LF+=("LF_POP3D");       _CSM_MAP_BFD_RULE+=("POP3D");            _CSM_MAP_BFD_TYPE+=("pressure"); _CSM_MAP_BFD_FIXED+=("")
    _CSM_MAP_BFD_LF+=("LF_IMAPD");       _CSM_MAP_BFD_RULE+=("IMAPD");            _CSM_MAP_BFD_TYPE+=("pressure"); _CSM_MAP_BFD_FIXED+=("")
    _CSM_MAP_BFD_LF+=("LF_CPANEL");      _CSM_MAP_BFD_RULE+=("CPANEL");           _CSM_MAP_BFD_TYPE+=("pressure"); _CSM_MAP_BFD_FIXED+=("")
    _CSM_MAP_BFD_LF+=("LF_MODSEC");      _CSM_MAP_BFD_RULE+=("MODSEC");           _CSM_MAP_BFD_TYPE+=("pressure"); _CSM_MAP_BFD_FIXED+=("")
    _CSM_MAP_BFD_LF+=("LF_DIRECTADMIN"); _CSM_MAP_BFD_RULE+=("DIRECTADMIN");      _CSM_MAP_BFD_TYPE+=("pressure"); _CSM_MAP_BFD_FIXED+=("")

    # --- Direct mappings: trip = raw value verbatim ---
    _CSM_MAP_BFD_LF+=("LF_TRIGGER_PERM");       _CSM_MAP_BFD_RULE+=("BAN_TTL");             _CSM_MAP_BFD_TYPE+=("direct");   _CSM_MAP_BFD_FIXED+=("")
    _CSM_MAP_BFD_LF+=("LF_ALERT_TO");           _CSM_MAP_BFD_RULE+=("EMAIL_ADDRESS");       _CSM_MAP_BFD_TYPE+=("direct");   _CSM_MAP_BFD_FIXED+=("")
    _CSM_MAP_BFD_LF+=("LF_PERMBLOCK_COUNT");    _CSM_MAP_BFD_RULE+=("BAN_ESCALATE_AFTER");  _CSM_MAP_BFD_TYPE+=("direct");   _CSM_MAP_BFD_FIXED+=("")
    _CSM_MAP_BFD_LF+=("LF_PERMBLOCK_INTERVAL"); _CSM_MAP_BFD_RULE+=("BAN_ESCALATE_WINDOW"); _CSM_MAP_BFD_TYPE+=("direct");   _CSM_MAP_BFD_FIXED+=("")
    _CSM_MAP_BFD_LF+=("LF_NETBLOCK");           _CSM_MAP_BFD_RULE+=("SUBNET_TRIG");         _CSM_MAP_BFD_TYPE+=("direct");   _CSM_MAP_BFD_FIXED+=("")

    # --- Fixed mapping: LF_SELECT always outputs "apf" (APF is the target firewall) ---
    _CSM_MAP_BFD_LF+=("LF_SELECT");             _CSM_MAP_BFD_RULE+=("FIREWALL");            _CSM_MAP_BFD_TYPE+=("fixed");    _CSM_MAP_BFD_FIXED+=("apf")
}

# csm_translate_bfd — translate LFD config to BFD equivalents
# Reads LF_* vars from CSM_CSF_CONF (LFD config lives in csf.conf)
# Applies pressure formula or direct mapping per table entry
# Populates: _CSM_BFD_RULES[], _CSM_BFD_TRIPS[]
# Returns: 0 on success, 1 if config file missing
csm_translate_bfd() {
    # Reset BFD arrays for re-entry safety
    _CSM_BFD_RULES=()
    _CSM_BFD_TRIPS=()

    [[ ! -f "$CSM_CSF_CONF" ]] && return 1

    _csm_map_bfd_init

    local mi lf_var rule_name map_type fixed_val
    local trigger trip val

    for mi in "${!_CSM_MAP_BFD_LF[@]}"; do
        lf_var="${_CSM_MAP_BFD_LF[$mi]}"
        rule_name="${_CSM_MAP_BFD_RULE[$mi]}"
        map_type="${_CSM_MAP_BFD_TYPE[$mi]}"
        fixed_val="${_CSM_MAP_BFD_FIXED[$mi]}"

        case "$map_type" in
            pressure)
                trigger=$(csm_read_var "$CSM_CSF_CONF" "$lf_var") || true  # returns 1 when var absent; empty trigger skips entry
                if [[ -n "$trigger" ]]; then
                    trip=$(( trigger * 3 ))
                    if [[ $trip -gt 200 ]]; then
                        trip=200
                    fi
                    _CSM_BFD_RULES+=("$rule_name")
                    _CSM_BFD_TRIPS+=("$trip")
                fi
                ;;
            direct)
                val=$(csm_read_var "$CSM_CSF_CONF" "$lf_var") || true  # returns 1 when var absent; empty val skips entry
                if [[ -n "$val" ]]; then
                    _CSM_BFD_RULES+=("$rule_name")
                    _CSM_BFD_TRIPS+=("$val")
                fi
                ;;
            fixed)
                # Fixed always emits the rule regardless of whether var is in config
                _CSM_BFD_RULES+=("$rule_name")
                _CSM_BFD_TRIPS+=("$fixed_val")
                ;;
        esac
    done

    return 0
}

# ---------------------------------------------------------------------------
# Section 6: CXS→LMD Translation
# ---------------------------------------------------------------------------

# Mapping table arrays (populated by _csm_map_lmd_init)
# Transform types:
#   direct      — copy value verbatim
#   watch_mode  — CXS_WATCH: "1"→"users", "0"→"disabled"
#   bytes_to_k  — divide bytes value by 1024 (integer)
#   gap         — no LMD equivalent; record status="gap"
_CSM_MAP_LMD_SRC=()
_CSM_MAP_LMD_DST=()
_CSM_MAP_LMD_XFM=()

# _csm_map_lmd_init — populate CXS→LMD mapping table
# Populates: _CSM_MAP_LMD_SRC[], _CSM_MAP_LMD_DST[], _CSM_MAP_LMD_XFM[]
_csm_map_lmd_init() {
    _CSM_MAP_LMD_SRC=(); _CSM_MAP_LMD_DST=(); _CSM_MAP_LMD_XFM=()
    # Format: SRC (CXS var) | DST (LMD var) | XFM (transform type)

    # --- Quarantine ---
    _CSM_MAP_LMD_SRC+=("CXS_QUARANTINE");       _CSM_MAP_LMD_DST+=("quarantine_hits");      _CSM_MAP_LMD_XFM+=("direct")
    _CSM_MAP_LMD_SRC+=("CXS_QUARANTINE_CLEAN"); _CSM_MAP_LMD_DST+=("quarantine_clean");     _CSM_MAP_LMD_XFM+=("direct")

    # --- Alerts ---
    _CSM_MAP_LMD_SRC+=("CXS_ALERT");            _CSM_MAP_LMD_DST+=("email_alert");          _CSM_MAP_LMD_XFM+=("direct")
    _CSM_MAP_LMD_SRC+=("CXS_ALERT_TO");         _CSM_MAP_LMD_DST+=("email_addr");           _CSM_MAP_LMD_XFM+=("direct")

    # --- Scanner ---
    _CSM_MAP_LMD_SRC+=("CXS_CLAMAV");           _CSM_MAP_LMD_DST+=("scan_clamscan");        _CSM_MAP_LMD_XFM+=("direct")
    _CSM_MAP_LMD_SRC+=("CXS_NICE");             _CSM_MAP_LMD_DST+=("scan_nice");            _CSM_MAP_LMD_XFM+=("direct")
    _CSM_MAP_LMD_SRC+=("CXS_IONICE");           _CSM_MAP_LMD_DST+=("scan_ionice");          _CSM_MAP_LMD_XFM+=("direct")
    _CSM_MAP_LMD_SRC+=("CXS_MAXFILESIZE");      _CSM_MAP_LMD_DST+=("scan_max_filesize");    _CSM_MAP_LMD_XFM+=("bytes_to_k")
    _CSM_MAP_LMD_SRC+=("CXS_MAXDEPTH");         _CSM_MAP_LMD_DST+=("scan_max_depth");       _CSM_MAP_LMD_XFM+=("direct")
    _CSM_MAP_LMD_SRC+=("CXS_SCANDAYS");         _CSM_MAP_LMD_DST+=("scan_recent_files");    _CSM_MAP_LMD_XFM+=("direct")

    # --- Scheduling / updates ---
    _CSM_MAP_LMD_SRC+=("CXS_CRON");             _CSM_MAP_LMD_DST+=("cron_daily_scan");      _CSM_MAP_LMD_XFM+=("direct")
    _CSM_MAP_LMD_SRC+=("CXS_AUTOUPDATE");       _CSM_MAP_LMD_DST+=("autoupdate");           _CSM_MAP_LMD_XFM+=("direct")

    # --- Suspend ---
    _CSM_MAP_LMD_SRC+=("CXS_SUSPEND");          _CSM_MAP_LMD_DST+=("suspend_user");         _CSM_MAP_LMD_XFM+=("direct")
    _CSM_MAP_LMD_SRC+=("CXS_SUSPEND_MINUID");   _CSM_MAP_LMD_DST+=("suspend_user_minuid");  _CSM_MAP_LMD_XFM+=("direct")

    # --- Inotify / watch ---
    _CSM_MAP_LMD_SRC+=("CXS_WATCH");            _CSM_MAP_LMD_DST+=("default_monitor_mode"); _CSM_MAP_LMD_XFM+=("watch_mode")
    _CSM_MAP_LMD_SRC+=("CXS_WATCH_DOCROOT");    _CSM_MAP_LMD_DST+=("monitor_docroot");      _CSM_MAP_LMD_XFM+=("direct")
    _CSM_MAP_LMD_SRC+=("CXS_WATCH_MINUID");     _CSM_MAP_LMD_DST+=("inotify_minuid");       _CSM_MAP_LMD_XFM+=("direct")
    _CSM_MAP_LMD_SRC+=("CXS_WATCH_SLEEP");      _CSM_MAP_LMD_DST+=("inotify_sleep");        _CSM_MAP_LMD_XFM+=("direct")
    _CSM_MAP_LMD_SRC+=("CXS_WATCH_NICE");       _CSM_MAP_LMD_DST+=("inotify_nice");         _CSM_MAP_LMD_XFM+=("direct")
    _CSM_MAP_LMD_SRC+=("CXS_WATCH_IONICE");     _CSM_MAP_LMD_DST+=("inotify_ionice");       _CSM_MAP_LMD_XFM+=("direct")
    _CSM_MAP_LMD_SRC+=("CXS_WATCH_WATCHES");    _CSM_MAP_LMD_DST+=("inotify_watches");      _CSM_MAP_LMD_XFM+=("direct")

    # --- Gap variables: no LMD equivalent ---
    _CSM_MAP_LMD_SRC+=("CXS_FTP_UPLOAD");       _CSM_MAP_LMD_DST+=("no LMD equivalent");    _CSM_MAP_LMD_XFM+=("gap")
    _CSM_MAP_LMD_SRC+=("CXS_CGI_UPLOAD");       _CSM_MAP_LMD_DST+=("no LMD equivalent");    _CSM_MAP_LMD_XFM+=("gap")
    _CSM_MAP_LMD_SRC+=("CXS_UI_APP");           _CSM_MAP_LMD_DST+=("no LMD equivalent");    _CSM_MAP_LMD_XFM+=("gap")
    _CSM_MAP_LMD_SRC+=("CXS_UI_TYPE");          _CSM_MAP_LMD_DST+=("no LMD equivalent");    _CSM_MAP_LMD_XFM+=("gap")
    _CSM_MAP_LMD_SRC+=("CXS_UI_ADMIN");         _CSM_MAP_LMD_DST+=("no LMD equivalent");    _CSM_MAP_LMD_XFM+=("gap")
}

# csm_translate_lmd — translate CXS config to LMD equivalents
# 1. Reads raw config from CSM_CXS_DEFAULTS first, then merges CSM_CXS_WATCHCONF
# 2. Applies mapping table transforms
# 3. Auto-sets scan_yara="1" (LMD always enables YARA when available)
# 4. Captures cxswatch.sh CLI invocation line for report reference
# Sets: _CSM_NORM_NAMES[], _CSM_NORM_VALUES[], _CSM_NORM_STATUS[], _CSM_NORM_TARGET[]
#       _CSM_REPORT_LINES[] — appended with CXS script CLI line (if found)
# Returns: 0 on success, 1 if cxs.defaults missing
csm_translate_lmd() {
    # Reset norm store for re-entry safety
    _CSM_NORM_NAMES=()
    _CSM_NORM_VALUES=()
    _CSM_NORM_STATUS=()
    _CSM_NORM_TARGET=()

    [[ ! -f "$CSM_CXS_DEFAULTS" ]] && return 1

    # --- Multi-file read: cxs.defaults first, then merge cxswatch.conf ---
    csm_read_conf "$CSM_CXS_DEFAULTS" || return 1

    # Merge cxswatch.conf into raw arrays (watchconf values override on key clash)
    if [[ -f "$CSM_CXS_WATCHCONF" ]]; then
        local wline wname wval wi wk wv found_idx ri
        local -a watch_names=()
        local -a watch_values=()
        local wvar_pat='^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)'
        while IFS= read -r wline; do
            [[ "$wline" =~ ^[[:space:]]*# ]] && continue
            [[ "$wline" =~ ^[[:space:]]*$ ]] && continue
            if [[ "$wline" =~ $wvar_pat ]]; then
                wname="${BASH_REMATCH[1]}"
                wval="${BASH_REMATCH[2]}"
                wval="${wval#\"}"
                wval="${wval%\"}"
                wval="${wval#\'}"
                wval="${wval%\'}"
                wval="${wval%%[[:space:]]#*}"
                watch_names+=("$wname")
                watch_values+=("$wval")
            fi
        done < <(sed 's/\r$//' "$CSM_CXS_WATCHCONF")

        for wi in "${!watch_names[@]}"; do
            wk="${watch_names[$wi]}"
            wv="${watch_values[$wi]}"
            found_idx=-1
            for ri in "${!_CSM_RAW_NAMES[@]}"; do
                if [[ "${_CSM_RAW_NAMES[$ri]}" == "$wk" ]]; then
                    found_idx="$ri"
                    break
                fi
            done
            if [[ "$found_idx" -ge 0 ]]; then
                _CSM_RAW_VALUES[found_idx]="$wv"
            else
                _CSM_RAW_NAMES+=("$wk")
                _CSM_RAW_VALUES+=("$wv")
            fi
        done
    fi

    _csm_map_lmd_init

    local -a _lmd_mapped_srcs=()
    local mi raw_val raw_idx xfm dst src ri

    for mi in "${!_CSM_MAP_LMD_SRC[@]}"; do
        src="${_CSM_MAP_LMD_SRC[$mi]}"
        dst="${_CSM_MAP_LMD_DST[$mi]}"
        xfm="${_CSM_MAP_LMD_XFM[$mi]}"

        # Find this src var in the merged raw array
        raw_val=""
        raw_idx=-1
        for ri in "${!_CSM_RAW_NAMES[@]}"; do
            if [[ "${_CSM_RAW_NAMES[$ri]}" == "$src" ]]; then
                raw_val="${_CSM_RAW_VALUES[$ri]}"
                raw_idx="$ri"
                break
            fi
        done

        # Skip if var not present in merged config
        [[ "$raw_idx" -eq -1 ]] && continue

        _lmd_mapped_srcs+=("$src")

        case "$xfm" in
            direct)
                _csm_norm_add "$src" "$raw_val" "translated" "$dst"
                ;;
            watch_mode)
                # CXS_WATCH: "1" → "users", anything else → "disabled"
                local mode_val
                if [[ "$raw_val" == "1" ]]; then
                    mode_val="users"
                else
                    mode_val="disabled"
                fi
                _csm_norm_add "$src" "$mode_val" "translated" "$dst"
                ;;
            bytes_to_k)
                # Divide integer byte value by 1024; non-numeric passes as 0
                local k_val=0
                local numeric_pat='^[0-9]+$'
                if [[ "$raw_val" =~ $numeric_pat ]]; then
                    k_val=$(( raw_val / 1024 ))
                fi
                _csm_norm_add "$src" "$k_val" "translated" "$dst"
                ;;
            gap)
                _csm_norm_add "$src" "$raw_val" "gap" "$dst"
                ;;
            *)
                _csm_norm_add "$src" "$raw_val" "translated" "$dst"
                ;;
        esac
    done

    # Auto-set scan_yara="1" — LMD always enables YARA when available
    _csm_norm_add "scan_yara" "1" "translated" "scan_yara"

    # Capture cxswatch.sh CLI invocation line for report reference
    local cxs_script="${CSM_CXS_DIR}/cxswatch.sh"
    if [[ -f "$cxs_script" ]]; then
        local script_line
        while IFS= read -r script_line; do
            [[ "$script_line" =~ ^#! ]] && continue          # skip shebang
            [[ "$script_line" =~ ^[[:space:]]*# ]] && continue  # skip comments
            [[ "$script_line" =~ ^[[:space:]]*$ ]] && continue  # skip blank
            _CSM_REPORT_LINES+=("CXS script CLI: ${script_line}")
            break
        done < "$cxs_script"
    fi

    return 0
}
