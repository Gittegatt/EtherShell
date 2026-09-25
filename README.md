# EtherShell

**EtherShell** is a PowerShell-based Windows network utility for managing network adapters, IPv4 configuration, reusable network presets, Wi-Fi profiles, Internet/VPN diagnostics, PowerShell maintenance, and interactive ping diagnostics from one terminal interface.

Current tool version: **v1.1.0**

Project website: https://github.com/Gittegatt/EtherShell  
GitHub profile: https://github.com/Gittegatt/

---

## Highlights

EtherShell provides:

- Live adapter, IPv4, Internet, VPN, and preset status in interactive menus
- DHCP and static IPv4 configuration with validation and best-effort rollback
- Reusable network presets with IDs, direct execution, and active-preset detection
- Wi-Fi scanning, connection, saved-network management, and adapter controls
- VPN endpoint and DNS diagnostics with configurable test URLs
- Ping diagnostics with RTT history and exports in a separate window
- An integrated manual, PowerShell update check, and release check
- Persistent settings, an administrator shortcut, and optional Vibrant Mode

---

## Requirements

- Windows 10 or later
- PowerShell **7.5.1 or newer**
- Administrator privileges for network-changing actions
- WinGet is recommended for PowerShell installation and update functions

EtherShell checks the PowerShell edition and version during startup.

The normal network-management mode automatically requests elevation when required. The separate Manual and Ping Diagnostics windows do not request another UAC elevation.

---

## Installation / First Run

1. Download or clone the repository.
2. Keep `ethershell.ps1`, `ethershell-v2.ico`, and `Start-ethershell.cmd` in the same folder.
3. Start EtherShell using either:

   ```text
   Start-ethershell.cmd
   ```

   or run the script directly from PowerShell 7:

   ```powershell
   pwsh -File .\ethershell.ps1
   ```

4. Use the generated `EtherShell.lnk` shortcut for future launches. On first run, EtherShell checks PowerShell, initializes `settings.json`, selects an adapter, and checks for a newer stable release.

`Start-ethershell.cmd` expects PowerShell 7 at the normal `%ProgramFiles%\PowerShell\7\pwsh.exe` location, launches `ethershell.ps1` from the same folder, and requests Administrator elevation.

### Manual shortcut target

If you want to create a shortcut yourself:

```text
"C:\Program Files\PowerShell\7\pwsh.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "Path\to\ethershell.ps1"
```

---

## Main Menu

```text
[1] Network Configuration
[2] Network Information
[3] Network Tools
[4] Wi-Fi
[5] Settings
──────────────────────────────────────────────
[P] Presets    [R] Restart        [Q] Quit
[M] Manual     [A] About/Info
──────────────────────────────────────────────
```

`[P]` lists presets, `[R]` restarts, and `[Q]` quits. Submenus also use `[Q]` to go back. Enter a preset name or ID directly at the main `Go:` prompt:

```text
Go: home
Go: id1
Go: dhcp-auto
```

Preset matching is case-insensitive. Main-menu command names such as `p`, `r`, `m`, `a`, and `q` are reserved and cannot be used as normal preset names.

---

## Main Status Display

The main status block displays values similar to:

```text
Adapter     : Ethernet
Status      : Up
Media State : Connected
Mode        : DHCP
Preset      : dhcp-auto (id0)
IPv4 Address: 192.168.0.100
Gateway     : 192.168.0.1
DNS         : 192.168.0.1
Internet    : Online
VPN         : Not Configured
```

Online or connected states appear green; offline or disconnected states appear dark red. Disabled and unconfigured states appear dark gray. Warnings, including `Connected / DNS unavailable` and multiple preset matches, appear yellow. An exact preset match appears cyan.

---

## Vibrant Mode

Toggle Vibrant Mode under `Settings -> [8]`. It is enabled by default and picks a highlight color for the logo and menu borders at each start. Turning it off restores normal console colors. The separate Manual keeps neutral formatting.

---

## Network Configuration

Open:

```text
Main Menu -> [1] Network Configuration
```

Available functions include:

```text
[1] Select Network Adapter
[2] Enable DHCP / Reapply DHCP Configuration
[3] Configure Static IPv4
[4] Apply Preset
[5] Enable / Disable Network Adapter
[6] Clear IPv4 Configuration
[Q] Back
```

### Select Network Adapter

Selects the adapter EtherShell works with and stores it as the default adapter.

### DHCP

EtherShell can enable or reapply DHCP on the selected interface and can combine DHCP with either DHCP-provided DNS or a custom DHCP DNS preference.

