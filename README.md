# EtherShell - README

---

## Description

**EtherShell** is a PowerShell-based utility to manage Windows network adapters,  
IP configurations, adapter presets, interface toggling, and ping diagnostics.  
It features an interactive terminal menu with visual ping graphs for quick diagnostics – all from a single interface.

It is designed to simplify repetitive network tasks and provide  
a fast CLI workflow for IT users and power users.

---

## Requirements

- Windows 10 or later  
- PowerShell 7.2 or newer  
  (Tested with PowerShell 7.5.1)  
- Administrator privileges for some actions  

---

## Installation / First Run

1. Download and extract the `.zip` file (place the folder wherever you like)  
2. Press `Win + R`, type and open `pwsh` or `pwsh.exe`  
3. Drag & drop `EtherShell.ps1` into the opened PowerShell window and hit `ENTER`  
4. The script will automatically generate a shortcut with administrator rights in the root folder  
5. The script will update PowerShell 7 automatically to at least the required version  
   - On failure: follow the instructions provided in the terminal and retry from step 3  
6. Let the script finalize the initialization process until you reach the main menu  
7. Close the terminal  
8. From now on, **only launch the script using the generated shortcut** (provides admin rights)  

**Optional:**
- Create a manual shortcut with this target:  
  ```text
  "C:\Program Files\PowerShell\7\pwsh.exe" -ExecutionPolicy Bypass -File "Path\to\EtherShell.ps1"
  ```
- VPN Status Indicator via `Invoke-WebRequest` in the background  
  - Multiple VPN test URLs must be set as individual array entries in the `vpnTestURL` array inside `settings.json`  
  - Comma-separated values within a single string are **not supported**  
  - `http://` or `https://` is optional – if omitted, the script will prepend `http://` automatically

---

## Usage

Start EtherShell by using the generated shortcut named **EtherShell**.

**Alternatively:**  
Open PowerShell 7 as Administrator and run:  
```powershell
pwsh -File .\EtherShell.ps1
```

**Features:**
- Internet status indicator  
- VPN status indicator  
- View and modify active adapters  
- Set static IP or DHCP  
- Save and apply IP presets  
- Export and delete ping logs  
- Interactive ping with graphical RTT display  

---

## Settings File

All persistent settings are stored in:

```text
settings.json
```

**Structure (example):**

```json
{
  "ethershell": {
    "defaultAdapter": "",
    "lastPingTarget": "",
    "network": {
      "dhcpDns": "",
      "vpnTestURL": [
        "",  // 1st test URL
        ""   // 2nd test URL
      ]
    }
  }
}
```

---

## Troubleshooting

- If changes are not applied, run the script as **Administrator**  
- If `pwsh` is not recognized, ensure **PowerShell 7** is properly installed  

---

## Contact

Feedback or suggestions?  
Visit: [https://github.com/Gittegatt/EtherShell](https://github.com/Gittegatt/EtherShell)

---

## Disclaimer

**Use at your own risk. No warranty provided.**
