# KODIMALI Android signing keys and certificates

Created 5 November 2026 for Customer and Manage. Each identity has its own RSA 3072 private key and public certificate, valid until October 2056. Fingerprints and aliases are in `certificates.json`; public certificates are the two PEM files beside this document.

## Where to find them on this laptop

Open this folder in File Explorer:

`C:\Users\user\Kodimali-Signing\android-production`

- `.envy`: private passwords, aliases and relative keystore filenames. Open locally in Notepad to see the credentials. This file is deliberately not in the repository; it is not loaded automatically by Flutter.
- `customer_mobile.jks` and `manage_mobile.jks`: the private signing keys. Preserve both for future updates.
- `customer_mobile-certificate.pem` and `manage_mobile-certificate.pem`: public certificates. You can open these as text; public copies are also in this documentation folder.
- `signing-config.dpapi`: an additional configuration copy encrypted for this Windows user profile. This file alone is not portable to another laptop.

The private folder has restricted Windows permissions. Never upload `.envy`, JKS files or backup passwords to GitHub, or paste their contents into chat.

## Portable backup and another laptop

Encrypted backup:

`C:\Users\user\Kodimali-Recovery\android-signing-2026-11-05\kodimali-signing-portable.zip`

Its password is saved locally in:

`C:\Users\user\Kodimali-Signing\portable-backup-password.txt`

1. Copy the encrypted ZIP to a private external drive or private backup storage. The current copy is on this laptop, so it cannot protect against losing the laptop until you make that copy.
2. Save its password separately, for example in your password manager. Do not keep the only password copy on the laptop you may replace.
3. On the new laptop, open the archive with an AES ZIP compatible extractor such as 7-Zip and enter the saved password. Extract into a private folder accessible only to your user account. On Windows, verify the folder's Security settings after extraction.
4. Confirm you have both JKS files, `.envy` and both public PEM certificates. The archive was decrypted and every restored file was verified against the originals; an incorrect password was also rejected. It does not depend on the old Windows profile.
5. Use the restored `.envy` values when signing future releases. The filenames in `.envy` are relative so they work in the new folder. Keep the same keys, aliases and passwords; generating replacements changes the signing identity.

For a future build, select the relevant `CUSTOMER_` or `MANAGE_` values from `.envy`. Existing Android Gradle configuration accepts these process environment variables: `KODIMALI_KEYSTORE_PATH` (full path to the restored JKS), `KODIMALI_KEY_ALIAS`, `KODIMALI_STORE_PASSWORD` and `KODIMALI_KEY_PASSWORD`. `.envy` is a credential reference, not an automatically imported environment file.

Public certificates identify a signing key but cannot sign an app by themselves. These are Android signing identities, not website HTTPS certificates or Apple distribution certificates. Any existing Google Play signing identity must be checked before publishing updates; Play ownership was not verified in this task. Previously inspected local APKs used a different Android debug certificate.

Scope: keys, public certificates, private credential storage and portable recovery. No app installation, store publication or production deployment was performed. A Customer release build had already completed before the instruction to stop builds; no further builds were continued.