### Static IPv4

Static configuration validates addresses, subnet masks, prefix lengths, gateways, and DNS servers. Supported apply operations first save a configuration snapshot for best-effort rollback if the change fails.

At the final `Apply?` prompt:

```text
Y      -> apply
ENTER  -> apply
N      -> cancel without applying
```

### Enable / Disable Adapter

EtherShell changes the selected adapter state and verifies the result reported by Windows.

### Clear IPv4 Configuration

Clears IPv4 configuration only on the selected adapter.

---

## Network Presets

Manage presets under `Settings -> [1] Network Presets`, or press `[P]` on the main menu for a quick list.

Full management menu:

```text
[1] List Presets
[2] Create Preset
[3] Apply Preset
[4] Delete Preset
[5] Delete All Presets
[Q] Back
```

### Protected system preset

EtherShell always maintains the protected system preset `dhcp-auto` (`id0`). It cannot be deleted or overwritten. Applying it enables DHCP and DHCP-provided DNS on the selected adapter.

### User preset types

User presets store either static IPv4 settings (address, subnet, gateway, and DNS) or DHCP with a custom DNS server. Each preset has a name and ID.

### Preset names

New preset names are:

- normalized to lowercase
- matched case-insensitively
- globally unique
- prevented from conflicting with reserved menu commands or `idN` syntax

### Preset IDs

`id0` is reserved for `dhcp-auto`. User IDs start at `id1` and are unique across adapters. Press ENTER for the smallest unused ID, or enter one manually. If it is occupied, EtherShell asks before replacing the existing preset.

### Active preset detection

EtherShell compares the current Windows configuration with saved presets. An exact match shows the preset name and ID; otherwise it shows `None` or `Multiple`.

---

## DHCP DNS Preference

Open:

```text
Settings -> [3] DHCP DNS
```

This is a general DHCP DNS preference and is separate from reusable DHCP presets.

EtherShell can:

- save/change a custom IPv4 DNS server
- apply it immediately when the selected adapter is using DHCP
- clear it and return to DHCP-provided DNS

For a reusable named configuration, create a DHCP preset instead.

---

## Internet and VPN Status

### Internet

EtherShell tries multiple Internet connectivity endpoints. A failed first endpoint does not immediately make the Internet state `Offline`.

### VPN

Configure up to two VPN test URLs under `Settings -> [4] VPN Test URLs`. A blank value clears the selected slot. URLs without a scheme default to `http://`, so enter `https://` explicitly when required.

#### VPN state detection

EtherShell checks DNS first, then uses short HTTP and TCP checks to test reachability without delaying the menus unnecessarily.

The resulting states are:

```text
Online                       -> configured VPN endpoint is reachable
Connected / DNS unavailable  -> VPN connection appears active, but VPN test DNS cannot resolve
Offline                      -> configured endpoints are not reachable
Not Configured               -> no VPN test URL is configured
Settings Error               -> VPN settings could not be read
```

`Connected / DNS unavailable` means a VPN appears active, but the test hostname cannot be resolved. If it appears after a network change, EtherShell may recommend reconnecting the VPN manually. It does not control third-party VPN software.

---

## Network Information

Open:

```text
Main Menu -> [2] Network Information
```

Functions include:

```text
[1] Selected Adapter Details
[2] All Network Adapters
[3] Full IP Configuration (ipconfig /all)
[4] Internet / VPN Status
[Q] Back
```

---

## Wi-Fi

Open:

```text
Main Menu -> [4] Wi-Fi
```

Menu:

```text
[1] Manage Known Networks
[2] Connect to New Wi-Fi Network
[3] Wi-Fi Adapter Status
[4] Toggle Wi-Fi Interface
[Q] Back
```

Visible and saved networks are listed by SSID and security mode. Where Windows provides the data, EtherShell also shows the cipher, such as `WPA2-Personal / AES/CCMP` or `WPA3-Personal / AES/CCMP`.

### Manage Known Networks

```text
[1] List Known Networks
[2] Show Network Credentials
[3] Connect to Known Network
[4] Forget Network
[Q] Back
```

You can list saved networks, connect to one, or forget a profile after confirmation. EtherShell can display a stored password when Windows exposes it; this is unavailable for some profile types. Temporary WLAN exports are removed after use.

### Connect to New Wi-Fi Network

```text
[1] Search Visible Networks
[2] Hidden / Manual SSID
[Q] Back
```

#### Search Visible Networks

