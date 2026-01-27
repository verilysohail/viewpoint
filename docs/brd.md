# Business Requirements Document
## Developer ID Application Certificate for Internal macOS App Distribution

**Document Version:** 1.0
**Date:** January 23, 2026
**Author:** Sohail Mamdani
**Status:** Draft

---

## 1. Executive Summary

This document outlines the business requirements for obtaining a Developer ID Application certificate from the Apple Developer Program. This certificate is required to enable secure distribution of internally-developed macOS applications to employees across the organization.

While the recommended long-term solution for internal app distribution is an Apple Developer Enterprise Program membership with enterprise certificates, this approach serves as an effective interim solution until enterprise enrollment is established.

---

## 2. Business Need

### 2.1 Current State

The organization develops internal macOS applications to improve team productivity and streamline workflows. These applications are built using Apple's native development frameworks (Swift, SwiftUI, AppKit) and are intended for use by employees on company-managed and personal Mac devices.

Currently, these applications:

- Are built and compiled locally by developers
- Cannot be distributed to other employees without triggering macOS security warnings
- Require manual security overrides for each user to run
- Lack verified identity, making it difficult to distinguish legitimate internal tools from potential threats

### 2.2 Problem Statement

macOS Gatekeeper security prevents unsigned or non-notarized applications from running on users' machines without manual security overrides. When employees attempt to run internally-developed applications, they encounter:

1. **Gatekeeper blocking** — macOS displays "cannot be opened because the developer cannot be verified"
2. **Manual workarounds required** — Users must navigate to System Settings > Privacy & Security to allow the app
3. **Security warnings persist** — Even after allowing, users may see repeated security prompts
4. **Undermined security culture** — Training users to bypass security warnings creates risk for actual threats

This creates friction for adoption of internal tools and undermines the organization's security posture by normalizing the bypassing of legitimate security controls.

### 2.3 Proposed Solution

Obtain a Developer ID Application certificate to:

1. **Digitally sign** internal macOS applications with a verified company identity
2. **Notarize** applications through Apple's automated security checks
3. **Enable seamless distribution** to employees without security warnings
4. **Establish trust** that applications have been verified and are malware-free

### 2.4 Long-Term Recommendation

The ideal solution for internal app distribution is the **Apple Developer Enterprise Program**, which provides:

- Enterprise distribution certificates specifically designed for internal use
- No requirement for App Store submission
- Ability to distribute via MDM or internal hosting

However, the Enterprise Program has additional requirements (D-U-N-S number, organizational verification, Apple approval process) that may take time to establish. The Developer ID Application certificate provides an immediate, compliant solution while enterprise enrollment is pursued.

---

## 3. Scope

### 3.1 In Scope

- Obtaining a Developer ID Application certificate
- Establishing code signing and notarization workflows
- Distributing signed applications to internal employees
- Documentation of signing procedures for development teams

### 3.2 Out of Scope

- Public App Store distribution
- Distribution to external parties or customers
- Mobile (iOS/iPadOS) application distribution
- MDM enrollment and device management

### 3.3 Applicable Applications

This certificate will enable distribution of any internally-developed macOS applications, including but not limited to:

- Productivity and workflow tools
- Internal utilities and automation scripts (when packaged as apps)
- Developer tools and debugging utilities
- Data visualization and reporting dashboards
- Integration tools connecting internal systems

---

## 4. Business Justification

### 4.1 Benefits

| Benefit | Description |
|---------|-------------|
| **Improved user experience** | Employees can install and run internal apps without security warnings |
| **Stronger security posture** | Users are not trained to bypass Gatekeeper; security warnings retain meaning |
| **Verified identity** | Recipients can confirm applications come from the organization |
| **Malware protection** | Apple's notarization scans for known malicious code |
| **Professional distribution** | Reflects organizational standards for internal tooling |
| **Faster adoption** | Reduced friction leads to higher uptake of productivity tools |

### 4.2 Target Users

- All employees using macOS devices
- Development teams building internal tools
- IT staff distributing and supporting internal applications
- Remote workers who need efficient, native tooling

### 4.3 Distribution Model

| Method | Description |
|--------|-------------|
| **Direct download** | Signed `.app` or `.dmg` files hosted on internal file shares or intranet |
| **Email distribution** | Signed applications shared via internal email for small teams |
| **Self-service portal** | Internal app catalog for employees to browse and download tools |

---

## 5. Technical Requirements

### 5.1 Certificate Requirements

| Item | Specification |
|------|---------------|
| **Certificate Type** | Developer ID Application |
| **Program** | Apple Developer Program (organization account) |
| **Signing Identity** | Must be associated with company Team ID |
| **Notarization** | Required for macOS Gatekeeper acceptance |

### 5.2 Build Process Requirements

With the Developer ID certificate, each application build will require:

1. **Code Signing** — Sign the application bundle with the Developer ID certificate
2. **Hardened Runtime** — Enable hardened runtime (required for notarization)
3. **Notarization Submission** — Submit to Apple's notary service via `xcrun notarytool`
4. **Stapling** — Attach the notarization ticket to the application bundle
5. **Distribution** — Distribute the signed and notarized `.app` or `.dmg`

### 5.3 Common Entitlements

