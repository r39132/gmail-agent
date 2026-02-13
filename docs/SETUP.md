# Setup Guide

Full setup instructions for gmail-skill: GCP project, OAuth credentials, CLI tools, and environment configuration.

## 1. Install Prerequisites

### Required tools

- **bash** 4.0+ (ships with Linux; macOS users: `brew install bash`)
- **[gog CLI](https://github.com/nicholasgasior/gog)** — Google API CLI tool
- **[jq](https://jqlang.github.io/jq/)** — JSON processor

### Optional tools (for label deletion and message deletion via Gmail API)

- **python3** with `google-auth` and `google-api-python-client` packages (`pip install google-auth google-api-python-client`)
- **google-auth-oauthlib** — only needed for full-scope authorization (`pip install google-auth-oauthlib`)

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

<details>
<summary>Python packages (Optional - for label/message deletion via Gmail API)</summary>

Label deletion and old message deletion use the Gmail API directly via Python. Install the required packages:

```bash
pip install google-auth google-api-python-client
```

No separate authentication is needed — the scripts reuse your existing `gog` OAuth credentials.

For full-scope authorization (permanent delete), also install:

```bash
pip install google-auth-oauthlib
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
4. Give it a name (e.g., "Gmail Skill")
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

## 7. (Optional) Full-Scope Authorization for Permanent Delete

By default, the Gmail Skill uses the `gmail.modify` scope via `gog`, which can only **trash** messages (auto-deleted by Gmail after 30 days). To enable **permanent deletion**, run the full-scope authorization script:

```bash
pip install google-auth-oauthlib  # one-time dependency
bash skills/gmail-skill/bins/gmail-auth-full-scope.sh "$GMAIL_ACCOUNT"
```

This opens a browser for OAuth consent with the `https://mail.google.com/` scope (full Gmail access). The token is stored at `~/.gmail-skill/full-scope-token.json`.

Once authorized, the `gmail-delete-old-messages.sh` script will permanently delete messages instead of trashing them.

> **Note:** This is separate from the `gog auth login` token. The full-scope token is only used by the delete-old-messages script. All other scripts continue to use the `gog` CLI with its `gmail.modify` scope.
