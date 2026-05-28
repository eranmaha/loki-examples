---
name: slack-channel-setup
description: Step-by-step guide to connect a Slack workspace to OpenClaw using Socket Mode. Use when setting up Slack integration, adding a Slack channel, or troubleshooting Slack connectivity with OpenClaw.
---

# Slack Channel Setup for OpenClaw

Connect your Slack workspace to OpenClaw so your agent can read and respond to messages, react, pin items, and more.

## Prerequisites

- An OpenClaw instance running (gateway active)
- AWS Secrets Manager access (or another secrets provider) for storing tokens
- Admin access to your Slack workspace (to create an app)

## Step 1: Create a Slack App

1. Go to <https://api.slack.com/apps> → *Create New App* → *From scratch*
2. Name it (e.g. `OpenClaw`) and select your workspace
3. Under *Socket Mode* → Enable Socket Mode → generate an **App-Level Token** with scope `connections:write` — save this token (`xapp-...`)

## Step 2: Configure Bot Permissions

Navigate to *OAuth & Permissions* → Add these Bot Token Scopes:

| Scope | Purpose |
|-------|---------|
| `app_mentions:read` | Respond when @mentioned |
| `channels:history` | Read channel messages |
| `channels:read` | List channels |
| `chat:write` | Send messages |
| `reactions:read` | Read reactions |
| `reactions:write` | Add reactions |
| `pins:read` | List pins |
| `pins:write` | Pin/unpin messages |
| `users:read` | Get member info |
| `groups:history` | Read private channel messages (optional) |
| `im:history` | Read DMs (optional) |
| `im:write` | Send DMs (optional) |

Install the app to your workspace → copy the **Bot User OAuth Token** (`xoxb-...`).

## Step 3: Subscribe to Events

Under *Event Subscriptions* → Enable Events → Subscribe to bot events:

- `app_mention`
- `message.channels`
- `message.groups` (optional, for private channels)
- `message.im` (optional, for DMs)

Socket Mode handles delivery — no public URL needed.

## Step 4: Store Tokens in Secrets Manager

```bash
aws secretsmanager create-secret --name openclaw/slack-app-token \
  --secret-string "xapp-YOUR-APP-TOKEN"

aws secretsmanager create-secret --name openclaw/slack-bot-token \
  --secret-string "xoxb-YOUR-BOT-TOKEN"
```

## Step 5: Configure OpenClaw

```bash
openclaw config set channels.slack.enabled true
openclaw config set channels.slack.mode socket
openclaw config set channels.slack.appToken '{"source":"exec","provider":"aws-sm","id":"openclaw/slack-app-token"}'
openclaw config set channels.slack.botToken '{"source":"exec","provider":"aws-sm","id":"openclaw/slack-bot-token"}'
openclaw config set channels.slack.dmPolicy pairing
openclaw config set channels.slack.groupPolicy allowlist
```

### Allow Specific Channels

Add channels the bot should respond in (get channel ID from Slack → right-click channel name → *View channel details* → copy ID at bottom):

```bash
openclaw config set channels.slack.channels.C0XXXXXXXX '{}'
```

## Step 6: Invite the Bot & Restart

1. In Slack, invite the bot to your channel: `/invite @OpenClaw`
2. Restart the gateway:

```bash
openclaw gateway restart
```

## Step 7: Verify

Send a message mentioning your bot in the allowed channel. Check logs if no response:

```bash
openclaw gateway logs --tail 50
```

## Policies

| Policy | Value | Meaning |
|--------|-------|---------|
| `dmPolicy` | `pairing` | Only respond to DMs from the paired user |
| `groupPolicy` | `allowlist` | Only respond in explicitly listed channels |

## Troubleshooting

- *Bot doesn't respond* → Verify channel ID is in `channels.slack.channels`, bot is invited to the channel, and event subscriptions are active.
- *Token errors* → Confirm secrets exist: `aws secretsmanager get-secret-value --secret-id openclaw/slack-bot-token`
- *Socket disconnects* → Check `appToken` scope includes `connections:write`.
