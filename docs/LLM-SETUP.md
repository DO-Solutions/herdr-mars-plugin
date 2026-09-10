# Mars for Herdr: LLM setup prompt

Copy everything below the line into an AI coding agent.
That agent should install and configure the **Mars** Herdr plugin for you.

---

You are setting up the **Mars** Herdr plugin (`digitalocean.mars`), which drives
DigitalOcean Managed Agents Runtime Services (M.A.R.S) from Herdr panes.

Follow every step in order. Every step is safe to re-run: check the current state
first and skip, merge, or report rather than redoing work. Do not skip the
confirmation gates.

## Hard rules (do not violate)

1. **Never touch the user's DigitalOcean credentials.**
   Do not run `doctl auth init`, do not read a Personal Access Token out of a
   screenshot or a file, and do not write one anywhere. If auth is missing or
   broken, stop and tell the user to run `doctl auth init` themselves.

2. **Verification is read-only. Never run a lifecycle action as a smoke test.**
   `remove`, `pause`, `resume`, `checkpoint`, `start`, and `proxy` act on live
   sandboxes that cost money and may hold the user's in-progress work. `remove`
   destroys a session. Confirm the install with `doctor` and list calls only.
   If the user wants a live session started, that is their explicit request, not
   part of setup.

3. **Never overwrite the user's Herdr config.**
   Append new `[[keys.command]]` blocks to `~/.config/herdr/config.toml`. Do not
   rewrite unrelated sections and do not regenerate the file. Back it up first.
   Check for key conflicts before writing (step 6) and ask rather than stealing
   a key that is already bound. Appending to a key nothing else uses is not
   overwriting, and needs no permission.

4. **Ask before installing anything on the user's machine.**
   That includes `fzf`, `jq`, `bash`, `doctl`, and any Homebrew or package
   manager call. Report what is missing and what it would cost them, then wait.

5. **Do not "fix" the bash version without evidence.**
   The README asks for bash 4 or newer. macOS ships bash 3.2, and the plugin has
   been observed to pass all `doctor` checks on it. Run `doctor` first. Only
   raise the bash version if `doctor` actually fails in a way that points at it.
   Never modify the user's login shell.

6. **Do not report success from an action invocation, or from the plugin log.**
   Both report that a popup opened, never that the work succeeded. `doctor` is
   the only thing that tells you the setup is good, and only when you run it the
   way step 3 shows. See "Where output actually goes" below. This is the single
   most common way to get this setup wrong.

## Goal

End state:

- Plugin `digitalocean.mars` installed and enabled.
- `doctor` reports 0 failed checks.
- A doctl build with the Managed Agents commands is resolvable, authenticated,
  and the API answers.
- Optional keybindings added, with conflicts resolved by asking.
- Optional dependencies (`fzf`, `codex`) reported, installed only with consent.
- A short plain-language summary of what changed and what is left for the user.

## Where output actually goes

Read this before running anything. Herdr plugin actions are asynchronous and
render to a popup in the Herdr UI, which you cannot see.

```sh
herdr plugin action invoke digitalocean.mars.doctor
```

This prints a JSON invocation record and exits 0 **before the action finishes**.
That JSON is Herdr's own record of the invocation, not the plugin's output, and
`"status":"running"` is not a result. The check results went to a popup. If you
conclude "doctor passed" from this, you have verified nothing.

The plugin log is the next thing you will reach for, and it does **not** rescue
you either:

```sh
herdr plugin log list --plugin digitalocean.mars --limit 5
```

```json
{"status":"succeeded","exit_code":0,"stderr":"mars: opened Mars popup for task 'doctor'\n"}
```

Read that `stderr` carefully. `"succeeded"` with `exit_code: 0` means **the popup
opened**, not that the checks passed or the action did its job. A `doctor` run
that failed every check logs exactly the same line. The log tells you the action
launched; it never tells you the outcome.

Two details when you do use the log: entries are ordered oldest first, so the run
you just triggered is the **last** element, not the first. And an entry starts as
`{"status":"running","exit_code":null}` and settles a second or two later, so
poll rather than reading once.

So, to actually see output:

| You want | Use |
| --- | --- |
| The `doctor` check results | `bin/mars doctor` run directly, exactly as step 3 shows |
| Whether an action even launched | `herdr plugin log list --plugin digitalocean.mars --limit 5` |
| What the plugin can do | `herdr plugin action list --plugin digitalocean.mars` |

For anything interactive (`start`, `dashboard`, `attach`, `configs`), there is no
programmatic way to read the result. Those need a human at the Herdr UI. Do not
invoke them to check your work.

