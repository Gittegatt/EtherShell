# EtherShell

**EtherShell** is a PowerShell-based Windows network utility for managing network adapters, IPv4 configuration, reusable network presets, Wi-Fi profiles, Internet/VPN diagnostics, PowerShell maintenance, and interactive ping diagnostics from one terminal interface.

Current tool version: **v1.1.0**

Project website: https://github.com/Gittegatt/EtherShell  
GitHub profile: https://github.com/Gittegatt/

---

## Highlights

EtherShell provides:

- Interactive terminal menus
- Live adapter, media, IPv4, Internet, VPN, and active-preset status
- DHCP and static IPv4 configuration
- Protected `dhcp-auto` system preset
- Static IPv4 user presets
- DHCP user presets with custom DNS
- Global preset IDs such as `id0`, `id1`, `id2`, ...
- Direct preset execution from the main menu by name or ID
- Quick preset listing directly from the main menu with `[P] Presets`
- Automatic active-preset detection from the live Windows configuration
- Persistent default-adapter selection
- Network-interface enable/disable controls
- IPv4 configuration clearing
- DHCP DNS preference management
- Configurable VPN test URLs
- VPN DNS-degradation detection with `Connected / DNS unavailable`
- Advisory reconnect hint when VPN DNS fails after an EtherShell network reconfiguration
- Bounded VPN DNS/HTTP/TCP checks to avoid unnecessary menu delays
- Wi-Fi interface toggling
- Known Wi-Fi network management
- Visible Wi-Fi scanning with security information
- Hidden/manual SSID connection
- WPA2-Personal and WPA3-Personal connection attempts
- Open Wi-Fi support
- Wi-Fi credential display when Windows exposes the stored key
- Forget-known-network support
- `Connect automatically` handling through a Boolean setting when new WLAN profiles are created
- Interactive ping diagnostics in a separate window
- Visual RTT graph and recent-reply history
- Ping-log export and cleanup
- Integrated Manual in a separate 100-column window
- Vibrant Mode for randomized EtherShell highlight colors
- Main-menu `[R] Restart` command
- Console-dimension preservation during EtherShell restart and normal exit where supported by the terminal host
- Automatic startup check for newer stable EtherShell releases
- PowerShell version checking and WinGet-assisted updates
- Automatic administrator shortcut creation/refresh
- Custom shortcut icon handling with a content-hashed icon cache
- Centralized, locked, validated persistent settings writes
- Best-effort IPv4 rollback after supported configuration failures

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

4. EtherShell verifies the PowerShell version.
5. EtherShell creates or upgrades `settings.json` as needed.
6. EtherShell loads the saved/default network adapter.
7. EtherShell creates or refreshes `EtherShell.lnk` with Administrator privileges.
8. EtherShell checks GitHub for a newer stable EtherShell release.
9. Use the generated shortcut for normal future launches.

`Start-ethershell.cmd` expects PowerShell 7 at the normal `%ProgramFiles%\PowerShell\7\pwsh.exe` location, launches `ethershell.ps1` from the same folder, and requests Administrator elevation.

### Manual shortcut target

If you want to create a shortcut yourself:

```text
"C:\Program Files\PowerShell\7\pwsh.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "Path\to\ethershell.ps1"
```

---

## Startup Sequence

A normal startup follows this sequence:

```text
Tool Version: v1.1.0

Initializing EtherShell. Please wait...
PowerShell version check
settings.json initialization/migration
Default adapter load
Shortcut create/update
Initialization complete
Release check
```

The release check is intentionally performed after the normal initialization sequence has completed.

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

`[P] Presets` clears the console and opens the same preset listing as:

```text
Settings -> Network Presets -> List Presets
```

`[R] Restart` starts a fresh EtherShell process. Where the terminal host permits programmatic resizing, the current console dimensions are carried into the restarted process.

`[Q] Quit` exits EtherShell. Where supported by the terminal host, EtherShell preserves the current console dimensions instead of intentionally resizing the window during shutdown.

Submenus consistently use:

```text
[Q] Back
```

Preset names or IDs can also be typed directly at the main `Go:` prompt:

