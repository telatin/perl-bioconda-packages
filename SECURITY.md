# Security Policy

## Abstract

This document describes how to report a security vulnerability in
**Bioconda::Packages**, what the project maintainers will do in response, and
which versions and classes of issue the policy covers. Bioconda::Packages is a
read-only Perl library that queries a bundled, offline snapshot of Bioconda
package metadata; it performs no network access at query time and executes no
third-party code, so its security surface is small but not zero.

## How to report a security vulnerability

Please report suspected vulnerabilities **privately** — do not open a public
issue, pull request, or discussion for an unfixed security problem.

- **Preferred:** open a private advisory via GitHub Security Advisories at
  <https://github.com/telatin/bioconda-packages/security/advisories/new>.
- **Alternative:** email the maintainer, Andrea Telatin, at
  <andrea.telatin@quadram.ac.uk> with `SECURITY` in the subject line.

When reporting, please include as much of the following as you can:

- the module version affected (`perl -MBioconda::Packages -e 'print $Bioconda::Packages::VERSION'`);
- your Perl version and operating system;
- a description of the issue and its impact;
- a minimal proof of concept or steps to reproduce.

### What to expect

- **Acknowledgement** within **5 business days** of your report.
- An initial **assessment** of severity and applicability within **10 business
  days**.
- Regular updates as we investigate and prepare a fix.
- **Coordinated disclosure:** we will agree a disclosure timeline with you,
  credit you in the advisory and the `Changes` file unless you ask otherwise,
  and publish a fixed release before any public details.

If you do not receive an acknowledgement within the stated window, please send
a follow-up — a missed message is more likely than a declined report.

## What this policy applies to

This policy covers security vulnerabilities in the code and bundled data
shipped in the `Bioconda-Packages` distribution, for example:

- flaws in the Perl modules under `lib/` (parsing, lookups, the CLI);
- issues that let malicious input to a public API or to the
  `bioconda-packages` command-line tool cause unsafe behaviour (e.g. denial of
  service, information disclosure, or code execution);
- integrity problems with the bundled database or how it is loaded.

The following are **out of scope** and should be reported through the normal
public issue tracker instead:

- the correctness or completeness of upstream Bioconda metadata itself (report
  package data problems to [bioconda-recipes](https://github.com/bioconda/bioconda-recipes));
- vulnerabilities in Perl itself or in unrelated CPAN modules;
- general bugs, feature requests, and build/installation questions with no
  security impact.

### Supported versions

Bioconda::Packages uses a calendar-based version scheme (`YYYY.MM.N`). Only the
**latest released version** on [CPAN](https://metacpan.org/dist/Bioconda-Packages)
receives security fixes. Fixes are shipped as a new release rather than
backported; please upgrade to the current version before reporting.

| Version        | Supported          |
|----------------|--------------------|
| Latest release | :white_check_mark: |
| Older releases | :x:                |

### Installation and usage notes

- Runtime dependencies are **core-only** (`JSON::PP`,
  `IO::Uncompress::Gunzip`), which keeps the dependency attack surface minimal.
- The library is **read-only and offline**: it opens and decompresses the
  bundled gzipped JSON database and answers queries. It does not write files,
  make network requests, or `eval` data at query time.
- Treat any **database file you supply via `new(db => $path)`** as you would any
  other input: load snapshots only from sources you trust, since a crafted file
  could attempt to trigger parser or resource-exhaustion issues.

## Workflow

Once a report is received, the maintainers will:

1. **Confirm receipt** and privately triage the report.
2. **Reproduce and assess** the issue, determining severity and affected
   versions.
3. **Develop and test a fix** on a private branch.
4. **Publish a new release** to CPAN and GitHub containing the fix.
5. **Disclose publicly** via a GitHub Security Advisory (and a CVE where
   warranted), crediting the reporter, in coordination with you.

Thank you for helping keep Bioconda::Packages and its users safe.
