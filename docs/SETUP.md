# Setup Guide

Full setup instructions for gmail-agent: GCP project, OAuth credentials, CLI tools, and environment configuration.

## 1. Install Prerequisites

### Required tools

- **bash** 4.0+ (ships with Linux; macOS users: `brew install bash`)
- **[gog CLI](https://github.com/nicholasgasior/gog)** — Google API CLI tool
- **[jq](https://jqlang.github.io/jq/)** — JSON processor

### Platform-specific installation

<details>
<summary>macOS (Homebrew)</summary>

```bash
brew install jq bash
npm install -g gogcli
```
</details>

<details>
<summary>Ubuntu / Debian</summary>

```bash
sudo apt-get update && sudo apt-get install -y jq
npm install -g gogcli
```
</details>

<details>
<summary>Fedora / RHEL</summary>

```bash
sudo dnf install -y jq
npm install -g gogcli
```
</details>

<details>
<summary>Windows (WSL)</summary>

```bash
# Inside WSL (Ubuntu)
sudo apt-get update && sudo apt-get install -y jq
npm install -g gogcli
```
</details>

## 2. Create a GCP Project and Enable Gmail API

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (or select an existing one)
3. Navigate to **APIs & Services > Library**
4. Search for **Gmail API** and click **Enable**

## 3. Create OAuth 2.0 Credentials

1. Go to **APIs & Services > Credentials**
2. Click **Create Credentials > OAuth client ID**
3. Select **Desktop app** as the application type
4. Give it a name (e.g., "Gmail Agent")
5. Click **Create** and download the credentials JSON file

> **Security note:** Store the credentials file outside this repository (e.g., `~/.config/gog/credentials.json`). Never commit credentials to version control.

## 4. Configure OAuth Consent Screen

1. Go to **APIs & Services > OAuth consent screen**
2. Choose **External** (or **Internal** for Google Workspace orgs)
3. Fill in required fields (app name, support email)
4. Add these scopes:
   - `https://www.googleapis.com/auth/gmail.readonly` — read messages
   - `https://www.googleapis.com/auth/gmail.modify` — delete spam/trash
5. Under **Test users**, add the Gmail address you'll use

## 5. Authorize the gog CLI

```bash
gog auth login
```

This opens a browser for OAuth consent. After authorizing, verify it works:

```bash
gog gmail messages search "is:unread" --account YOUR_EMAIL --max 5
```

## 6. Configure Environment Variables

```bash
cp .env.example .env
```

Edit `.env` and set your Gmail address:

```bash
GMAIL_ACCOUNT="your-email@gmail.com"
```

Then source it:

```bash
source .env
```

For persistence, add `export GMAIL_ACCOUNT="your-email@gmail.com"` to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.).
