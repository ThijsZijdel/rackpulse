# Security

## Reporting a vulnerability

Please report vulnerabilities privately through [GitHub's private vulnerability reporting](https://github.com/en3sis/rackpulse/security/advisories/new). Don't open a public issue.

Include what is affected (the app, the agent, or the install script), the version, and steps to reproduce. You'll get an answer within a few days. Once a fix is released, the report is credited unless you prefer otherwise.

## Supported versions

Only the latest release of the app and the agent gets security fixes. The app updates itself, and `curl -fsSL https://rackpulse.app/agent/install.sh | sudo sh` updates the agent and keeps its key.

## Design

- The app stores API tokens and agent keys in the macOS Keychain and runs in the App Sandbox.
- With a Read token the app can't change anything. With a Read & Write token it sends only the five power actions, after confirmation.
- The agent is read-only, runs as its own user under systemd sandboxing, and answers only requests that carry its server's key. The app pins the agent's certificate on the first connection.

[docs/AGENT.md](docs/AGENT.md) describes the agent's security model and protocol in detail.
