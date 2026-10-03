# Worker Setup and Recovery

The optional worker needs Python 3.10+ and a signed-in Codex CLI. Any existing
project directory works. `--project` chooses notes; `--workspace` chooses the
repository the AI may edit. Refer to README examples for list/show/export/work.

`work --model MODEL_ID` overrides a model configured for the desktop app that
your CLI account may not support. Model availability depends on the account
and client; choose an available ID using the
[official model guidance](https://learn.chatgpt.com/docs/models).
`work --isolated` skips global user configuration and unrelated MCP connections
while retaining CLI authentication. It does not change your saved configuration.
Without these flags, the worker uses your normal CLI configuration.

On Windows, `work --windows-sandbox unelevated` or `elevated` explicitly selects
the documented Windows sandbox implementation for this invocation. This can
be useful with `--isolated`, which skips your saved Windows configuration.
Neither option bypasses filesystem access controls or managed policies.

New workspaces can default to read-only until trusted by the CLI. For a project
you own and intend to authorize, `work --trust-workspace` declares only that
workspace trusted for this invocation and retains the workspace-write sandbox.
It does not persist trust settings or bypass managed policies. See
[official permission guidance](https://learn.chatgpt.com/docs/agent-approvals-security).

An optional live fixture check (uses your AI account) is:

```sh
python tools/smoke_worker.py --model YOUR_CLI_MODEL
```

This verifies that the worker resolves a note and changes only the intended
object in a temporary JSON fixture. It is not a live 3D mesh-repair test.

The release's local Windows live check did not complete: the sandbox denied
access to the temporary fixture. Automated tests use a simulated CLI; actual
AI project editing remains unverified in that environment. If access is denied,
stop and fix the CLI's documented workspace permissions before retrying. A
Review status means the CLI returned a report, not that the requested edit succeeded.

Only Queued instructions run. An empty instruction is Blocked. The worker
requests source resolution, scoped edits, verification, and a report. This
does not guarantee a requested asset repair will succeed. Review actual changes.
Keep the computer awake and connected. Reports live under `.canvas/runs/`.

Errors, interruption, and the default 1800-second timeout become Blocked.
Cleanup attempts to stop the worker process tree. Stop watch mode with Ctrl+C.
Inspect surviving processes and changes before retrying.

After a crashed worker left a Working note, stop any surviving workers, inspect
the changes, and run:

```sh
python canvas.py --project /path/to/project recover NOTE_ID
```

Recovery sets Blocked, not Queued. Remove abandoned `notes.json.lock` directories
only after confirming writers stopped. Restore malformed files from history.

Create a note in any engine or non-engine project:

```sh
python canvas.py --project /path/to/project create --name "Broken corner" --engine custom --scene "room/main" --position 2 3 4 --instruction "Bevel this corner"
```

Other AI tools can use exported prompts or read files directly. The bundled
worker does not supply a live scene-editing transport or automatic publishing.