```text
Go: home
Go: HOME
Go: id1
Go: ID1
Go: dhcp-auto
Go: id0
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

### Status colors

| Field | State | Color |
|---|---|---|
| Status | `Up` | `Green` |
| Status | `Disconnected` | `DarkRed` |
| Status | `Disabled` | `DarkGray` |
| Status | `Unknown` | `DarkYellow` |
| Media State | `Connected` | `Green` |
| Media State | `Disconnected` | `DarkRed` |
| Media State | `Unknown` | `DarkYellow` |
| Internet | `Online` | `Green` |
| Internet | `Offline` | `DarkRed` |
| VPN | `Online` | `Green` |
| VPN | `Connected / DNS unavailable` | `Yellow` |
| VPN | `Offline` | `DarkRed` |
| VPN | `Not Configured` | `DarkGray` |
| VPN | `Settings Error` | `Yellow` |

`Connected / DNS unavailable` indicates that EtherShell sees evidence consistent with an active VPN connection, but the configured VPN test hostname cannot currently be resolved.

Preset colors are intentionally separate from health/status colors:

| Preset state | Color |
|---|---|
| Exact preset match | `Cyan` |
| `None` | `DarkGray` |
| `Multiple` | `Yellow` |

---

## Vibrant Mode

Open:

```text
Settings -> [8] Vibrant Mode: On/Off
```

The current state is visible directly in the Settings menu.

### Vibrant Mode On

- A random highlight color is selected on every EtherShell program start.
- The EtherShell ASCII logo uses the selected highlight color.
- The frame around `EtherShell - Terminal Tool for Networkwizardry` uses the same highlight color.
- The text `EtherShell - Terminal Tool for Networkwizardry` inside that frame remains in the normal console text color.
- Main-menu and submenu border lines use the same highlight color.
- The selected color remains consistent for that running EtherShell session.

### Vibrant Mode Off

- No random highlight color is selected.
- The EtherShell logo uses the normal console foreground color.
- Main-menu and submenu border lines use the normal console foreground color.
- The appearance therefore matches the normal menu text more closely.

The integrated Manual intentionally does **not** use the random Vibrant Mode highlight color. Its formatting remains neutral and consistent.

Vibrant Mode is enabled by default for new settings files.

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

Static configuration includes validation for:

- IPv4 address
- subnet mask
- prefix length
- gateway
- DNS server
- subnet-mask continuity
- address-family correctness

Supported apply operations create a configuration snapshot first so EtherShell can attempt a best-effort rollback if the new configuration fails.

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

Open the full preset-management menu through:

```text
Settings -> [1] Network Presets
```

For a read-only quick listing directly from the main menu, use:

```text
[P] Presets
```

The quick view clears the screen first so the preset list has more room.

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

EtherShell always maintains:

```text
id0  dhcp-auto
```

Properties:

```text
Type      : DHCP
DNS mode  : Automatic / DHCP-provided
Scope     : System
Protected : Yes
```

`dhcp-auto` / `id0` cannot be deleted, renamed, overwritten, or replaced.

Applying it enables DHCP and returns DNS to DHCP-provided values on the currently selected adapter.

### User preset types

#### Static IPv4 preset

Stores:

- preset ID
- static type
- IPv4 address
- subnet mask
- prefix length
- gateway
- DNS server

#### DHCP with custom DNS

Stores:

- preset ID
- DHCP type
- custom DNS mode
- DNS server

### Preset names

New preset names are:

- normalized to lowercase
- matched case-insensitively
- globally unique
- prevented from conflicting with reserved menu commands or `idN` syntax

### Preset IDs

- `id0` is permanently reserved for `dhcp-auto`.
- User IDs begin at `id1`.
- IDs are globally unique across adapters.
- Pressing ENTER during ID selection assigns the smallest currently unused ID.
- You can manually enter an ID number.
- If a manually selected user ID is already occupied, EtherShell identifies the current preset and asks whether it should be replaced.

### Active preset detection

EtherShell detects the active preset from the real Windows network configuration.

Examples:

```text
DHCP + automatic DNS          -> dhcp-auto (id0)
DHCP + matching custom DNS    -> matching DHCP preset
Matching static configuration -> matching static preset
No exact match                -> None
Multiple exact matches        -> Multiple
```

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

Configure up to two VPN test URLs through:

```text
Settings -> [4] VPN Test URLs
```

The menu is:

```text
[1] Set URL 1
[2] Set URL 2
[3] Clear Both URLs
[Q] Back
```

Pressing ENTER at this menu without making a selection does **not** choose URL 1. EtherShell asks for `1`, `2`, `3`, or `Q`.

When editing a URL slot, pressing ENTER with an empty value clears that slot.

If `http://` or `https://` is omitted, the current implementation prepends:

```text
http://
```

For HTTPS-only internal resources, enter the complete `https://...` URL explicitly.

#### VPN state detection

For each configured endpoint, EtherShell first checks hostname resolution. This avoids waiting through repeated HTTP/TCP timeouts when VPN DNS is unavailable.

If DNS succeeds, EtherShell performs a bounded HTTP request. Any real HTTP status response proves that the configured endpoint is reachable. If the HTTP request itself fails, EtherShell performs a short TCP reachability check against the URL's configured/default port.

The resulting states are:

```text
Online                       -> configured VPN endpoint is reachable
Connected / DNS unavailable  -> VPN connection appears active, but VPN test DNS cannot resolve
Offline                      -> configured endpoints are not reachable
Not Configured               -> no VPN test URL is configured
Settings Error               -> VPN settings could not be read
```

`Connected / DNS unavailable` is intended for cases where a likely active VPN adapter is present, or the DNS lookup is explicitly refused, while the internal test hostname cannot be resolved.

If that degraded DNS state appears after EtherShell changed network configuration during the current session, EtherShell additionally shows:

```text
VPN DNS resolution failed after network reconfiguration.
A manual VPN reconnect may be required.
```

