# Mars for Herdr

A [Herdr](https://herdr.dev) plugin for DigitalOcean Managed Agents Runtime Services (M.A.R.S).
It lets you start, attach to, and manage hosted coding-agent sessions (Claude Code, Codex, OpenCode, and custom harnesses) without leaving your Herdr workspace.

Every action opens a small popup that walks you through a picker or two, then runs `doctl` for you.
Long-running things such as attaching to a session, replaying logs, or the Codex proxy open in a split pane next to the pane you are working in.

## What it does

| Action | What happens |
| --- | --- |
| `start` | Pick a manifest (`agents.yaml`), a saved Agent Config, or a bare harness. Optionally set a name, a GitHub repo to clone, and an initial prompt. The session starts and attaches in a new split pane. |
| `attach` | Pick a live session and attach to it in a split pane. Ctrl-D detaches and keeps the session alive. |
| `dashboard` | Browse all sessions and act on one: attach, logs, show, pause, resume, checkpoint, proxy, exec, port-forward, upload, download, remove. Also jumps to the Agent Configs list. |
| `configs` | Browse your team's saved Agent Configs. Show a config's manifest, start a session from it, list its sessions, delete it, or create a new one from a local manifest. |
| `logs` | Replay a session's event history in a split pane. |
| `pause` / `resume` / `remove` | Lifecycle operations with a picker filtered to the sessions that make sense for each. `remove` asks for confirmation. |
| `proxy` | Start the Codex proxy for a session, wait until it listens, then start a local Codex agent in a Herdr pane bridged to it. |
| `exec` | Run one shell command inside a session sandbox and show the output. |
| `port-forward` | Forward local ports into a session sandbox. |
| `upload` / `download` | Move files in and out of a session workspace. Selected text in the terminal is used as the default path. |
| `checkpoint` | Save a checkpoint for a session, with an optional label. |
| `validate` | Run the client-side manifest validator on a spec file. |
| `new-spec` | Write an `agents.yaml` from a bundled template, then optionally validate it. |
| `doctor` | Check doctl, authentication, API reachability, jq, fzf, and plugin configuration. |

Herdr shows a notification when a lifecycle action finishes, so you can keep working while a session starts.

## Requirements

- Herdr 0.9.0 or newer on Linux or macOS.
- A doctl build that includes the Managed Agents commands.
  The plugin looks for `doctl-beta` first, then `doctl`, and checks for the `harness-runtime` command group (older betas used `open-harness-runtime`, which is also accepted).
  Set `MARS_DOCTL_BIN` if your build lives elsewhere.
- `doctl auth init` done with a Personal Access Token, and the Managed Agents feature enabled for your team.
- `bash` 4 or newer and `jq`.
- Optional: `fzf` for fuzzy pickers, and the `codex` CLI for the proxy action.

Run the `doctor` action after installing to confirm everything is in place.

## Install

From GitHub:

```sh
herdr plugin install DO-Solutions/herdr-mars-plugin
herdr plugin action invoke digitalocean.mars.doctor
```

From a local checkout while developing:

```sh
git clone git@github.com:DO-Solutions/herdr-mars-plugin.git
herdr plugin link ./herdr-mars-plugin
herdr plugin action list --plugin digitalocean.mars
```

Inside Herdr, run actions with a keybinding instead of the CLI.
Add a `plugin_action` command binding to your Herdr `config.toml`, then run `herdr server reload-config`:

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

## Let an LLM set it up

Copy the prompt in [docs/LLM-SETUP.md](docs/LLM-SETUP.md) into an AI coding agent.
It installs the plugin, runs `doctor`, and walks you through the rest.

The prompt tells the agent to ask before it installs anything or edits your Herdr
config, and never to start, pause, or remove a session as a smoke test.
It will not touch your DigitalOcean credentials; `doctl auth init` stays yours to run.

## Examples

Each example starts from a Herdr pane.
Replace `herdr plugin action invoke digitalocean.mars.<action>` with a keybinding once you have one.

When you invoke an action from a shell, Herdr itself prints a JSON record of the invocation (the action, the context it built, and the log entry).
That is Herdr's CLI output, not the plugin's; the plugin's output goes to the popup and to `herdr plugin log list`.
Silence it with a small alias:

```sh
alias mars='f() { herdr plugin action invoke "digitalocean.mars.$1" >/dev/null; }; f'
mars dashboard
```

### Start an agent on the repo you are looking at

```sh
herdr plugin action invoke digitalocean.mars.start
```

1. Choose "From an agent manifest". The picker lists `agents.yaml` files in the focused pane's directory, its `specs/` and `.mars/` folders, and `MARS_SPEC_DIRS`.
2. Leave the session name blank to keep the manifest's name.
3. Accept the suggested GitHub repo, which comes from your `origin` remote, or clear it.
4. Type an initial prompt such as `Run the test suite and fix any failures`, or leave it blank.

A split pane opens next to your pane, starts the session, and attaches. Answer approval prompts with `y` or `n`. Press Ctrl-D to detach; the session keeps running.

### Try a harness without writing a manifest

```sh
herdr plugin action invoke digitalocean.mars.start
```

Choose "Quick start", pick `claude-code`, `codex`, or `opencode`, and optionally give a repo and prompt.
doctl builds the manifest and prompts for the provider key when it is not in your environment.

### Keep working while the agent works

Detach with Ctrl-D, carry on in your own panes, then come back:

```sh
herdr plugin action invoke digitalocean.mars.attach
```

Pick the session from the list. Paused sessions resume on the first message you send.

### Check on the sandbox without attaching

```sh
herdr plugin action invoke digitalocean.mars.exec
```

Pick the session and enter a command such as `git -C /workspace status --short` or `ls -la /workspace`.
The output opens in a split pane and stays until you press Enter.

To replay everything the agent has done so far:

```sh
herdr plugin action invoke digitalocean.mars.logs
```

### Preview a dev server running in the sandbox

```sh
herdr plugin action invoke digitalocean.mars.port-forward
```

Pick the session and enter `3000`, or `8080:8000` to map local 8080 to sandbox 8000.
Open `http://localhost:3000` in your browser while the pane stays open. Ctrl-C stops the tunnel.

### Move files in and out

Select a filename in your terminal, then:

```sh
herdr plugin action invoke digitalocean.mars.upload
```

The selection becomes the default local file.
Accept the destination or type a path under `/workspace`.

To fetch something the agent produced:

```sh
herdr plugin action invoke digitalocean.mars.download
```

Enter the workspace path, for example `reports/summary.md`; the default save location is the focused pane's directory.

### Save a checkpoint before a risky change

```sh
herdr plugin action invoke digitalocean.mars.checkpoint
```

Pick the session and give it a label such as `before-refactor`.
Checkpoints can only be taken between agent turns, so wait for the agent to finish its current step first.

### Use the native Codex UI against a hosted session

```sh
herdr plugin action invoke digitalocean.mars.proxy
```

Pick a Codex session and accept the port.
One split pane runs the proxy; when it reports it is listening, a second pane starts the local `codex` CLI connected to it through Herdr's agent primitive, so Herdr tracks its idle, working, and blocked states like any local agent.
Without the `codex` CLI installed, the popup prints the `codex --remote ws://127.0.0.1:1144` command instead.

### Create and check a manifest for a new project

```sh
herdr plugin action invoke digitalocean.mars.new-spec
```

Pick a template, accept the suggested session name, and write it to `agents.yaml`.
Say yes to validation, or run it later:

```sh
herdr plugin action invoke digitalocean.mars.validate
```

The validator flags credentials placed under `env:` instead of `secrets:` and conflicting model keys.

### Inspect and reuse Agent Configs

Agent Configs are immutable manifests stored with the Managed Agents API and shared across your team.

```sh
herdr plugin action invoke digitalocean.mars.configs
```

The list shows each config's name, schema version, and creation time.
Pick one, then choose:

- `show manifest` prints the config's metadata and the manifest exactly as the API stores it. Secret values are redacted by doctl.
- `start a session` asks for a session name and an optional prompt, then starts and attaches in a split pane.
- `list sessions` shows every session started from that config with its status.
- `delete` asks for confirmation. The API refuses while sessions from the config are still active, so remove those first.

Choose `+ create a config from a manifest` to publish a local `agents.yaml` as a new config.
The name must be unique within your team, and `${VAR}` placeholders are resolved from your environment when the config is created.
Configs cannot be edited; create a new one to change a manifest.

### Manage everything from one place

```sh
herdr plugin action invoke digitalocean.mars.dashboard
```

The dashboard lists every session with its harness, status, and age.
Pick one, then choose attach, logs, show, pause, resume, checkpoint, proxy, exec, port-forward, upload, download, or remove.
The list also has an entry that opens the Agent Configs browser described above.
Operations that finish in the popup return you to the list; operations that open a pane close the popup so you can use it.

### Bind the two you use most

```toml
[[keys.command]]
key = "prefix+m"
type = "plugin_action"
command = "digitalocean.mars.dashboard"
description = "Managed Agents dashboard"

[[keys.command]]
key = "prefix+shift+m"
type = "plugin_action"
command = "digitalocean.mars.attach"
description = "attach to a managed agent session"
```

Reload with `herdr server reload-config`.

### Clean up when you are done

```sh
herdr plugin action invoke digitalocean.mars.pause    # keep the workspace, stop paying for compute
herdr plugin action invoke digitalocean.mars.remove   # tear the sandbox down, asks for confirmation
```

Sessions also auto-pause after 15 minutes of inactivity.

## Configuration

All settings are optional.
Copy the example file into the plugin's config directory and edit it:

```sh
CONFIG_DIR="$(herdr plugin config-dir digitalocean.mars)"
cp config/env.example "$CONFIG_DIR/.env"
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `MARS_DOCTL_BIN` | auto (`doctl-beta`, then `doctl`) | doctl binary with the Managed Agents commands. |
| `MARS_SPEC_DIRS` | `<config dir>/specs` | Extra directories (colon separated) to search for manifests. The focused pane's directory and its `specs/` and `.mars/` subdirectories are always searched. |
| `MARS_SPLIT_DIRECTION` | `auto` | `right`, `down`, or `auto` (wide panes split right, tall panes split down). |
| `MARS_PROXY_TYPE` | `codex` | Protocol for `start-proxy`. |
| `MARS_PROXY_PORT` | `1144` | Default local proxy port. |
| `MARS_PROXY_AUTOSTART_AGENT` | `1` | Start a local Codex agent in a Herdr pane once the proxy listens. |
| `MARS_AGENT_NAME_PREFIX` | `mars` | Prefix for Herdr agent names created by the proxy action. |
| `MARS_NOTIFY` | `1` | Show Herdr notifications after lifecycle actions. |
| `MARS_USE_FZF` | `auto` | Use fzf for pickers when installed. |
| `MARS_LIST_PAGE_SIZE` | `100` | Sessions fetched per list call. |

Process environment overrides the `.env` file.
Plugin state (last used manifest and session) lives in the Herdr-provided state directory.

## Manifests and credentials

The `start` action looks for flat `agents.yaml` manifests. A minimal one is:

```yaml
name: my-session
agent: claude-code
size: mv-2vcpu-4gb
persistent_workspace: true
env:
  ANTHROPIC_MODEL: sonnet
secrets:
  ANTHROPIC_API_KEY: "${ANTHROPIC_API_KEY}"
permissions:
  default: ask
```

Templates for Claude Code, Codex, OpenCode, DigitalOcean-hosted models, and GitHub private repositories are in `specs/`.
The `new-spec` action copies one into your project.

Two rules from the Managed Agents guide are worth repeating:

- Put credentials under `secrets:`, never under `env:`. Values in `env:` are stored as plain text and are readable inside the sandbox.
- `${VAR}` placeholders are expanded by doctl from your local environment, and doctl prompts in the pane when one is missing. The plugin never reads or stores your provider keys.

The permissions policy behaves differently per agent. Validate a manifest with the `validate` action, then confirm the real behavior on a live session before relying on it.

## How it works

Herdr runs plugin actions headless and logs their output, so each action opens the plugin's `task` popup pane and forwards the invocation context (focused pane and working directory) to it.
The popup runs the interactive part with `fzf` or numbered menus, calls `doctl` through the binary it resolved, and opens split panes through `herdr plugin pane open` for anything long-running.
All calls back into Herdr go through `HERDR_BIN_PATH`, as the Herdr plugin documentation recommends.

Layout:

```text
herdr-plugin.toml   manifest: actions and pane entrypoints
bin/mars            entrypoint: `mars action <task>` and `mars pane`
lib/                config loading, Herdr and doctl wrappers, UI, tasks, pane entrypoints
specs/              manifest templates used by `new-spec`
config/env.example  configuration template
tests/              test suite with fake doctl and herdr binaries
scripts/            lint and test runners
```

## Development

```sh
herdr plugin link .
scripts/test.sh          # shellcheck + bash -n, then the test suite
tests/run.sh proxy       # run only tests whose name contains "proxy"
bin/mars task doctor     # run a task directly in the current terminal
herdr plugin log list --plugin digitalocean.mars
```

Tests run against fake `doctl` and `herdr` binaries in `tests/fakes`, so they need no DigitalOcean account.
The fakes return the same JSON shapes as the real `doctl harness-runtime list -o json` and `herdr plugin pane open` commands.

## Troubleshooting

- "No doctl build with the Managed Agents commands was found": install the doctl beta or set `MARS_DOCTL_BIN`.
- A 404 or maintenance page from doctl means the Managed Agents feature is not enabled for your team yet.
- Nothing happens when invoking an action: check `herdr plugin log list --plugin digitalocean.mars` for the action's output.
- Popups return `ui_busy` while Settings, Copy mode, or another Herdr modal is open. Close it and try again.
- Only one of `attach` and `start-proxy` can stream a session from one machine at a time.

## Trust

This plugin runs `doctl` and `herdr` as your user with your environment.
Review `herdr-plugin.toml` and the scripts before linking or installing, as you would for any plugin.