Select a scanned network, enter its password if required, and choose whether Windows should connect automatically. EtherShell creates a WLAN profile and checks the result where WLAN status is available. Open networks and WPA2/WPA3-Personal are supported.

#### Location Services behavior

If Windows blocks WLAN scan or status access because of privacy settings, EtherShell offers to open Location settings. A blocked status read alone does not mean the connection failed.

#### Hidden / Manual SSID

Lets you enter the SSID directly without first performing a visible-network scan, followed by password and automatic-connect preference.

### Wi-Fi Adapter Status

Displays the Windows WLAN interface state.

### Toggle Wi-Fi Interface

Enables or disables the selected Wi-Fi adapter and verifies the resulting Windows adapter state.

---

## Ping Diagnostics

Open:

```text
Main Menu -> [3] Network Tools -> Ping Diagnostics
```

Ping Diagnostics opens in a separate PowerShell window and uses PowerShell `Test-Connection`.

Features include:

- repeated probes
- graphical RTT history
- recent replies
- latency display
- new-target selection
- saved recent target
- result export
- export cleanup

Exports are written to the EtherShell ping-export directory with timestamped filenames.

---

## Settings

Open:

```text
Main Menu -> [5] Settings
```

Menu:

```text
[1] Network Presets
[2] Select / Set Default Adapter
[3] DHCP DNS
[4] VPN Test URLs
[5] About / Version
[6] Check / Update PowerShell
[7] Reset EtherShell Settings
[8] Vibrant Mode: On/Off
[Q] Back
```

### Reset EtherShell Settings

Resets persistent settings to the default structure.

The protected system preset remains part of the defaults:

```text
id0  dhcp-auto
```

The reset also restores Vibrant Mode to its default enabled state and clears any skipped release version.

---

## Release Check

During a normal startup, EtherShell checks the latest stable release published at:

https://github.com/Gittegatt/EtherShell/releases

The check runs **after** normal initialization has completed.

If a newer release is available, EtherShell reports the release version and offers:

```text
[1] Visit the repository website
[2] Skip this version
[Q] Continue without opening the website
```

### Skip this version

`Skip this version` saves the release tag in `settings.json`. EtherShell still shows that the release exists, but suppresses its prompt until a newer release appears.

The check uses GitHub's public latest stable release endpoint.

If the network request fails, EtherShell continues normally and reports that the release check is unavailable.

---

## PowerShell Check / Update

Open:

```text
Settings -> [6] Check / Update PowerShell
```

EtherShell compares the installed PowerShell version with the stable `Microsoft.PowerShell` package visible through WinGet.

The logic distinguishes between WinGet-managed and non-WinGet-managed PowerShell installations and avoids unnecessary parallel installations when the current version is already up to date.

---

## Integrated Manual

Press `[M]` to open the integrated Manual in a separate PowerShell window. It uses a 100-column layout where supported and neutral colors regardless of Vibrant Mode.

---

## About / Info

The About screen shows version and PowerShell information, project links, license, and a short feature overview.

---

## Restart and Window Size

From the main menu:

```text
[R] Restart
```

starts a fresh EtherShell process.

Before restarting, EtherShell records the current console width and height and passes them to the new process. The restarted process attempts to restore those dimensions where the terminal host allows programmatic resizing.

On a normal `[Q] Quit`, EtherShell likewise avoids intentionally changing the current console dimensions and reapplies the captured size where supported.

Terminal applications such as Windows Terminal can impose their own window-management behavior, so dimension preservation is best-effort rather than guaranteed on every host.

---

## Shortcut and Icon Handling

EtherShell creates or refreshes:

```text
EtherShell.lnk
```

The shortcut uses PowerShell 7 and is marked to run with Administrator privileges.

If `ethershell-v2.ico` is present, EtherShell uses it as the shortcut icon.

To reduce stale Windows icon-cache behavior after replacing the icon file, EtherShell creates a content-hashed copy inside:

```text
.ethershell-icon-cache/
```

Changing the icon contents therefore produces a new icon-cache filename.

---

## Persistent Settings

All persistent settings are stored in:

```text
settings.json
```

Example structure:

```json
{
  "ethershell": {
    "defaultAdapter": "Ethernet",
    "lastPingTarget": "8.8.8.8",
    "vibrantMode": true,
    "skippedReleaseVersion": "",
    "network": {
      "dhcpDns": "1.1.1.1",
      "vpnTestURL": [
        "",
        ""
      ],
      "systemPresets": {
        "dhcp-auto": {
          "id": 0,
          "type": "dhcp",
          "dnsMode": "auto",
          "protected": true
        }
      },
      "adapter": {}
    }
  }
}
```

