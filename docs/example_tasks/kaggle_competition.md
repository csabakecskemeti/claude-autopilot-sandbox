# Example Task: Kaggle Competition

## Pre-requisites (Human Must Do)

Before giving this task to the agent, YOU must:

1. **Accept competition rules** - Go to the competition page on Kaggle.com and click "Join Competition" or accept rules
2. **Create API token** - Go to https://www.kaggle.com/settings → API → "Create New Token"
3. **Note the token** - Copy the KGAT_xxx token

## Task Template

```
Solve the Kaggle competition: https://www.kaggle.com/competitions/playground-series-s6e3

Submit a result that is accepted, then spend 2-4 more rounds improving and submitting improved results.

## Kaggle API Setup

IMPORTANT: Use the NEW token format (access_token file), NOT the legacy kaggle.json format.

Set up authentication with this EXACT command:
```bash
mkdir -p ~/.kaggle && echo 'KGAT_XXXXX_YOUR_TOKEN_HERE' > ~/.kaggle/access_token && chmod 600 ~/.kaggle/access_token
```

WARNING: Do NOT create kaggle.json - that's for legacy credentials only. The KGAT tokens MUST go in ~/.kaggle/access_token

Verify authentication works:
```bash
kaggle competitions list
```

Then download the competition data:
```bash
kaggle competitions download -c playground-series-s6e3 -p ./data
unzip ./data/playground-series-s6e3.zip -d ./data
```

## When You Encounter Errors

If you get authentication errors (401, 403), API errors, or unexpected behavior:

1. STOP and use `web_search` immediately to research the error
2. Search for: "kaggle [error message] [year]" (e.g., "kaggle 401 unauthorized KGAT 2025")
3. Do NOT guess or try random variations - search for current documentation first
4. Kaggle's API changes frequently - always verify current usage

Example searches:
- "kaggle KGAT token access_token setup 2025"
- "kaggle competitions download 403 forbidden fix"
- "kaggle api authentication new token format"

## Submission

Use the Kaggle CLI to submit:
```bash
kaggle competitions submit -c playground-series-s6e3 -f submission.csv -m "Description of approach"
```

After first successful submission, iterate to improve your score.
```

## Notes

- Competition rules MUST be accepted via website before API downloads work
- The KGAT token format (introduced 2024) uses `~/.kaggle/access_token`
- Legacy format (`kaggle.json` with username/key) is deprecated for new tokens
