# Security

## Reporting a vulnerability

Please **don't open a public issue** for security problems. Report them privately through GitHub instead:
**Security → Report a vulnerability** on this repository ([GitHub's guide](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)).

Please include what you found, how to reproduce it, and what an attacker could do with it. You'll get a reply as soon as possible.

## What VoxType has access to

VoxType asks for **Accessibility**, so it can paste text into other apps, and for **Microphone** access. It runs without the App Sandbox, which is needed to paste into other apps. That makes these the areas where reports matter most:

- Anything that could make VoxType type or paste text the user didn't dictate
- Anything that could expose dictated text, history or the stored OpenAI key to other apps or to the network
