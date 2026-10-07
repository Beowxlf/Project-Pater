#!/usr/bin/env bash
set -euo pipefail

if (( $# != 3 )); then
    echo "Usage: $0 TARGET DOMAIN WORDLIST" >&2
    exit 1
fi

TARGET="$1"
DOMAIN="$2"
WORDLIST="$3"
PORT=25
QUERY_TIMEOUT=20
MAX_WORKERS=100

command -v smtp-user-enum >/dev/null || {
    echo "Missing dependency: smtp-user-enum (Pentestmonkey version)" >&2
    exit 1
}

[[ -r "$WORDLIST" ]] || {
    echo "Cannot read wordlist: $WORDLIST" >&2
    exit 1
}

[[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || {
    echo "Invalid domain." >&2
    exit 1
}

TEMP_DIR="$(mktemp -d)"
RAW="$TEMP_DIR/enumeration.log"
FOUND="$TEMP_DIR/found-users.txt"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

echo "[*] Enumerating $TARGET:$PORT with bare VRFY names ($QUERY_TIMEOUT-second timeout, $MAX_WORKERS workers)"

smtp-user-enum \
    -M VRFY \
    -U "$WORDLIST" \
    -t "$TARGET" \
    -p "$PORT" \
    -w "$QUERY_TIMEOUT" \
    -m "$MAX_WORKERS" |
    tee "$RAW"

# Upstream builds without Kali's -w patch may ignore the timeout option.
if ! awk -v timeout="$QUERY_TIMEOUT" -v workers="$MAX_WORKERS" '
    $1 == "Query" && $2 == "timeout" && $4 == timeout { got_timeout = 1 }
    $1 == "Worker" && $2 == "Processes" && $4 == workers { got_workers = 1 }
    END { exit !(got_timeout && got_workers) }
' "$RAW"; then
    echo "The installed smtp-user-enum did not confirm the requested timeout and worker count." >&2
    exit 1
fi

# Extract usernames from Pentestmonkey's documented output formats:
#   TARGET: user exists (or user@domain exists)
#   user@TARGET: Exists
awk -v host="$TARGET" -v domain="$DOMAIN" '
{
    sub(/\r$/, "")
    candidate = ""

    if ($1 == host ":" && tolower($3) == "exists") {
        candidate = $2
    } else if ($2 == "Exists" && $1 ~ /:$/) {
        candidate = $1
        sub(/:$/, "", candidate)
        suffix = "@" host

        if (length(candidate) <= length(suffix) ||
            substr(candidate, length(candidate)-length(suffix)+1) != suffix)
            next

        candidate = substr(candidate, 1, length(candidate)-length(suffix))
    } else {
        next
    }

    if (index(candidate, "@")) {
        suffix = "@" domain

        if (length(candidate) <= length(suffix) ||
            substr(candidate, length(candidate)-length(suffix)+1) != suffix)
            next

        candidate = substr(candidate, 1, length(candidate)-length(suffix))
    }

    if (candidate ~ /^[A-Za-z0-9._+-]+$/)
        print candidate
}' "$RAW" | sort -u > "$FOUND"

if [[ ! -s "$FOUND" ]]; then
    echo "[*] No users extracted from enumeration output."
    exit 0
fi

printf '\n[*] Discovered users:\n'
cat "$FOUND"

# Read a complete SMTP response, including multiline replies.
read_reply() {
    local line
    REPLY_CODE=""

    while IFS= read -r -t "$QUERY_TIMEOUT" line <&3; do
        line="${line%$'\r'}"
        printf 'S: %s\n' "$line"

        if [[ "$line" =~ ^([0-9]{3})[[:space:]] ]]; then
            REPLY_CODE="${BASH_REMATCH[1]}"
            return 0
        fi
    done

    echo "[-] Connection closed or response timed out." >&2
    return 1
}

send_command() {
    printf 'C: %s\n' "$1"
    printf '%s\r\n' "$1" >&3 || return 1
    read_reply
}

# A subshell gives each user a separate connection and cleanup trap.
test_user() (
    user="$1"
    address="${user}@${DOMAIN}"

    printf '\n=== Testing %s ===\n' "$address"

    exec 3<>"/dev/tcp/$TARGET/$PORT" || {
        echo "[-] Cannot connect to $TARGET:$PORT" >&2
        exit 1
    }
    trap 'exec 3>&-; exec 3<&-' EXIT

    read_reply || exit 1
    [[ "$REPLY_CODE" == 220 ]] || exit 1

    send_command "EHLO htb.local" || exit 1
    if [[ "$REPLY_CODE" != 250 ]]; then
        send_command "HELO htb.local" || exit 1
        [[ "$REPLY_CODE" == 250 ]] || exit 1
    fi

    send_command "MAIL FROM:<$address>" || exit 1
    if [[ "$REPLY_CODE" != 250 ]]; then
        echo "[-] Sender rejected: $address"
        exit 1
    fi

    send_command "RCPT TO:<$address>" || exit 1
    case "$REPLY_CODE" in
        250|251) ;;
        *)
            echo "[-] Recipient not accepted: $address"
            exit 1
            ;;
    esac

    send_command "DATA" || exit 1
    if [[ "$REPLY_CODE" == 354 ]]; then
        echo "[+] Sender and recipient accepted; DATA ready: $address"
    else
        echo "[-] DATA rejected: $address"
        exit 1
    fi

    # EXIT closes the connection and aborts the unfinished transaction.
)

while IFS= read -r user; do
    if ! test_user "$user"; then
        printf '[*] Continuing to next user.\n'
    fi
done < "$FOUND"

