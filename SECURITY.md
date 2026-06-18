

# Security Policy

The Compact programming language is an open-source project hosted by the Linux Foundation Decentralized Trust (LFDT) under the Minokawa project. The security and integrity of the Compact language are paramount, as it serves as the foundation for privacy-preserving smart contracts on live, high-value decentralized networks.

This document outlines how to securely report vulnerabilities, our coordinated disclosure policy, and how we collaborate with core maintainers and network operators to protect users.

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues, discussions, or pull requests.**

If you believe you have found a security vulnerability in Compact, please report it privately to the core maintainers.

1. Navigate to the **[Security Advisories tab](https://github.com/LFDT-Minokawa/compact/security/advisories)** in this repository.
2. Click **"Report a vulnerability"** to open a private draft advisory.
3. Provide a detailed description of the issue, the steps to reproduce it, and any potential impact on zero-knowledge circuit generation, contract execution, or state transition.

Our maintainer team (led by Shielded Technologies) will acknowledge receipt of your vulnerability report within **48 hours** and provide a timeline for triage and resolution.

## Supported Versions

Only the most recent major and minor releases receive active security updates.

| Version | Supported |
| --- | --- |
| 1.x.x | :white_check_mark: |
| < 1.0 | :x: |

*(Note: Pre-release and beta versions are strictly for testing and are not covered by prioritized security SLAs.)*

---

## Governance & Coordinated Disclosure Policy

Because Compact operates within a decentralized ecosystem, fixing a vulnerability requires more than just pushing a patch. Live networks must be upgraded carefully before a zero-day exploit becomes public.

Under LFDT governance, we separate the responsibilities of **code maintenance** and **network operations**.

### 1. Maintainer Triage & Patching

The repository maintainers (primarily engineers from Shielded Technologies) are responsible for technical triage, zero-knowledge cryptographic review, and writing the mitigation code. All vulnerability resolution takes place in a private fork attached to the GitHub Security Advisory.

### 2. The Pre-Disclosure Embargo List

To protect live networks that rely on Compact for their consensus and smart contract execution, this project operates a strict **Coordinated Disclosure Embargo List**.

Major network operators and ecosystem stewards—such as the **[Midnight Foundation](https://midnight.network)**—are granted advanced, private notification of high-severity vulnerabilities before a CVE is published or the patch is merged into the public `main` branch.

**Purpose of the Embargo List:**

* To allow operators of live, high-value infrastructure to prepare node operators and validators for an emergency network upgrade.
* To prevent zero-day exploitation against live blockchain state while the patch is finalized.

**Criteria for Inclusion:**
Entities may request addition to the Embargo List if they operate a public, live network utilizing Compact in production where a vulnerability poses a systemic risk to user funds or data privacy. Additions to the list are approved by the LFDT Minokawa Technical Steering Committee (TSC).

### 3. Confidentiality Requirements

Access to the Embargo List is a privilege governed by strict confidentiality.

Entities on the pre-disclosure list (including the Midnight Foundation and any future approved network operators) must agree to the following:

* **Zero Leakage:** Vulnerability details, exploit mechanics, and patch code must not be shared outside of the designated security contacts within the operator's organization.
* **Operational Use Only:** Information is provided strictly for the purpose of coordinating a secure network upgrade.
* **Enforcement:** If an organization leaks embargoed vulnerability details—intentionally or accidentally—prior to the coordinated public disclosure date, they will be immediately and permanently removed from the Embargo List.

## Disclosure Timeline

1. **Triage:** Maintainers confirm the vulnerability and assess severity.
2. **Embargo Notification:** For critical and high-severity issues, the maintainers notify the Pre-Disclosure Embargo List via encrypted channels, providing a secure summary and an estimated timeline for the patch.
3. **Patch Preparation:** Maintainers develop and test the fix in a private repository fork. Select security contacts from major network operators may be temporarily invited as GitHub Advisory Collaborators to view the specific patch details if necessary for node compatibility.
4. **Coordinated Upgrade:** Network operators utilize the embargo period (typically 7 to 30 days, depending on severity) to stage updates.
5. **Public Release:** The patch is merged to `main`, a new version is released, and the GitHub Security Advisory / CVE is published.
