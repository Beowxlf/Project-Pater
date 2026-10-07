# Project-Pater

Private repository for small, separately documented red-team lab tools. Each tool lives in its own folder so its purpose, dependencies, and limits stay with the script.

## Tools

| Folder | Purpose |
| --- | --- |
| [`smtp-vrfy-envelope-probe/`](smtp-vrfy-envelope-probe/) | Enumerate candidate SMTP recipients with `VRFY`, then check how the same address is treated as an envelope sender and recipient up to the `DATA` stage. |

Use these tools only within an engagement or lab where the target and traffic are authorized.
