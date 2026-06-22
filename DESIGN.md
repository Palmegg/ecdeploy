# ecDeploy — design

Next-gen rebuild of **SpeedTune**. A WPF (Windows PowerShell 5.1) provisioning utility a
technician runs on a freshly deployed Windows machine *after* signing in, to keep it awake
during provisioning and unstick stalled Intune Win32 app installs.

> Predecessors kept for reference only in `legacy/`: `Speedtune.ps1` (WinForms launcher),
> `Countdown_GRS.ps1`, `GRS.ps1`. Understand the *intent* from them, not the implementation.

## Execution context
- Runs in the **interactive user session**, post sign-in. The user must be a **local admin**.
- **Self-elevates** at launch (one expected UAC prompt). If elevation is declined/impossible →
  warn and run **degraded** (privileged actions disabled). Admin state is shown as a header chip.

## Runtime & packaging
- **Windows PowerShell 5.1**, **STA**, .NET Framework WPF — guaranteed on any fresh image, zero prereqs.
- **One self-contained `ecDeploy.ps1`** — embedded XAML (here-string), one function per action,
  `#region` organization. Ships as-is (no build step). A `$Version` constant is shown in the header.

## Delivery
- **Primary:** `irm ecd.qwe.dk | iex` → tiny **`index.ps1`** → downloads `ecDeploy.ps1` to
  `%TEMP%` → launches `powershell.exe -NoProfile -ExecutionPolicy Bypass -STA`.
- **Fallback:** **`ecDeploy.bat`** — keeps SpeedTune's Cloudflare ping / no-network guard,
  modernized to the new host + `curl.exe` + `-STA`.
- Host: **`ecd.qwe.dk`** (alias `ecdeploy.palme3.dk`), replacing `ast.oo.dk/SpeedTune/`.
- **Always-fresh:** every launch pulls the latest script. No in-app updater.

## UI (dark, flat, minimalist, fixed-size, standard chrome)
- **Header:** `⚫ ecDeploy` wordmark + live chips — **Admin**, **Online**, **No Sleep**, version.
- **Left rail:** actions (Automatisk sekvens / No Sleep / Opdater GRS) on top; utility buttons
  below a divider — **IME-logs**, **Programmer** (`appwiz.cpl`), **Jobliste** (`taskmgr`).
- **Main panel:** controls for the selected action + an **inline live status/log pane**.
- **Danish** UI + on-screen log text; **English** code identifiers/comments.
- A visible **reminder banner** while No Sleep is active: ecDeploy must stay open to prevent sleep.
- No ASCII art, no spawned consoles. Worker-windows are a fallback-only escape hatch.

## Actions
1. **No Sleep** — `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED)`,
   keeps **system + screen** awake. Default **indefinite** (until stop/close); **option** to bound
   to a **24h** auto-release timer. Global toggle, reflected in the header chip.
2. **Opdater GRS** — enumerate **all** context nodes under
   `HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps`, delete **every** `GRS` subkey
   found, then **restart IME once**; report how many were cleared. Fireable anytime, behind a
   confirm (it restarts IME). "None found" / "Win32Apps absent" = friendly info, not an error.
   If the IME service is absent → clear GRS anyway, skip the restart with a message.
3. **Automatisk sekvens** — No Sleep ON immediately → **editable countdown (default 45 min)** →
   **one-time** GRS refresh + IME restart → **stay awake** afterward. While running it **owns** the
   No Sleep state + scheduled GRS (manual controls disabled, marked "styret af sekvens"); **Stop**
   hands control back and releases No Sleep. One sequence at a time. **Never** restarts IME on a loop.

## Behavior & robustness
- UI never blocks: power API returns instantly; countdowns via **`DispatcherTimer`**; registry +
  service work runs on a **background runspace**, with messages marshaled back via a thread-safe
  queue drained on the UI thread.
- **Process-bound** keep-awake: closing/crashing releases the flag → sleep resumes. **Confirm-on-close**
  while No Sleep / sequence is active. Minimize to keep running.
- **Never self-terminate on error** (the old `Stop-Process $PID` pattern is gone). Every action is
  try/caught and reports to the log; the app stays alive. Missing IME / missing GRS / missing
  Win32Apps are normal info states.

## Logging
- Persistent, appended, timestamped: **`C:\ProgramData\ecDeploy\ecDeploy.log`** (action start/stop,
  elevation, GRS counts per context, IME restart result, full exceptions). Shown live in-app, plus
  **View log** and **Open IME logs** (`C:\ProgramData\Microsoft\IntuneManagementExtension\Logs`).

## Exit cleanup
- Release the power/keep-awake flag only. Leave `%TEMP%\ecDeploy.ps1` in place. The log persists.
