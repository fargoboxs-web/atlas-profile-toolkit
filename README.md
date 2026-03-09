# Atlas Profile Toolkit

`atlas-profile-toolkit.sh` is a macOS shell tool for people who switch ChatGPT Atlas accounts regularly and do not want to rebuild their browser environment every time.

It treats Atlas like a Chromium-style profile store and gives you a repeatable workflow to:

- save a reusable browser template
- scrub Atlas/OpenAI auth from that template
- seed Atlas staging profiles before the next account switch
- inject the saved template into a newly created active Atlas profile while preserving the current Atlas login

## What It Preserves

- browsing history
- bookmarks
- extensions
- browser preferences
- many third-party site cookies and local storage entries

## What It Intentionally Does Not Preserve In The Template

- `chatgpt.com`
- `openai.com`
- `auth.openai.com`
- related Atlas/OpenAI/Auth0/Sentinel auth cookies and similarly named storage paths

The template is meant to preserve your browser environment without dragging the previous Atlas account back in.

## Default Atlas Paths

The script targets the Atlas layout observed on macOS:

- app: `/Applications/ChatGPT Atlas.app`
- Atlas root: `~/Library/Application Support/com.openai.atlas`
- browser host profiles: `~/Library/Application Support/com.openai.atlas/browser-data/host`

These paths can be overridden with environment variables if your Atlas installation is different.

## Commands

Run from the repository root:

```bash
./scripts/atlas-profile-toolkit.sh <command>
```

Available commands:

- `list`
  Show Atlas profiles found on this machine and mark the active one.

- `refresh-master [name]`
  Refresh the saved master template from a profile, then scrub Atlas/OpenAI auth state from the saved copy.

- `capture-master [name]`
  Backward-compatible alias for `refresh-master`.

- `prepare-switch`
  Copy the scrubbed master into Atlas `login-staging*` profiles and `Default` before the next account login.

- `inject-active`
  Replace the current active Atlas profile with the saved template while restoring the current Atlas/OpenAI auth state on top.

- `restore-active`
  Fallback command that replaces the current active profile with the saved template directly. This is more destructive and usually means logging into Atlas again afterward.

- `open`
  Open ChatGPT Atlas.

## Recommended Workflow

Before the next account switch:

```bash
./scripts/atlas-profile-toolkit.sh refresh-master
./scripts/atlas-profile-toolkit.sh prepare-switch
```

Then log into the new Atlas account.

If Atlas creates a sparse new active profile for that account:

```bash
./scripts/atlas-profile-toolkit.sh inject-active
```

Then reopen Atlas. The target state is:

- current Atlas account stays logged in
- template history, bookmarks, extensions, and third-party site state are injected into that active profile

## Backups

Every overwrite operation creates a timestamped backup under:

```bash
~/.atlas-profile-kit/backups
```

The saved reusable template lives at:

```bash
~/.atlas-profile-kit/master-profile
```

## Safety Notes

- Atlas is closed before live profile data is copied.
- Third-party site sessions are best-effort. Some sites will still require re-login.
- If Atlas changes its internal profile layout in a future release, the matching rules may need updates.

## Test

Run the shell integration test with:

```bash
bash ./tests/test_atlas_profile_toolkit.sh
```
