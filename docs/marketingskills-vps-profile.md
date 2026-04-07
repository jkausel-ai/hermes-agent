# Hermes + MarketingSkills VPS Profile

This recipe mounts the [`marketingskills`](https://github.com/coreyhaines31/marketingskills) repository into a dedicated Hermes profile instead of copying or modifying the skill pack.

## What this setup gives you

- A dedicated Hermes profile, usually `marketing`
- A dedicated workspace for briefs, artifacts, and reusable marketing context
- `marketingskills/skills` mounted as a read-only external skill directory
- A clear place to store marketing API credentials in the profile `.env`
- A profile-aware gateway service you can run on a VPS

## Expected repo layout

The helper scripts assume these repos are siblings:

```text
~/src/
  hermes-agent/
  marketingskills/
```

If your layout is different, pass `--marketingskills-repo`.

## Quick start

From the Hermes repo:

```bash
./scripts/setup-marketingskills-profile.sh \
  --profile marketing \
  --marketingskills-repo ../marketingskills \
  --workspace ~/hermes-marketing-workspace
```

That script will:

1. Create `~/.hermes/profiles/marketing/` if needed
2. Update `config.yaml` so `skills.external_dirs` includes `../marketingskills/skills`
3. Set the terminal working directory to `~/hermes-marketing-workspace`
4. Seed:
   - `~/hermes-marketing-workspace/AGENTS.md`
   - `~/hermes-marketing-workspace/.agents/product-marketing-context.md`
5. Add helper env vars to `~/.hermes/profiles/marketing/.env`

## Smoke test

Run the CLI smoke test before using the profile:

```bash
./scripts/smoke-test-marketingskills-clis.sh --marketingskills-repo ../marketingskills
```

This syntax-checks all marketing CLIs and runs dry-run calls for representative tools.

## Profile usage

Interactive:

```bash
hermes -p marketing
```

Convenience wrapper:

```bash
./scripts/hermes-marketing.sh
```

Inside the marketing workspace, Hermes will see:

- the local workspace instructions in `AGENTS.md`
- the product marketing context file in `.agents/product-marketing-context.md`
- the external skills from `marketingskills/skills`

## Messaging gateway on a VPS

Once the profile is configured:

```bash
hermes -p marketing gateway setup
sudo hermes -p marketing gateway install --system --run-as-user "$USER"
sudo hermes -p marketing gateway start --system
```

On Linux, the systemd unit name is profile-aware. For a `marketing` profile, Hermes will generate:

```text
hermes-gateway-marketing
```

Check status:

```bash
sudo hermes -p marketing gateway status --system
sudo journalctl -u hermes-gateway-marketing -f
```

If you prefer a user service instead of a boot-time system service:

```bash
hermes -p marketing gateway install
hermes -p marketing gateway start
```

Use the user-service path only if the VPS user session is configured with systemd linger.

## Credentials

Put marketing API credentials in:

```text
~/.hermes/profiles/marketing/.env
```

The setup script adds a commented starter block for common marketing tools.

Recommended pattern:

- only add keys for the tools you actually want the agent to operate
- keep production and sandbox credentials separate
- start with read-only/reporting tools before enabling mutating ones

## How the agent should run tool CLIs

The mounted `marketingskills` repo is intentionally left read-only. For tool execution, have the agent use explicit CLI paths:

```bash
node "$MARKETINGSKILLS_REPO/tools/clis/ga4.js" reports run --property 123 --metrics sessions --dimensions date
node "$MARKETINGSKILLS_REPO/tools/clis/meta-ads.js" campaigns list --account-id 123
```

The workspace `AGENTS.md` template reminds Hermes to:

- check `.agents/product-marketing-context.md` first
- consult `tools/REGISTRY.md` before picking an integration
- stop and report missing env vars instead of guessing
- write outputs to `artifacts/`

## Recommended founder workflow

1. Drop the company context into `.agents/product-marketing-context.md`
2. Put incoming asks in `briefs/`
3. Ask Hermes to produce artifacts into `artifacts/`
4. Use messaging for quick approvals, reviews, and follow-ups
5. Keep the profile narrow: marketing tasks, marketing credentials, marketing memory