One more constraint: popups fail with `ui_busy` while Settings, Copy mode, or any
other Herdr modal is open. If an action logs `ui_busy`, ask the user to close the
open modal rather than retrying in a loop.

## Steps

### 1. Prerequisites

Check each and record the result. Do not install anything yet (hard rule 4).

```sh
herdr --version                 # need 0.9.0 or newer
uname -s                        # Darwin or Linux only
command -v jq                   # required
command -v fzf                  # optional: fuzzy pickers, else numbered menus
command -v codex                # optional: the proxy action can auto-connect it
```

For doctl, the plugin probes `MARS_DOCTL_BIN`, then `doctl-beta`, then `doctl`,
and requires the `harness-runtime` command group (older betas exposed it as
`open-harness-runtime`, which is also accepted):

```sh
for bin in doctl-beta doctl; do
  command -v "$bin" >/dev/null || continue
  "$bin" harness-runtime --help >/dev/null 2>&1 && echo "$bin: ok"
done
doctl account get               # confirms auth; do NOT run `doctl auth init` yourself
```

If no binary has the command group, stop and tell the user to install the doctl
beta or set `MARS_DOCTL_BIN` (step 4). If `account get` fails, stop and tell them
to run `doctl auth init` with a Personal Access Token. A 404 or a maintenance
page from a `harness-runtime` call means Managed Agents is not enabled for their
team yet, which is an account issue you cannot fix from here.

### 2. Install the plugin

Inspect current state first:

```sh
herdr plugin list
```

- If `digitalocean.mars` is already installed from
  `DO-Solutions/herdr-mars-plugin` and enabled, skip to step 3. Do not reinstall.
- If it is installed but disabled, run `herdr plugin enable digitalocean.mars`.
- **Plugin-id collision:** if a different plugin claims `digitalocean.mars` (a
  locally linked dev tree, for instance), installing conflicts. Tell the user
  what you found, get their OK, then remove the old one first with
  `herdr plugin unlink digitalocean.mars` (linked) or
  `herdr plugin uninstall DO-Solutions/herdr-mars-plugin` (installed).

Then install. `--yes` is **required** whenever stdin is not interactive, which is
always the case when an agent runs the command:

```sh
herdr plugin install DO-Solutions/herdr-mars-plugin --yes
```

Verify with `herdr plugin list`. Expect `digitalocean.mars` marked `enabled`, and
`herdr plugin action list --plugin digitalocean.mars` to report 14 actions.

### 3. Verify with doctor

`herdr plugin list` prints the plugin's **config** directory, never its **root**.
You need the root to reach `bin/mars`, and the directory name carries a hash
suffix, so you have to search for it:

```sh
ROOT="$(find "${XDG_CONFIG_HOME:-$HOME/.config}/herdr/plugins/github" \
  -maxdepth 1 -type d -name 'digitalocean.mars-*' -print -quit 2>/dev/null)"

if [ -z "$ROOT" ] || [ ! -f "$ROOT/bin/mars" ]; then
  echo "Mars plugin root not found. Check: herdr plugin list"
  exit 1
fi

HERDR_PLUGIN_CONFIG_DIR="$(herdr plugin config-dir digitalocean.mars)" \
  bash "$ROOT/bin/mars" doctor </dev/null
```

Use `find`, not a shell glob. A glob that matches nothing expands to the literal
pattern in bash, so `bash "$ROOT/bin/mars"` fails with a confusing
`No such file or directory` and exit 127 that reads like a broken install rather
than a missing one. In zsh the same glob is a hard error instead. `find` gives
you an empty string in both shells, which the guard turns into a clear message.

Three more things about that command.

Redirecting stdin from `/dev/null` matters: `doctor` ends with a "Press Enter to
close" hold. With no tty it returns immediately and exits 0 when every check
passes, so the exit code is a usable gate. Unlike the action invocation, this
prints the check results to stdout where you can read them.

Setting `HERDR_PLUGIN_CONFIG_DIR` matters just as much, and it is easy to skip.
Herdr sets that variable when it runs an action. You are not Herdr, so without it
`doctor` reports a *different* config directory than the one real actions use,
and every path in its output is misleading. Compare:

```
# without the variable
· config dir: ~/.config/herdr-mars-plugin (no .env, defaults in use)
# with it
· config dir: ~/.config/herdr/plugins/config/digitalocean.mars (no .env, defaults in use)
```

Both are the same binary on the same machine. Step 4 explains why this matters.

Finally, `doctor`'s exit code is the best gate available here (0 when the tally
says `0 failed`, 1 otherwise), which is why the setup hangs off it. But read the
next paragraph before you rely on it alone.

A healthy run looks like this:

