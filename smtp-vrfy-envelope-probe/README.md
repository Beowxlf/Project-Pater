# SMTP VRFY envelope probe

This Bash helper wraps Pentestmonkey's `smtp-user-enum`. It takes a small wordlist of local parts, runs `VRFY` against one SMTP target on TCP 25, extracts candidate names from the tool's reported results, and opens a separate SMTP connection for each candidate. On each connection it sends `EHLO` (or falls back to `HELO`), `MAIL FROM`, `RCPT TO`, and `DATA` using the candidate's address. It closes the connection after a `354` response, before sending a message body.

Its purpose is to compare recipient enumeration with envelope acceptance on an authorized lab server. A positive result means the server accepted that transaction *so far from this client*. It does **not** prove an operating-system account exists, that a mailbox received mail, or that sender spoofing or relay is possible. `smtp-user-enum` can classify an inconclusive SMTP reply as an existing user, so review the raw replies and the server's recipient map before making a finding.

## Requirements

- Bash with `/dev/tcp` support; `awk`, `sort`, `mktemp`, and `tee`.
- [Pentestmonkey `smtp-user-enum`](https://www.kali.org/tools/smtp-user-enum/) on `PATH`.
- An authorized SMTP listener on TCP 25 that permits the tested commands without STARTTLS or SMTP AUTH.

The script does not implement TLS, authentication, custom ports, or message delivery. Its `EHLO` identity is `htb.local`, as in the supplied lab script.

## Use

```bash
./smtp-vrfy-envelope-probe.sh mail.lab.test lab.test candidates.txt
```

`TARGET` is the SMTP host, `DOMAIN` is appended to each wordlist entry, and `WORDLIST` contains one local part per line. Keep the list within the approved scope and small enough to review each reply. The script prints the enumeration output and SMTP replies, then deletes its temporary files on exit.

For a controlled comparison, include one owner-created valid recipient and one owner-created invalid recipient. If the server gives the same answer for both, report the result as inconclusive.
