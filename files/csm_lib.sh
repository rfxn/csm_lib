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