Applications may require entitlements depending on their functionality:

| Entitlement | Use Case |
|-------------|----------|
| `com.apple.security.network.client` | Network/API access |
| `com.apple.security.files.user-selected.read-write` | File system access |
| `com.apple.security.device.audio-input` | Microphone access |
| `com.apple.security.device.camera` | Camera access |
| `com.apple.security.automation.apple-events` | AppleScript/automation |

---

## 6. Security Considerations

### 6.1 Benefits of Code Signing and Notarization

1. **Identity Verification** — Certificate proves the application comes from the organization
2. **Integrity Assurance** — Signature detects if the application has been tampered with
3. **Malware Scanning** — Apple's notarization service scans for known malicious code
4. **Revocation Capability** — Compromised certificates can be revoked to protect users
5. **Audit Trail** — Signed applications can be traced back to the signing certificate

### 6.2 Certificate Security

The Developer ID certificate private key must be:

- Stored securely (Keychain, hardware security module, or CI/CD secrets management)
- Access-controlled to authorized personnel only
- Backed up securely for disaster recovery
- Revoked immediately if compromised

### 6.3 Comparison to Enterprise Distribution

| Aspect | Developer ID | Enterprise Certificate |
|--------|--------------|------------------------|
| **Intended use** | Public distribution outside App Store | Internal employee distribution only |
| **Notarization** | Required | Not required |
| **Gatekeeper** | Fully supported | Requires MDM or manual trust |
| **Availability** | Standard Developer Program | Enterprise Program (separate enrollment) |
| **Setup complexity** | Lower | Higher (D-U-N-S, Apple review) |

Developer ID with notarization is appropriate for internal distribution and provides stronger Gatekeeper integration than enterprise certificates in some scenarios.

---

## 7. Implementation Plan

### 7.1 Prerequisites

1. Active Apple Developer Program membership (organization account)
2. Admin access to Apple Developer portal
3. Xcode with command-line tools installed on build machines
4. Secure storage for certificate private key

### 7.2 Implementation Steps

| Phase | Activities |
|-------|------------|
| **1. Certificate Creation** | Generate CSR, request Developer ID Application certificate, download and install |
| **2. Build Integration** | Update build scripts/CI to include signing and notarization steps |
| **3. Documentation** | Document signing procedures for development teams |
| **4. Pilot Distribution** | Test with a small group of users to verify Gatekeeper acceptance |
| **5. Rollout** | Enable signing for all internal macOS applications |

### 7.3 Ongoing Maintenance

- Certificate validity: 5 years from issuance
- Notarization required for each new build
- Monitor Apple Developer account for certificate status
- Plan for certificate renewal before expiration

---

## 8. Cost Analysis

| Item | Cost | Frequency |
|------|------|-----------|
| Apple Developer Program | $99 USD | Annual |
| Developer time for setup | — | One-time |
| Build pipeline updates | — | One-time |

**Note:** If an organization Apple Developer account already exists, no additional program fees are required. The Developer ID certificate is included with the standard Apple Developer Program membership.

---

## 9. Success Criteria

| Criterion | Measurement |
|-----------|-------------|
| **Certificate obtained** | Developer ID Application certificate issued and installed |
| **Notarization workflow** | Build process successfully notarizes applications |
| **Gatekeeper acceptance** | Applications launch on employee machines without security warnings |
| **Documentation complete** | Signing procedures documented for development teams |
| **Pilot successful** | Test group can install and run signed applications |

---

## 10. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Certificate approval delays | Low | Medium | Submit request promptly; Apple typically processes within 1-2 days |
| Notarization failures | Medium | Low | Enable hardened runtime; test builds before distribution |
| Private key compromise | Low | High | Secure key storage; access controls; revocation plan |
| Certificate expiration | Low | High | Calendar reminders; renewal 30+ days before expiry |
| Apple policy changes | Low | Medium | Monitor Apple developer communications; maintain flexibility |

---

## 11. Future Considerations

### 11.1 Enterprise Program Migration

Once the Apple Developer Enterprise Program enrollment is complete, the organization should:

1. Evaluate whether to migrate to enterprise certificates
2. Consider hybrid approach (Developer ID for some apps, enterprise for others)
3. Integrate with MDM for streamlined distribution

### 11.2 CI/CD Integration

For teams with automated build pipelines:

1. Store signing credentials securely in CI/CD secrets
2. Automate notarization as part of release builds
3. Implement signing verification in deployment workflows

---

## 12. Conclusion

Obtaining a Developer ID Application certificate is essential for distributing internal macOS applications to employees in a secure, professional manner. This approach:

1. **Eliminates security friction** — No warnings or manual overrides for users
2. **Maintains security culture** — Gatekeeper warnings retain their meaning
3. **Provides verified trust** — Employees know applications come from the organization
4. **Enables Apple security validation** — Notarization confirms no known malware
5. **Serves as interim solution** — Effective immediately while enterprise enrollment is pursued

The minimal investment of the Apple Developer Program membership provides significant value in employee productivity, security compliance, and professional internal tooling.

---

## 13. Approvals

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Requestor | | | |
| Manager | | | |
| IT Security | | | |
| Finance | | | |

---

*Document prepared for internal use.*
