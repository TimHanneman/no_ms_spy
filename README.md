# no_ms_spy

A Windows batch script that turns off telemetry and privacy-invasive defaults — and puts them back. Every change is recorded before it is made, so the script can restore the values that were there before it ran.

Runs on Windows 7, 8/8.1, 10 and 11. Only the settings that exist on the detected build are used.

> **Status:** version 2026.09.29. Code review and static checks are complete; the test plan in `tests/TEST_PLAN.md` has not been run end to end yet. Test in a virtual machine with a snapshot before using it on a PC you care about.

---

## Why this one

Most debloat scripts are one-way. This one is built around being reversible:

- **It remembers.** Before changing a value, service start type, scheduled task or optional feature, the script saves what was there into `config\no_ms_spy.cfg`. `R` puts those values back — not Microsoft's defaults, but *yours*.
- **It only writes where it can restore.** A restore is refused for any location outside a fixed allow-list, so a damaged or edited config cannot be used to write elsewhere in the registry.
- **It reads back what it writes.** A filter driver or policy engine can accept a write and silently discard it. A mismatch is reported rather than assumed successful.
- **It fails loudly and safely.** A change that fails does not leave behind a saved value it can never restore, and every failure records the underlying error text in the log.
- **It survives Windows updates.** If an update removes a service, task or app, the restore skips it with a note instead of failing forever or creating a stub.

## What it changes

47 settings, grouped into three profiles. Every setting can also be toggled one at a time.

| Profile | Settings on | Keeps working |
|---|---|---|
| **Work** | 23 | Dictation, Office Editor and translation, clipboard history, recent files, Find My Device, error reports, network browsing for printers and shares |
| **Home** (default) | 33 | NetBIOS for NAS and Samba shares, Teredo for Xbox party chat and multiplayer |
| **Maximum** | 43 | Security settings stay on. Uninstalls OneDrive, Copilot and the new Outlook |

<details>
<summary>Full setting list</summary>

**Telemetry and diagnostics:** `TELEMETRY` · `PUSH_SERVICE` · `ERROR_REPORTING` · `HANDWRITING_SHARING` · `EDGE_DIAGNOSTICS` · `OFFICE_TELEMETRY` · `OFFICE_CONNECTED` · `DEV_TOOLS_TELEMETRY`

**Advertising and personalization:** `ADVERTISING_ID` · `TAILORED_EXPERIENCES` · `SUGGESTED_CONTENT` · `START_RECOMMENDATIONS` · `WIDGETS` · `INPUT_PERSONALIZATION` · `ONLINE_SPEECH`

**Search:** `WEB_SEARCH` · `CLOUD_SEARCH` · `SEARCH_HIGHLIGHTS`

**Tracking and history:** `ACTIVITY_HISTORY` · `APP_LAUNCH_TRACKING` · `RECENT_FILES` · `CLIPBOARD_HISTORY` · `CLIPBOARD_SYNC` · `RECALL`

**Device and account:** `LOCATION` · `CALL_HISTORY` · `PHONE_LINK` · `FIND_MY_DEVICE` · `SETTINGS_SYNC` · `LANGUAGE_LIST` · `DELIVERY_OPTIMIZATION`

**App removal (cannot be undone by this script):** `ONEDRIVE_REMOVE` · `COPILOT_REMOVE` · `OUTLOOK_REMOVE`

**Off by default — read the description first:** `CONNECTIVITY_CHECK` · `UPDATE_NOTIFY` · `ACTIVATION_VALIDATION` · `DEFENDER_CLOUD` · `DEFENDER_SAMPLES` · `SMARTSCREEN`

**Local network chatter (Advanced menu):** `LLMNR` · `NETBIOS` · `MDNS` · `SSDP_UPNP` · `NETWORK_PUBLISHING` · `LLTD` · `TEREDO`

</details>

## Getting started

1. Download the latest release, or clone the repository.
2. Run `no_ms_spy.bat`. It asks for administrator rights itself.
3. Choose **I** to install to `C:\Program Files\no_ms_spy`, where only administrators can change it. The installed copy then starts.
4. Choose **P** to pick a profile, or **C** to go through the settings one at a time.
5. Restart to finish.

Partner/OEM scripts and the connectivity check rotation only run from the installed copy, because an uninstalled copy sits in a folder other programs may be able to write to.

### Menu

```
A  Apply settings
P  Pick a profile: Work, Home or Maximum - least to most privacy
C  Choose settings one by one and save them
R  Put back the settings from before this script
W  Reset every setting to the Windows default
S  Show current status
I  Install to Program Files
U  Uninstall: put everything back and remove the installed copy
V  Advanced options
X  Exit
```

Under **V, Advanced**:

1. Local network chatter settings (LLMNR, NetBIOS, mDNS, SSDP/UPnP and so on)
2. Detect partner and OEM software
3. Run the partner and OEM scripts listed in the config
4. Select an offline Windows installation
5. Detach the offline Windows installation
6. Reapply the settings at every sign-in

## Layout

```
no_ms_spy\
  no_ms_spy.bat              launcher - start this one
  scripts\
    no_ms_spy_main.bat       the menu and all settings
    ncsi_rotate.ps1          connectivity check rotation
    oem_template.bat         template for partner scripts
    oem\                     your partner scripts go here
  config\                    created on first run
    no_ms_spy.cfg            selections and the values from before
    ncsi_state.txt           rotation state
  logs\
    no_ms_spy.log
    ncsi_rotate.log
  tests\                     not installed
    snapshot.ps1             records everything the script can change
    TEST_PLAN.md
```

