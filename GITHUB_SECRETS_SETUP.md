# GitHub Secrets Setup Guide

This guide explains how to configure GitHub Secrets for your Unity Android/iOS CI/CD pipeline.

## What Are GitHub Secrets?

GitHub Secrets are encrypted environment variables that you set in your repository. They're perfect for storing sensitive information like API keys, certificates, and passwords that your CI/CD pipeline needs.

## Quick Start

### Option 1: Upload from Local Environment (Recommended)

If you already have your secrets configured locally in `.env.android.local`:

```bash
# Make sure gh CLI is installed
brew install gh

# Authenticate with GitHub
gh auth login

# Run the sync script to upload your local secrets to GitHub
./Scripts/syncGitHubSecretsToLocal.sh
```

Choose option 1 to upload from local to GitHub.

### Option 2: Manual Setup

Go to your repository settings and add secrets manually:
https://github.com/boardible/ineuj/settings/secrets/actions

---

## Required GitHub Secrets for Android

### 1. Facebook SDK Credentials

**FB_APP_ID**
- Description: Your Facebook App ID (without the "fb" prefix)
- Example: `681865130889080`
- Where to find: https://developers.facebook.com/apps/ → Your App → Settings → Basic

**FB_CLIENT_TOKEN**
- Description: Facebook Client Token for SDK authentication
- Example: `a3230776666a6049e521968cddda7685`
- Where to find: https://developers.facebook.com/apps/ → Your App → Settings → Advanced

### 2. Google Play Store Configuration

**GOOGLE_PLAY_SERVICE_ACCOUNT_JSON**
- Description: Google Play Service Account JSON (entire file content as single line)
- Format: JSON string (minified)
- Example:
  ```json
  {"type":"service_account","project_id":"your-project","private_key_id":"...","private_key":"-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n","client_email":"...@....iam.gserviceaccount.com","client_id":"..."}
  ```
- How to get: See `GOOGLE_PLAY_SERVICE_ACCOUNT_SETUP.md`

**ANDROID_PACKAGE_NAME**
- Description: Your Android app package name
- Example: `com.boardible.ineuj`
- Where to find: In your Unity project's Player Settings

### 3. Android Code Signing

**ANDROID_KEYSTORE_BASE64**
- Description: Your Android keystore file, base64-encoded
- How to create:
  ```bash
  # Encode your keystore
  base64 -i /path/to/your/keystore.jks | pbcopy
  
  # Then paste into GitHub Secrets
  ```
- Note: For CI/CD, we use base64-encoded keystores instead of file paths

**ANDROID_KEYSTORE_PASS**
- Description: Password for the keystore file
- Example: `your_secure_password_here`

**ANDROID_KEY_ALIAS**
- Description: Alias name for the signing key
- Example: `release`

**ANDROID_KEY_PASS**
- Description: Password for the signing key (often same as keystore password)
- Example: `your_secure_password_here`

### 4. Deployment Configuration (Optional)

**DEPLOY_TRACK**
- Description: Which Google Play track to deploy to
- Default: `internal`
- Options: `internal`, `alpha`, `beta`, `production`

---

## Required GitHub Secrets for iOS

### 1. Apple Developer Configuration

**APPLE_DEVELOPER_EMAIL**
- Description: Your Apple Developer account email
- Example: `developer@boardible.com`

**APPLE_CONNECT_EMAIL**
- Description: App Store Connect email (often same as developer email)
- Example: `support@boardible.com`

**APPLE_TEAM_ID**
- Description: Your Apple Developer Team ID
- Example: `35W3RB2M4Z`
- Where to find: https://developer.apple.com/account → Membership

**APPLE_TEAM_NAME**
- Description: Your Apple Developer Team Name
- Example: `Boardible LTDA`

### 2. App Store Connect API

**APPSTORE_KEY_ID**
- Description: App Store Connect API Key ID
- Example: `ABC123DEF4`
- Where to find: https://appstoreconnect.apple.com/access/api → Keys

**APPSTORE_ISSUER_ID**
- Description: App Store Connect API Issuer ID
- Example: `12345678-1234-1234-1234-123456789abc`
- Where to find: https://appstoreconnect.apple.com/access/api → Keys (top of page)