```
✔ doctl with Managed Agents commands: doctl harness-runtime (doctl version 1.167.0-beta)
✔ doctl auth: you@example.com
✔ Managed Agents API reachable (session list succeeded).
✔ jq
✔ fzf (fuzzy pickers enabled)
✔ codex CLI (proxy action can auto-connect it)
✔ herdr 0.9.0 via /path/to/herdr
· config dir: ...
· state dir:  ...

4 checks passed, 0 failed.
```

**Do not be alarmed that the tally disagrees with the checkmarks.** Seven `✔`
lines above, but the summary says `4 checks passed`. That is not a failure and
not your mistake: only the doctl, auth, API, and jq checks increment the counter.
The fzf, codex, and herdr lines print a mark without counting.

**Read the `✘` marks, do not just read the tally.** The herdr check has the same
gap on the failure side: it can print `✘ herdr binary not reachable` without
incrementing the failed count, so that one check can fail while the summary still
says `0 failed` and the exit code is still 0. Treat the pass condition as *both*
`0 failed` *and* no `✘` anywhere in the output. Lines starting with `·` are
informational and never failures. If any `✘` appears, fix that specific check
before continuing; do not proceed and hope.

### 4. doctl resolution and where `.env` actually goes

Only needed if step 1 found a working doctl under a name the plugin does not
probe, or in a non-standard location.

Resolve the config directory with the CLI. Do not guess it, and do not use the
path `doctor` prints:

```sh
CONFIG_DIR="$(herdr plugin config-dir digitalocean.mars)"
```

**This is a real trap.** When Herdr runs an action it sets
`HERDR_PLUGIN_CONFIG_DIR`, and the plugin reads `.env` from there. When you run
`bin/mars` standalone that variable is unset, so `mars_config_dir()` falls back
to `~/.config/herdr-mars-plugin` and `doctor` reports *that* path. An `.env`
written to the path standalone `doctor` printed is silently ignored when the
action actually runs from Herdr. Always use `herdr plugin config-dir`.

```sh
printf 'MARS_DOCTL_BIN=%s\n' "/path/to/your/doctl" >> "$CONFIG_DIR/.env"
```

Other settings are optional and documented in the README's Configuration table
(`MARS_SPEC_DIRS`, `MARS_SPLIT_DIRECTION`, `MARS_PROXY_PORT`, and so on). A
starting point ships as `config/env.example` in the plugin root. Process
environment overrides the `.env` file.

Re-run step 3 after any change here.

### 5. Optional dependencies

Report, then ask (hard rule 4). Neither blocks setup.

- **`fzf`** turns the session, manifest, and config pickers into fuzzy-searchable
  lists. Without it the plugin uses numbered menus, which work fine. Worth it
  once the user has more than a handful of sessions.
- **`codex`** lets the `proxy` action auto-start a local Codex agent bridged to a
  hosted session. Without it, `proxy` prints connection instructions instead.

If the user agrees, install with their platform's package manager, then re-run
step 3 to confirm `doctor` now sees them.

### 6. Keybindings (conflict check, then apply)

**When no key is already taken, add the bindings. Do not stop to ask.** Appending
to a free key is the expected outcome of this step, and treating it as a consent
gate leaves the user with a half-finished setup and a question they did not need
to answer. Back up the file first, tell them what you added afterwards, and move
on.

You must stop and ask in exactly one case: a recommended key is already bound to
a **different** command (step 6.4). That is the conflict gate, and it is the only
one here. If the user has separately said they do not want keybindings, skip the
whole step; actions can always be invoked from the CLI instead.

Recommended bindings from the README, both using Herdr's `prefix` mode:

| Purpose | `command` value | Recommended `key` |
| --- | --- | --- |
| Sessions dashboard | `digitalocean.mars.dashboard` | `prefix+m` |
| Start a session | `digitalocean.mars.start` | `prefix+shift+m` |

1. Read the active config: `~/.config/herdr/config.toml`, or `$HERDR_CONFIG`, or
   `$XDG_CONFIG_HOME/herdr/config.toml`.
2. For each recommended key, check whether another `[[keys.command]]` already
   uses it, and note which command holds it:

```sh
CFG=~/.config/herdr/config.toml
for k in "prefix+m" "prefix+shift+m"; do
  if grep -q "^key = \"$k\"$" "$CFG"; then
    echo "CONFLICT: $k -> $(grep -A 2 "^key = \"$k\"$" "$CFG" | grep '^command = ' | head -1)"
  else
    echo "free: $k"
  fi
done
```
3. If a binding for the same `digitalocean.mars.*` command already exists with
   the recommended key, leave it alone and report it as already configured.