This message is advisory. EtherShell does **not** disconnect or reconnect third-party VPN software automatically.

The DNS-first check and bounded HTTP/TCP timeouts are also intended to keep main-menu and submenu returns responsive when VPN DNS or routing is broken.

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

### Wi-Fi security table

Visible and known Wi-Fi networks are shown as a compact table:

```text
No.    SSID                                         Security
----   -------------------------------------------- ------------------------------------
[1]    Example-WPA2                                 WPA2-Personal / AES/CCMP
[2]    Example-WPA3                                 WPA3-Personal / AES/CCMP
[3]    Guest                                        Open
```

The `Security` column combines authentication/security mode and cipher information when Windows exposes both values.

Typical values include:

```text
WPA2-Personal / AES/CCMP
WPA3-Personal / AES/CCMP
WPA2-Enterprise / AES/CCMP
WPA3-Enterprise / AES/CCMP
OWE
Open
Unknown
```

For known networks, the information is read from saved Windows WLAN profiles. For visible networks, it is derived from the Windows WLAN scan.

### Manage Known Networks

```text
[1] List Known Networks
[2] Show Network Credentials
[3] Connect to Known Network
[4] Forget Network
[Q] Back
```

#### List Known Networks

Displays saved WLAN profiles using the SSID/Security table.

#### Show Network Credentials

Lets you select a saved network and attempts to display its stored password when Windows exposes the key material.

A password may not be available for open networks, enterprise authentication, or profiles where Windows does not expose a key.

Temporary exported WLAN profile files are removed after use.

#### Connect to Known Network

Connects through the existing saved Windows WLAN profile and verifies the connected SSID when WLAN status access is available.

#### Forget Network

Lists known networks, allows numeric selection, asks for confirmation, then deletes the selected Windows WLAN profile.

### Connect to New Wi-Fi Network

```text
[1] Search Visible Networks
[2] Hidden / Manual SSID
[Q] Back
```

#### Search Visible Networks

EtherShell:

1. selects a Wi-Fi adapter
2. scans for visible networks
3. shows the numbered SSID/Security table
4. lets you select a network by number
5. asks for the password
6. asks whether to connect automatically
7. creates a Windows WLAN profile
8. requests the connection
9. verifies the result when WLAN status information is available

The `Connect automatically` answer is handled internally as a Boolean:

```text
True  -> automatic Windows WLAN profile connection mode
False -> manual Windows WLAN profile connection mode
```

An empty password can be used for an open network.

For password-protected personal networks, EtherShell supports WPA2-Personal and WPA3-Personal profile creation. The connection messages identify which security mode is being attempted.

#### Location Services behavior

EtherShell does not proactively ask for Location Services before every visible-network scan.

It first attempts the WLAN operation normally. If Windows blocks WLAN scan/status access because the required location/privacy permission is unavailable, EtherShell can offer to open Windows Location settings.

A connection request is not treated as failed merely because Windows subsequently blocks EtherShell from reading the connected SSID.

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

### VPN Test URLs

The VPN Test URLs menu requires an explicit selection:

```text
[1] Set URL 1
[2] Set URL 2
[3] Clear Both URLs
[Q] Back
```

A blank ENTER at the menu prompt performs no action and does not implicitly select URL 1.

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

When `Skip this version` is selected:

- the release tag is saved in `settings.json`
- future startups still display that the newer release exists
- the interactive prompt is suppressed for that exact release
- the prompt automatically returns when an even newer release is published

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

Press:

```text
[M] Manual
```

The Manual opens in a separate PowerShell process through:

```text
-ManualOnly
```

The Manual window is set to a **100-column width** when supported by the terminal host.

The Manual uses neutral formatting and does not use the random Vibrant Mode highlight color.

The integrated Manual documents the current main-menu shortcuts, preset behavior, Static IPv4 apply confirmation, VPN test URL selection behavior, `Connected / DNS unavailable`, the post-reconfiguration VPN DNS reconnect hint, restart behavior, and console-dimension handling.

---

## About / Info

The About screen includes:

- EtherShell version
- required PowerShell version
- currently running PowerShell version
- GitHub profile
- project website
- license name
- a short description of the current feature scope, including reusable presets, Wi-Fi management, VPN endpoint/DNS diagnostics, and network tools

No personal author name is displayed.

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

EtherShell uses:

- centralized settings access
- a named mutex for concurrent access
- temporary-file writes
- JSON validation before replacement
- backup handling
- schema initialization and migration

This protects `settings.json` when multiple EtherShell processes, such as the main tool and Ping Diagnostics, are active at the same time.

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

### Automatic DHCP and automatic DNS

```text
Go: id0
```

or:

```text
Go: dhcp-auto
```

### Apply preset by name

```text
Go: home
```

### Apply preset by ID

```text
Go: id3
```

### List presets quickly

```text
Go: p
```

### Restart EtherShell

```text
Go: r
```

### Open the Manual

```text
Go: m
```

### Quit

```text
Go: q
```

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