## Features

### Reapply at every sign-in

Windows updates and some apps turn these settings back on. Advanced option 6 creates a scheduled task that reapplies your saved configuration one minute after you sign in, with administrator rights and no prompts. It runs on battery, fires only for the account that created it, and `R`, `W` and `U` remove it so it cannot undo them.

### Connectivity check rotation

Windows checks for internet access by contacting `msftconnecttest.com`, which tells Microsoft when every network you join comes up. `CONNECTIVITY_CHECK` installs a task that rotates the check between providers (Microsoft, Mozilla, Apple, GNOME, Arch, Fedora) and rotates the DNS check between the root server names. Each provider is verified before use: the reply must match the expected pattern, be identical across two requests and be under 1 KB, and each candidate user agent matches what that provider normally receives.

If Windows rejects a provider — reporting no internet while the provider answers correctly — it is dropped after three runs. If two providers are rejected, the script assumes a Windows update changed how the check works and falls back to the Windows default.

### Offline mode

Boot something like Hiren's BootCD PE and fix a Windows installation that will not start (`V` → 4). The target's registry hives are loaded, changed, and written back on detach. It refuses to work on a target that was hibernated or shut down with Fast Startup, unless you discard the saved session, because resuming it would undo the changes or damage the file system.

Each offline PC keeps its saved values in its own file on the recovery disk, so values from one PC are never applied to another.

### Partner and OEM software

Advanced option 2 looks for vendor telemetry services from NVIDIA, Intel, AMD, Dell, HP, Lenovo, ASUS, Razer, Logitech, Adobe, Google and Mozilla. To handle one, copy `scripts\oem_template.bat` into `scripts\oem\`, fill it in, and add an `OEM_SCRIPT=name.bat` line to the config. The script is called with `apply` or `restore` and inherits the registry root variables so it works offline too.

### Uninstall

`U` puts back every saved value, runs your OEM scripts' restore step, removes the scheduled tasks, event log source and Task Scheduler folder, then deletes the install folder. If anything cannot be put back it stops and asks whether to keep the install or finish anyway, logging exactly what was left as-is.

## Before you use it

- **Test in a VM first.** The test plan in `tests/TEST_PLAN.md` has not been completed.
- **App removals cannot be undone by this script.** OneDrive, Copilot and the new Outlook must be reinstalled from Microsoft or the Store. Deleting the `OutlookUpdate` key also means Windows may not offer the new Outlook again on its own.
- **HKCU settings apply to the account the script runs under.** If you elevate with a different admin account, the per-user settings land on that account. Run it from the account you want changed.
- **On a work or school PC, ask IT first.** The script warns once when it detects a domain, Entra ID or Intune. Group Policy will override these settings at each refresh and fight with the reapply task.
- **Some settings weaken security or lose features.** `DEFENDER_CLOUD`, `SMARTSCREEN` and `UPDATE_NOTIFY` are off by default for that reason. `LOCATION` breaks automatic time zone and Find My Device; `INPUT_PERSONALIZATION` and `ONLINE_SPEECH` break voice typing; turning off LLMNR, NetBIOS and mDNS together leaves only DNS for finding devices by name.
- **Some values Windows protects.** On recent Windows 11 builds the User Choice Protection Driver blocks the Widgets policy value even for administrators. The script detects this, points you at the matching setting in `gpedit.msc`, and does not count it as a failure.

## Testing

`tests\snapshot.ps1` records every registry value, service, scheduled task, optional feature, app and the time zone the script can change — reading that list out of `no_ms_spy_main.bat` itself, so it stays current. The core regression test:

```powershell
powershell -ExecutionPolicy Bypass -File tests\snapshot.ps1 -Out before.json
# run no_ms_spy.bat: Apply, then R
powershell -ExecutionPolicy Bypass -File tests\snapshot.ps1 -Out after.json
powershell -ExecutionPolicy Bypass -File tests\snapshot.ps1 -Compare before.json,after.json
```

The two snapshots must match except for the app removals. `-Compare` exits with 1 when there are differences.

`tests\TEST_PLAN.md` has the environment matrix and 37 test cases across install, apply and restore, system states, reapply, rotation, offline mode and uninstall.

## Contributing

To add a setting:

1. Add a `call :define NAME MINIMUM_BUILD DEFAULT "Description"` line, using the build number of the Windows version that first had the setting.
2. Write `:apply_NAME` and `:restore_NAME` sections. Use the `:set_dword`, `:set_string`, `:delete_value`, `:disable_service` and `:disable_task` helpers — they record the previous value for you.
3. If it writes outside `HKLM\SOFTWARE\Policies` or `HKCU\SOFTWARE\Policies`, add the location to `:define_allowed`, or the restore will refuse it.
4. Add it to the profiles in `:set_profile` and update the counts shown in `:pick_profile`.
5. Use `%SW%`, `%SYS%` and `%CU%` rather than `HKLM\SOFTWARE`, `HKLM\SYSTEM\CurrentControlSet` and `HKCU`, so the setting works on an offline installation.

Keep every file ASCII with CRLF line endings. `cmd` will not run a batch file whose line endings were converted to LF — it reports `The input line is too long`.