4. If a **different** command holds a recommended key, stop and ask the user
   which key to use instead. Do not guess and do not steal the binding.
5. Tell the user what you are about to add, back up the file, then append only
   the missing blocks:

```sh
cp ~/.config/herdr/config.toml ~/.config/herdr/config.toml.bak
```

```toml
[[keys.command]]
key = "prefix+m"
type = "plugin_action"
command = "digitalocean.mars.dashboard"
description = "Managed Agents dashboard"

[[keys.command]]
key = "prefix+shift+m"
type = "plugin_action"
command = "digitalocean.mars.start"
description = "start a managed agent session"
```

6. Reload and confirm the config parsed:

```sh
herdr server reload-config
```

**`reload-config` exits 0 even when it rejects your config.** Checking `$?` here
tells you nothing, exactly like the action invocation in "Where output actually
goes". You must parse the JSON:

```json
{"status":"applied","diagnostics":[]}
```

That is success. A rejection looks like this, still with exit code 0:

```json
{"status":"failed","diagnostics":["config parse error: TOML parse error at line 9, column 15\n ... ; keeping current config"]}
```

Note `keeping current config`. Herdr does not break when handed bad TOML, it
keeps what it already had. That is good for the user and a trap for you: your
edit simply did not take, the command looked like it worked, and the only symptom
is a keybinding that silently does nothing.

So: require `"status":"applied"` **and** an empty `diagnostics`. On anything else,
restore the backup, reload again to confirm you are back to a good state, and
report the parse error to the user rather than retrying.

### 7. Manifests (orientation only, do not create sessions)

The `start` action looks for flat `agents.yaml` manifests in the focused pane's
directory, its `specs/` and `.mars/` subdirectories, and any directory in
`MARS_SPEC_DIRS` (default `<config dir>/specs`).

If the user's working directory has no manifest, the picker comes up empty. Tell
them, and point at the `new-spec` action, which copies a template from the
plugin's `specs/` directory (Claude Code, Codex, OpenCode, DigitalOcean-hosted
models, GitHub private repositories).

Two rules worth repeating to the user, both from the Managed Agents guide:

- Credentials go under `secrets:`, never `env:`. Values in `env:` are stored as
  plain text and are readable inside the sandbox.
- `${VAR}` placeholders are expanded by doctl from the local environment, and
  doctl prompts in the pane when one is missing. The plugin never reads or stores
  provider keys.

Do not start a session to demonstrate this (hard rule 2).

### 8. Read-only smoke check

```sh
herdr plugin list
herdr plugin action list --plugin digitalocean.mars
HERDR_PLUGIN_CONFIG_DIR="$(herdr plugin config-dir digitalocean.mars)" \
  bash "$ROOT/bin/mars" doctor </dev/null
herdr plugin log list --plugin digitalocean.mars --limit 5
```

All four are non-destructive. Nothing here starts, pauses, or removes a session.

The `doctor` line is the only one of the four that proves the setup works. Treat
its `0 failed` as the pass condition for the whole job.

## Report back

Summarize in plain language:

- Plugin: installed now, or already present and left alone.
- `doctor`: how many checks passed and failed, and the text of any `✘` line.
- doctl: which binary and command group resolved, and the authenticated account.
- Config dir path, and whether you wrote an `.env`.
- Keybindings: which were added, already present, declined, or reassigned after a
  conflict. Mention the backup file if you made one.
- Optional deps: `fzf` and `codex` present or absent, and whether the user
  declined installing them.
- Anything still needing the user: `doctl auth init`, Managed Agents not enabled
  for their team, a missing manifest, a package install they said no to.

Then tell them how to use it: `prefix+m` for the dashboard and `prefix+shift+m`
to start a session if bindings were added, otherwise
`herdr plugin action invoke digitalocean.mars.dashboard`. Remind them that action
output appears in a Herdr popup, not the terminal they invoked from.

## Reference

- Plugin id: `digitalocean.mars`
- Install: `herdr plugin install DO-Solutions/herdr-mars-plugin --yes`
- Plugin root (use `find`, not a glob): `find "${XDG_CONFIG_HOME:-$HOME/.config}/herdr/plugins/github" -maxdepth 1 -type d -name 'digitalocean.mars-*' -print -quit`
- Config dir: `herdr plugin config-dir digitalocean.mars`
- Readable doctor:
  `HERDR_PLUGIN_CONFIG_DIR="$(herdr plugin config-dir digitalocean.mars)" bash "$ROOT/bin/mars" doctor </dev/null`
- Action launched (not action succeeded):
  `herdr plugin log list --plugin digitalocean.mars --limit 5`
- Full documentation: the repository `README.md`
