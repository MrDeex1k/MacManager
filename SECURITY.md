# Security Policy

## Supported versions

Mac Manager has no public release yet. Until the first release, security fixes are made on the active development branch and included before release. A supported-version table will be added when versioned builds become available.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting from the repository **Security** tab when it is available. Include:

- the affected commit or version,
- a concise description of the impact,
- steps or a minimal proof of concept,
- relevant macOS version and hardware class,
- suggested mitigation, if known.

Do not include clipboard contents, real IP addresses, credentials, device identifiers or unrelated user data. Please do not open a public issue with exploit details. If private vulnerability reporting is not enabled, open a public issue containing no sensitive details and ask the maintainer to establish a private contact channel.

You should receive an acknowledgement within seven days. Timelines for confirmation and remediation depend on severity and whether the issue requires validation on specific hardware or macOS versions. Please allow time for a fix and release before public disclosure.

## Scope

Security concerns include unintended data transmission or persistence, permissions requested beyond documented need, unsafe update behavior, input-event handling that disrupts the system, exposed secrets, and bypasses of local data protections.

General bugs and feature requests belong in the regular issue templates.
