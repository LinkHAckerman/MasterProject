# Security Policy

Magnum Opus is a crypto/Web3 multi-language showcase project. It is **not production software** and has not been independently audited. Even so, we take security reports seriously and appreciate the time of anyone who helps make the project safer.

## Project status and what to expect

- The project is under active, continuous development, and part of it is written by automated AI agents (see [TERMS.md](TERMS.md)). Code can change daily.
- Smart contract, wallet, cryptography and transaction-handling code in this repository is for **demonstration and learning only**. **Do not use it to secure or move real funds.**
- Only the latest version on the `main` branch is supported. There are no versioned releases, and security fixes are not backported.

## Supported versions

| Version | Supported |
| --- | --- |
| `main` (latest commit) | Yes |
| Anything else (forks, older commits) | No |

## Reporting a vulnerability

**Please do not report security vulnerabilities in public issues, pull requests, or discussions.**

Report privately using GitHub's private vulnerability reporting:

1. Go to the [Security tab](https://github.com/LinkHAckerman/MasterProject/security) of this repository.
2. Select **Report a vulnerability**.
3. Fill in the form with the details below.

If that option is unavailable, open a public issue that says only that you have a security concern, with **no technical details**, and the Maintainer will arrange a private channel with you.

### What to include

- A clear description of the issue and the file(s) or component(s) affected
- Steps to reproduce, or a proof of concept
- The potential impact, as you understand it
- Any suggested fix or mitigation
- Whether you would like to be credited

## What you can expect from us

This is a personal project maintained by one person, so the timelines below are best-effort targets, not guarantees.

| Step | Target |
| --- | --- |
| Acknowledge your report | Within 7 days |
| Initial assessment | Within 14 days |
| Fix or mitigation for confirmed issues | Depends on severity and complexity |
| Public disclosure | After a fix is available, coordinated with you |

We will keep you informed of progress, credit you in the fix or advisory if you wish, and ask that you give us reasonable time to respond before disclosing the issue publicly.

## Scope

**In scope**

- Source code in this repository, including the Solidity contract, Rust on-chain program, C++ engine, Go service, C# service, Ruby service, SQL schema, and web front end
- Secrets or credentials accidentally committed to the repository
- Weaknesses in the GitHub Actions workflow or automation scripts that could expose secrets or allow unauthorized changes

**Out of scope**

- Vulnerabilities in third-party services, libraries, or platforms (report those to their owners)
- Social engineering, phishing, or physical attacks
- Denial-of-service testing against infrastructure we do not operate, such as GitHub or AI provider APIs
- Missing hardening that is clearly outside this project's showcase purpose (for example, the lack of a production-grade deployment setup)
- Reports from automated scanners without a demonstrated, relevant impact

## Safe harbor

If you act in good faith, follow this policy, avoid harming others, and do not access or modify data that is not yours, we will not pursue legal action against you for your research. Please do not test against any systems or accounts other than your own copy of the code.

## Secrets and credentials

If you find a leaked API key, token, private key, or seed phrase in this repository or its history, report it through the private channel above. Do not use it. We will revoke and rotate it.

Contributors must never commit secrets, as stated in [CONTRIBUTING.md](CONTRIBUTING.md).

## Disclaimer

Security reports are handled voluntarily and without compensation. There is no bug bounty program. This policy does not create any warranty, obligation, or liability, and is subject to the [MIT License](LICENSE) and [TERMS.md](TERMS.md).