The values above are examples only.

### Settings safety

EtherShell validates and backs up settings during writes, uses temporary files, and coordinates concurrent access between processes such as the main tool and Ping Diagnostics.

---

## Command-Line Modes

Normal mode:

```powershell
pwsh -File .\ethershell.ps1
```

Ping-only mode:

```powershell
pwsh -File .\ethershell.ps1 -PingOnly
```

Manual-only mode:

```powershell
pwsh -File .\ethershell.ps1 -ManualOnly
```

The special modes are primarily used internally when EtherShell opens separate windows.

---

## Quick Usage Examples

At the main `Go:` prompt:

| Action | Input |
|---|---|
| Apply automatic DHCP and DNS | `id0` or `dhcp-auto` |
| Apply a saved preset | Its name (for example `home`) or ID (for example `id3`) |
| List presets | `p` |
| Restart / Manual / Quit | `r` / `m` / `q` |

---

## Troubleshooting

### PowerShell 7 is not found

Install PowerShell 7 with WinGet:

```powershell
winget install --id Microsoft.PowerShell --source winget
```

### Network changes fail

Use the generated EtherShell shortcut or otherwise make sure EtherShell is running with Administrator privileges.

### VPN shows `Connected / DNS unavailable`

This means the configured VPN test hostname cannot currently be resolved while EtherShell sees evidence consistent with an active VPN connection.

If the state appears immediately after EtherShell changed the adapter/network configuration, EtherShell may also display:

```text
VPN DNS resolution failed after network reconfiguration.
A manual VPN reconnect may be required.
```

A manual disconnect/reconnect in the installed VPN client may restore the VPN DNS state. EtherShell intentionally does not control third-party VPN software.

If the test resource requires HTTPS, make sure the configured VPN test URL explicitly begins with `https://`; protocol-less values currently default to `http://`.

### Wi-Fi scan is blocked

Current Windows versions may restrict WLAN scan/status information through Location Services/privacy controls. EtherShell only offers the Location settings workflow after the WLAN operation itself indicates that access is unavailable.

### Preset shows `None`

The active Windows network configuration does not exactly match a stored preset.

### Preset shows `Multiple`

More than one stored preset represents the same effective live configuration.

### Shortcut icon remains old

Make sure `ethershell-v2.ico` is next to `ethershell.ps1`, then start EtherShell again so the shortcut and content-hashed icon-cache path are refreshed.

---

## Security Notes

EtherShell can change Windows networking and can display saved Wi-Fi credentials when Windows permits access.

Use it only on systems and networks you are authorized to administer.

Temporary WLAN profile exports used for credential reading are removed after use.

---

## Third-Party Products and Trademarks

EtherShell is an independent project and is not affiliated with, sponsored by, or endorsed by Microsoft.

References to Microsoft, Windows, PowerShell, WinGet, and other third-party products or services are used only for identification, compatibility, interoperability, or descriptive purposes.

Third-party product names, service names, trademarks, and logos remain the property of their respective owners. No third-party trademark or branding rights are granted by the EtherShell license.

EtherShell uses installed Windows and PowerShell functionality as part of its normal operation. The EtherShell license applies to the EtherShell project itself and does not replace or alter the licenses that apply to third-party software or components.

---

## License

EtherShell is distributed under the **EtherShell Source Available License 1.0**.

The license is a source-available license and is not an OSI Open Source license.

In summary, subject to the full license terms:

- personal use is permitted
- educational use is permitted
- internal business use is permitted
- companies and IT service providers may use the unmodified software, including during paid professional services
- complete unmodified copies may be redistributed free of charge with the required notices and license
- modification and derivative works are prohibited
- rebranding is prohibited
- sale, paid licensing, and direct monetization of the software itself are prohibited

Configuration changes, presets, `settings.json`, logs, exports, caches, and other normal user/runtime data are not treated as prohibited source-code modifications under the license terms.

Read the repository `LICENSE` file for the complete and controlling terms.

---

## Project

GitHub profile: https://github.com/Gittegatt/  
Project website: https://github.com/Gittegatt/EtherShell

Feedback, bug reports, and suggestions can be submitted through the repository.

---

## Disclaimer

**Use at your own risk. No warranty is provided.**

Network configuration changes can interrupt connectivity. Verify critical settings before applying them, especially when administering a system remotely.