**APPSTORE_P8_CONTENT**
- Description: App Store Connect API Private Key (entire .p8 file content)
- Format: Multi-line string including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----`
- How to get:
  1. Download .p8 file from App Store Connect
  2. Copy entire file content including headers
  3. Paste into GitHub Secret

### 3. Code Signing

**MATCH_PASSWORD**
- Description: Password for Fastlane Match (encrypted certificates storage)
- Example: Your secure password
- Note: Choose a strong password and save it securely

**REPO_TOKEN**
- Description: GitHub Personal Access Token for accessing Match repository
- Example: `ghp_xxxxxxxxxxxxxxxxxxxx`
- How to create:
  1. Go to: https://github.com/settings/tokens
  2. Generate new token (classic)
  3. Select scopes: `repo` (Full control of private repositories)
  4. Save the token securely

**IOS_APP_ID**
- Description: Your iOS app bundle identifier
- Example: `com.boardible.ineuj`

---

## Step-by-Step Setup Instructions

### Step 1: Install GitHub CLI (if not already installed)

```bash
brew install gh
gh auth login
```

### Step 2: Verify Your Local Environment

Make sure your `.env.android.local` file is properly configured:

```bash
cat Scripts/.env.android.local
```

### Step 3: Upload Secrets to GitHub

Option A: Use the sync script (recommended):
```bash
./Scripts/syncGitHubSecretsToLocal.sh
```

Option B: Manual upload:
```bash
# Example: Upload Facebook App ID
gh secret set FB_APP_ID --body "681865130889080" --repo boardible/ineuj

# Example: Upload keystore (base64-encoded)
base64 -i /path/to/keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64 --repo boardible/ineuj
```

### Step 4: Verify Secrets Are Set

```bash
# List all secrets
gh secret list --repo boardible/ineuj

# Or use the check script
./Scripts/checkSecrets.sh
```

---

## Security Best Practices

### ✅ DO:
- Use strong, unique passwords for keystores and certificates
- Rotate secrets periodically (at least yearly)
- Use different keystores for debug/release builds
- Keep your service account JSON files secure
- Use least-privilege principle for service accounts
- Enable 2FA on all developer accounts

### ❌ DON'T:
- Commit secrets to git (ever!)
- Share secrets via email or chat
- Use the same password for multiple secrets
- Give service accounts more permissions than needed
- Store secrets in plain text files without encryption

---

## Troubleshooting

### "Secret not found" error in GitHub Actions

1. Check secret name matches exactly (case-sensitive)
2. Verify secret is set at repository level (not environment level)
3. Check repository permissions for GitHub Actions

### "Invalid keystore" error

1. Verify base64 encoding is correct:
   ```bash
   # Test decode
   gh secret set ANDROID_KEYSTORE_BASE64 --repo boardible/ineuj < <(base64 -i keystore.jks)
   ```
2. Check keystore password is correct
3. Verify key alias exists in keystore

### "Google Play authentication failed"

1. Verify JSON is valid and properly formatted
2. Check service account has correct permissions in Google Play Console
3. Ensure API is enabled in Google Cloud Console

### "Apple authentication failed"

1. Verify .p8 key is valid and not expired
2. Check API key has correct permissions in App Store Connect
3. Verify Team ID and Issuer ID are correct

---

## Quick Reference Commands

```bash
# Upload a secret
gh secret set SECRET_NAME --body "secret_value" --repo boardible/ineuj

# Upload from file
gh secret set SECRET_NAME < secret_file.txt --repo boardible/ineuj

# List secrets
gh secret list --repo boardible/ineuj

# Delete a secret
gh secret delete SECRET_NAME --repo boardible/ineuj

# Base64 encode keystore and upload
base64 -i keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64 --repo boardible/ineuj

# View local secrets (be careful!)
cat Scripts/.env.android.local

# Sync local to GitHub
./Scripts/syncGitHubSecretsToLocal.sh
```

---

## Related Documentation

- [CI/CD Environment Variables](./CI-CD-ENVIRONMENT-VARIABLES.md) - Complete list of variables
- [Google Play Service Account Setup](./GOOGLE_PLAY_SERVICE_ACCOUNT_SETUP.md) - Detailed Google Play setup
- [Android Build Quick Start](./ANDROID_BUILD_QUICK_START.md) - Build system overview
- [Secrets Validation](./checkSecrets.sh) - Script to verify all secrets are configured

---

## Support

If you encounter issues:

1. Check the error message carefully
2. Review this documentation
3. Run `./Scripts/checkSecrets.sh` to diagnose
4. Check GitHub Actions logs for detailed errors
5. Verify all prerequisites are met

**Need help?** Contact the development team or check the project wiki.
