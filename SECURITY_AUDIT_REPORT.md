# SECURITY AUDIT REPORT - project: feb

## 1. Executive Summary
The overall security posture of the application is **Strong**, particularly regarding credential management and network transport. The use of a Cloudflare Worker proxy to abstract API keys is a high-maturity design choice that prevents sensitive secrets from being shipped in the client binary. No critical credential leaks or hardcoded secrets were found.

However, there are structural weaknesses regarding **outdated dependencies**, **local data privacy**, and **route-level access control** that should be addressed to harden the application against advanced threats.

---

## 2. Critical Vulnerabilities (High Severity)
*No critical remote-code execution (RCE) or plaintext credential leaks were found.*

**High Risk Findings:**
*   **Path Traversal Risk in `EncryptedCacheManager`**:
    *   **Issue**: Remote-sourced IDs are used to construct local file paths without explicit sanitization. An attacker providing a specially crafted ID (e.g., `../../etc/passwd`) could potentially access files outside the intended cache directory.
    *   **Remediation**: Implement a sanitization function to strip path traversal sequences (`..`, `/`, `\`) from any remote ID before using it in a file path.

---

## 3. Medium & Low Risks

### 🔴 Medium Risks
*   **Broken Access Control (Route Bypass)**:
    *   **Files**: `lib/screens/account_details_screen.dart`, `lib/screens/manage_subscription_screen.dart`
    *   **Issue**: These screens lack internal authorization guards. While the UI prevents navigation to them for unauthenticated users, direct routing (if exposed) could allow unauthorized access.
    *   **Remediation**: Add an `AuthGuard` or check the authentication state in the `initState` of these screens.
*   **Outdated Security-Critical Dependencies**:
    *   **Issue**: Core packages (`firebase_auth`, `firebase_core`, `google_sign_in`, `sign_in_with_apple`) are several versions behind. This increases the risk of missing critical security patches.
    *   **Remediation**: Run `flutter pub upgrade` and specifically target the latest versions of Firebase and Auth plugins.

### 🟡 Low Risks
*   **Local Data Privacy (Unencrypted Storage)**:
    *   **Issue**: Hive boxes (`continue_watching`, `reviews`) store user history in plaintext. If a device is rooted, this data is easily accessible.
    *   **Remediation**: Implement `hive_aes` for sensitive boxes.
*   **Soft Secret Storage**:
    *   **Issue**: `_appSecret` is obfuscated rather than hardware-backed.
    *   **Remediation**: Migrate to `flutter_secure_storage` to utilize iOS Keychain / Android Keystore.
*   **Unstable State Updates**:
    *   **Issue**: `HomeScreen._hydrateSecondaryFromCache` lacks consistent `mounted` checks before `setState`, potentially leading to "setState called after dispose" crashes.
    *   **Remediation**: Ensure all async callbacks in `HomeScreen` check `if (!mounted) return;`.

---

## 4. Best Practice Recommendations

1.  **Hardware-Backed Security**: Move all local salts and keys from simple obfuscation to native secure storage.
2.  **Dependency Lifecycle**: Establish a monthly dependency audit to keep Firebase and Auth SDKs up to date.
3.  **Strict Route Guards**: Transition from "UI-based" navigation blocking to "Logic-based" route guarding for all sensitive screens.
4.  **Structured Error Handling**: Replace empty `catch (_) {}` blocks with a structured logging system to identify production failures without exposing stack traces to users.
