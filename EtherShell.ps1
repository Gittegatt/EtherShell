param (
    [switch]$PingOnly
)

####################################################################
#
# To bypass the ExecutionPolicy
# Get-ExecutionPolicy -List
# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned
# Set-ExecutionPolicy -ExecutionPolicy AllSigned
# 
# PowerShell
# Version:
# $PSVersionTable.PSVersion ODER pwsh
# Update: winget install --id Microsoft.PowerShell --source winget
# 
####################################################################

# ────────────────────────────────────────────────────────
# initalize console 
# ────────────────────────────────────────────────────────
#[console]::WindowWidth = 100;
[console]::WindowHeight = 42; 
#[console]::BufferWidth = [console]::WindowWidth
[Console]::BackgroundColor = 'Black'
Clear-Host

# get the banner color for this session
$global:BannerColor = Get-Random -InputObject @(
    'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed',
    'DarkMagenta', 'DarkYellow', 'Gray', 'DarkGray',
    'Blue', 'Green', 'Cyan', 'Red', 'Magenta',
    'Yellow', 'DarkGray'
)

# ────────────────────────────────────────────────────────
# meet the precise requirements
# ────────────────────────────────────────────────────────
function Initialize-EtherShell-Version {
    $script:ToolVersion = '1.0.0'
    $script:RequiredVersion = '7.5.1'
}

function New-EtherShellShortcut {
    $scriptPath = Join-Path $PSScriptRoot 'EtherShell.ps1'
    $shortcutPath = Join-Path $PSScriptRoot 'EtherShell.lnk'
    $iconPath = Join-Path $PSScriptRoot 'ethershell.ico'
    $targetPath = "$env:ProgramFiles\PowerShell\7\pwsh.exe"

    if (-not (Test-Path $scriptPath)) {
        Write-Host "❌ 'EtherShell.ps1' not found in root directory." -ForegroundColor Red
        return
    }

    if (-not (Test-Path $iconPath)) {
        Write-Host "❌ 'ethershell.ico' not found in root directory." -ForegroundColor Red
        return
    }

    if (Test-Path $shortcutPath) {
        Write-Host "ℹ️ Shortcut already exists. Skipping creation." -ForegroundColor DarkGray
        return
    }

    $WScriptShell = New-Object -ComObject WScript.Shell
    $shortcut = $WScriptShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $targetPath
    $shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$scriptPath`""
    $shortcut.IconLocation = $iconPath
    $shortcut.WorkingDirectory = $PSScriptRoot
    $shortcut.Description = "Launch EtherShell with administrator privileges"
    $shortcut.Save()

    try {
        $bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
        $bytes[21] = $bytes[21] -bor 0x20  # Set RunAs flag -> Run as Administrator
        [System.IO.File]::WriteAllBytes($shortcutPath, $bytes)    
        Write-Host "✅ Shortcut created with administrator privileges." -ForegroundColor DarkGray
    }
    catch {
        Write-Host "⚠️ Shortcut created, but admin flag could not be set." -ForegroundColor Yellow
    }
}

function Ensure-PwshVersion {
    if (-not $script:RequiredVersion) {
        throw "Required PowerShell version is not defined. Please make sure 'Show-About' or your initialization block has set `$script:RequiredVersion`."
    }

    function Is-VersionLess {
        param (
            [string]$current,
            [string]$required
        )
        return [version]$current -lt [version]$required
    }

    $currentVersion = $PSVersionTable.PSVersion.ToString()

    if (Is-VersionLess -current $currentVersion -required $script:RequiredVersion) {
        Write-Host "The tool was written and tested with PowerShell Version $script:RequiredVersion." -ForegroundColor Yellow
        Write-Host "Your current version is: $currentVersion" -ForegroundColor DarkYellow
        Write-Host ""
        Write-Host "If the update is not applied, some functions may not work or behave properly."
        Write-Host ""
        $consent = Read-Host "Consent to update PowerShell 7 to version $script:RequiredVersion ? (Y/N)"

        if ($consent -match '^(Y|y)$') {
            Write-Host "`n🔄 Starting update to PowerShell $script:RequiredVersion using winget..." -ForegroundColor DarkCyan

            try {
                if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
                    Write-Host "❌'winget' is not available. Please install winget manually or update PowerShell via MSI." -ForegroundColor Red
                    Write-Host "Microsoft → https://learn.microsoft.com/de-de/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.5" -ForegroundColor DarkCyan
                    Write-Host "OR"
                    Write-Host "Offical Github → https://github.com/PowerShell/PowerShell/releases/tag/v7.5.1" -ForegroundColor DarkCyan
                    Pause
                    return
                }

                winget install --id Microsoft.PowerShell --source winget --version $script:RequiredVersion --accept-source-agreements --accept-package-agreements

                Write-Host "`n✅ PowerShell $script:RequiredVersion installation initiated. Please restart your terminal after installation." -ForegroundColor Green
                
            }
            catch {
                Write-Host "`n❌ Update failed: $_" -ForegroundColor Red
                Start-Sleep 1
            }
        }
        else {
            Write-Host "`n⚠️ Update was skipped. Proceeding with current version $currentVersion." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "✅ PowerShell version $currentVersion meets or exceeds required version $script:RequiredVersion." -ForegroundColor DarkGray
    }
}

# ────────────────────────────────────────────────────────
# initialize settings.json file
# ────────────────────────────────────────────────────────
function Ensure-SettingsFile {
    $settingsPath = Join-Path $PSScriptRoot "settings.json"

    if (-not (Test-Path $settingsPath)) {
        Write-Host "⚙️ Creating default settings.json..." -ForegroundColor DarkGray

        $defaultSettings = @{
            ethershell = @{
                defaultAdapter = ""
                lastPingTarget = ""
                network        = @{
                    dhcpDns    = ""
                    vpnTestURL = @(
                        "", # 1st test URL
                        ""  # 2nd test URL
                    )
                }
            }
        }

        try {
            $json = $defaultSettings | ConvertTo-Json -Depth 5
            Set-Content -Path $settingsPath -Value $json -Encoding UTF8
            Write-Host "✅ settings.json created." -ForegroundColor DarkGray
        }
        catch {
            Write-Host "❌ Failed to create settings.json: $_" -ForegroundColor Red
        }
    }
}

# ────────────────────────────────────────────────────────
# set global variable for default adapter
# ────────────────────────────────────────────────────────
function Load-DefaultAdapterFromSettings {
    $global:adapterName = "Ethernet"  # fallback value
    $settingsFile = Join-Path $PSScriptRoot "settings.json"

    if (Test-Path $settingsFile) {
        try {
            $json = Get-Content $settingsFile -Raw | ConvertFrom-Json -AsHashtable

            if ($json.ContainsKey("ethershell") -and $json["ethershell"].ContainsKey("defaultAdapter")) {
                $value = $json["ethershell"]["defaultAdapter"]

                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $global:adapterName = $value
                    Write-Host "🔌 Default adapter '$global:adapterName' loaded from settings.json." -ForegroundColor DarkGray
                }
                else {
                    Write-Host "⚠️ Default adapter entry is empty – using fallback '$global:adapterName'." -ForegroundColor DarkGray
                }
            }
        }
        catch {
            Write-Host "⚠️ Could not read settings.json. Fallback to '$global:adapterName'." -ForegroundColor DarkGray
        }
    }
}



# ────────────────────────────────────────────────────────
# EtherShell Startup Initalization
# ────────────────────────────────────────────────────────
function Initialize-EtherShellStartup {
    # initiate ToolVersion
    Initialize-EtherShell-Version

    if ($script:ToolVersion) {
        Write-Host ("Tool Version: v{0}" -f $script:ToolVersion) -ForegroundColor DarkGray
    }

    Write-Host "`nInitializing EtherShell. Please wait..." -ForegroundColor DarkGray

    # init functions in main thread
    try {
        New-EtherShellShortcut
        Ensure-PwshVersion
        Ensure-SettingsFile
        Load-DefaultAdapterFromSettings
    }
    catch {
        Write-Host "❌ An error occurred during initialization: $_" -ForegroundColor Red
    }

    Write-Host "✅ Initialization complete." -ForegroundColor DarkGray
    Start-Sleep 1
}

# run EtherShell startup init
Initialize-EtherShellStartup


# ────────────────────────────────────────────────────────
# EtherShell ASCII Banner
# ASCII font style: Colossal
# ────────────────────────────────────────────────────────
function Show-StartBanner {
    Write-Host @"

    8888888888 888    888                       .d8888b.  888               888 888 
    888        888    888                      d88P  Y88b 888               888 888 
    888        888    888                      Y88b.      888               888 888 
    8888888    888888 88888b.   .d88b.  888d888 "Y888b.   88888b.   .d88b.  888 888 
    888        888    888 "88b d8P  Y8b 888P"      "Y88b. 888 "88b d8P  Y8b 888 888 
    888        888    888  888 88888888 888          "888 888  888 88888888 888 888 
    888        Y88b.  888  888 Y8b.     888    Y88b  d88P 888  888 Y8b.     888 888 
    8888888888  "Y888 888  888  "Y8888  888     "Y8888P"  888  888  "Y8888  888 888
"@ -ForegroundColor $BannerColor
    Write-Host @"
    ┌─────────────────────────────────────────────────────────────────────────────┐
    │            ⚡ EtherShell – Terminal Tool for Networkwizardry ⚡             │
    └─────────────────────────────────────────────────────────────────────────────┘
"@ -ForegroundColor Gray
}

function Get-InternetStatus {
    $urls = @(
        "https://www.msftconnecttest.com/connecttest.txt",
        "https://clients3.google.com/generate_204"
    )

    foreach ($url in $urls) {
        try {
            $res = Invoke-WebRequest -Uri $url -TimeoutSec 3 -UseBasicParsing
            if ($res.StatusCode -eq 200 -or $res.StatusCode -eq 204) {
                return @{ Status = "Online"; Color = 'Green' }
            }
        }
        catch {}
    }

    return @{ Status = "Offline"; Color = 'DarkGray' }
}

function Get-VPNStatus {
    $settingsPath = Join-Path $PSScriptRoot "settings.json"

    if (-not (Test-Path $settingsPath)) {
        return @{ Status = "Offline"; Color = 'DarkGray'; URL = "" }
    }

    try {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable
        $vpnTestURLs = $settings.ethershell.network.vpnTestURL

        # Sicherstellen, dass es ein Array ist
        if ($vpnTestURLs -is [string]) {
            $vpnTestURLs = @($vpnTestURLs)
        }
        elseif (-not ($vpnTestURLs -is [System.Collections.IEnumerable])) {
            $vpnTestURLs = @()
        }

        # Leere/ungültige Einträge filtern
        $vpnTestURLs = $vpnTestURLs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        # Wenn keine gültigen Einträge → als "Not Configured" behandeln
        if ($vpnTestURLs.Count -eq 0) {
            return @{ Status = "Not Configured"; Color = 'DarkGray'; URL = "" }
        }

        # Teste jede gültige URL
        foreach ($url in $vpnTestURLs) {
            $fullUrl = if ($url.StartsWith("http://") -or $url.StartsWith("https://")) {
                $url
            }
            else {
                "http://$url"
            }

            try {
                $res = Invoke-WebRequest -Uri $fullUrl -TimeoutSec 3 -UseBasicParsing
                if ($res.StatusCode -eq 200 -or $res.StatusCode -eq 204) {
                    return @{ Status = "Online"; Color = 'Green'; URL = $fullUrl }
                }
            }
            catch {
                # Fehler ignorieren und nächste URL prüfen
            }
        }
    }
    catch {
        # JSON oder allgemeiner Fehler → ignorieren
    }

    # Wenn keine URL erfolgreich war
    return @{ Status = "Offline"; Color = 'DarkGray'; URL = "" }
}

function Show-Menu {
    try {
        # read from setting.json
        $settingsFile = Join-Path $PSScriptRoot "settings.json"
        
        # read the VPN test URLs from settings.json 
        $vpnInfo = Get-VPNStatus

        # Inline-Liste für Anzeige
        $vpnListInline = if ($vpnInfo.Status -eq "Online" -or $vpnInfo.Status -eq "Offline") {
            if ($vpnInfo.URL) {
                " (Test: $($vpnInfo.URL -replace '^https?://'))"
            }
            else {
                ""
            }
        }
        elseif ($vpnInfo.Status -eq "Not Configured") {
            ""
        }
        else {
            " (unknown)"
        }

        # Try to get internet connection status
        $internetInfo = Get-InternetStatus
        $vpnInfo = Get-VPNStatus

        # Try to get adapter status
        $adapter = Get-NetAdapter -Name $global:adapterName -ErrorAction Stop
        $result = Show-AdapterStatus -Adapter $adapter -Name $global:adapterName

        # Initialize default values
        $ipv4 = "Not available"
        $ipMode = "Unknown"
        $mediaState = $adapter.MediaConnectionState

        # Determine media state color
        switch ($mediaState) {
            "Connected" { $mediaColor = 'Green' } 
            "Disconnected" { $mediaColor = 'DarkGray' }
            "Unknown" { $mediaColor = 'DarkRed' }
            default { $mediaColor = 'Gray' }
        }

        # If adapter is up, retrieve IP information
        if ($result.Status -eq "Up") {
            try {
                $ipConfig = Get-NetIPConfiguration -InterfaceAlias $global:adapterName -ErrorAction Stop 2>$null
                $ipv4 = $ipConfig.IPv4Address.IPAddress
            }
            catch {
                $ipv4 = "Not available"
            }

            # get IP mode - either static or dhcp (if dhcp, show custom DNS if set)
            try {
                $dhcpEnabled = (Get-NetIPInterface -InterfaceAlias $global:adapterName -ErrorAction Stop 2>$null).Dhcp
                if ($dhcpEnabled -eq "Enabled") {
                    $ipMode = "DHCP"

                    # load DHCP-DNS from settings.json (if present)
                    $settingsFile = "$PSScriptRoot\settings.json"
                    if (Test-Path $settingsFile) {
                        try {
                            $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json -AsHashtable
                            $dns = $settings.ethershell.network.dhcpDns
                            if (-not [string]::IsNullOrWhiteSpace($dns)) {
                                $ipMode += " (DNS $dns)"
                            }
                        }
                        catch {
                            # ignore failure while read
                        }
                    }
                }
                else {
                    $ipMode = "Static"
                }
            }
            catch {
                $ipMode = "Unknown"
            }
        }

    }
    catch {
        # Fallback, if Get-NetAdapter or Show-AdapterStatus fails
        $result = @{ Status = "Unknown" }
        $ipv4 = "Not available"
        $ipMode = "Unknown"
        $mediaState = "Unknown"
        $mediaColor = 'Gray'
    }

    Clear-Host
    Show-StartBanner
    Write-Host "┌" -NoNewline -ForegroundColor $BannerColor
    Write-Host " Status"
    Write-Host "│" -NoNewline -ForegroundColor $BannerColor
    Write-Host " VPN" -NoNewline
    Write-Host "🔐" -ForegroundColor $vpnInfo.Color
    Write-Host "│" -NoNewline -ForegroundColor $BannerColor
    Write-Host " Internet" -NoNewline
    Write-Host "🌐"  -ForegroundColor $internetInfo.Color
    Write-Host "└" -ForegroundColor $BannerColor
    Write-Host "┌"-NoNewline -ForegroundColor $BannerColor
    Write-Host " Network Adapter"

    Write-Host "│" -NoNewline -ForegroundColor $BannerColor
    Write-Host " Name        : $global:adapterName"

    Write-Host "│" -NoNewline -ForegroundColor $BannerColor
    Write-Host " Status      : " -NoNewline
    $statusColor = switch ($result.Status) {
        "Up" { 'Green' }
        "Disconnected" { 'DarkGray' }
        "Disabled" { 'Red' }
        default { 'Gray' }
    }
    Write-Host $($result.Status) -ForegroundColor $statusColor

    Write-Host "│" -NoNewline -ForegroundColor $BannerColor
    Write-Host " Media State : " -NoNewline
    Write-Host $mediaState -ForegroundColor $mediaColor

    Write-Host "│" -NoNewline -ForegroundColor $BannerColor
    Write-Host " Mode        : $ipMode"

    Write-Host "│" -NoNewline -ForegroundColor $BannerColor
    Write-Host " IPv4 Address: $ipv4"

    Write-Host "└─────────────────────────────────" -ForegroundColor $BannerColor

    Write-Host "┌" -ForegroundColor $BannerColor

    foreach ($entry in @(
            "[1] Set Active Network Adapter",
            "[2] Show IP Configuration",
            "[3] Set DHCP Mode",
            "[4] Set Static IP Mode"
        )) {
        Write-Host "│" -NoNewline -ForegroundColor $BannerColor; Write-Host " $entry"
    }

    Write-Host "├─────────────────────────────────" -ForegroundColor $BannerColor

    foreach ($entry in @(
            "[C] Clear IP Config",
            "[I] ipconfig /all",
            "[N] Network Adapter Overview",
            "[M] Manage Static IP Presets",
            "[P] Ping",
            "[T] Toggle the Network Interface",
            "[W] Show WiFi Creds"
        )) {
        Write-Host "│" -NoNewline -ForegroundColor $BannerColor; Write-Host " $entry"
    }

    Write-Host "├─────────────────────────────────" -ForegroundColor $BannerColor

    Write-Host "│" -NoNewline -ForegroundColor $BannerColor; Write-Host " [Q] Quit"
    Write-Host "│" -NoNewline -ForegroundColor $BannerColor; Write-Host " [A] About / Info" -ForegroundColor DarkGray

    Write-Host "└─────────────────────────────────" -ForegroundColor $BannerColor

    return Read-Host "`nGo"
}


function Set-ActiveAdapter {
    $selected = Select-Adapter -Title "`nSelect network adapter to activate:"

    if (-not $selected) {
        Write-Host "`n⚠️ No adapter selected. Keeping previous setting: '$global:adapterName'" -ForegroundColor Yellow
        Start-Sleep 1
        return
    }

    if ($selected -eq $global:adapterName) {
        Write-Host "`n↪️ No changes made. Adapter remains: '$global:adapterName'" -ForegroundColor DarkGray
        return
    }

    $global:adapterName = $selected
    Write-Host "`n✅ Active adapter set to: '$global:adapterName'" -ForegroundColor Green

    $settingsFile = "$PSScriptRoot\settings.json"
    $json = @{}

    if (Test-Path $settingsFile) {
        try {
            $json = Get-Content $settingsFile -Raw | ConvertFrom-Json -AsHashtable
        }
        catch {
            $json = @{}
        }
    }

    if (-not $json.ContainsKey("ethershell")) {
        $json["ethershell"] = @{}
    }

    $json["ethershell"]["defaultAdapter"] = $global:adapterName
    $json | ConvertTo-Json -Depth 5 | Set-Content $settingsFile -Encoding UTF8

    Write-Host "💾 Saved default adapter" -ForegroundColor DarkGray
    Start-Sleep 1
}


function Select-Adapter {
    param (
        [string]$Title = "`nPlease select a network adapter:"
    )

    $selected = $global:adapterName
    $jsonFile = "$PSScriptRoot\settings.json"

    # Presets prüfen
    $presetAdapters = @{}
    if (Test-Path $jsonFile) {
        try {
            $jsonRaw = Get-Content -Path $jsonFile -Raw
            $json = $jsonRaw | ConvertFrom-Json -AsHashtable
            $adapterPresets = $json.ethershell.network.adapter
            foreach ($entry in $adapterPresets.GetEnumerator()) {
                if ($entry.Value.Keys.Count -gt 0) {
                    $presetAdapters[$entry.Key] = $true
                }
            }
        }
        catch {
            # Fehler ignorieren
        }
    }

    $adapters = Get-NetAdapter | Where-Object { $_.Status -ne "Unknown" } | Sort-Object -Property Name
    if (-not $adapters) {
        Write-Host "❌ No adapters found." -ForegroundColor Red
        return $null
    }

    Write-Host $Title -ForegroundColor DarkCyan
    Write-Host "( * ) = preset exists`n" -ForegroundColor DarkGray

    $indexWidth = 3
    $nameMaxLength = 30

    for ($i = 0; $i -lt $adapters.Count; $i++) {
        $entry = $adapters[$i]

        $statusColor = switch ($entry.Status) {
            "Up" { 'Green' }
            "Disconnected" { 'DarkGray' }
            "Disabled" { 'Red' }
            default { 'Gray' }
        }

        $marker = if ($entry.Name -ieq $selected) { " (SELECTED)" } else { "" }
        $shortName = if ($entry.Name.Length -gt $nameMaxLength) {
            $entry.Name.Substring(0, $nameMaxLength - 1) + "…"
        }
        else {
            $entry.Name
        }

        $index = "[{0}]" -f ($i + 1)
        $padded = $shortName.PadRight($nameMaxLength)
        $presetMark = if ($presetAdapters.ContainsKey($entry.Name)) { " *" } else { "" }

        Write-Host -NoNewline ("{0} " -f $index.PadRight($indexWidth))
        Write-Host -NoNewline $padded -ForegroundColor $statusColor
        Write-Host -NoNewline " |  "
        Write-Host ("{0} {1}" -f ($entry.Status + $marker), $presetMark) -ForegroundColor $statusColor
    }

    # Position merken
    $errorLine = [System.Console]::CursorTop

    do {
        # Fehlermeldung löschen
        [System.Console]::SetCursorPosition(0, $errorLine)
        Write-Host (" " * $Host.UI.RawUI.WindowSize.Width)

        # Eingabeaufforderung anzeigen
        [System.Console]::SetCursorPosition(0, $errorLine)
        $input = Read-Host "Enter adapter number [1-$($adapters.Count)] or Q to cancel"

        if ($input.Trim().ToLower() -eq 'q') {
            Write-Host "↩️ Cancelled by user." -ForegroundColor DarkGray
            return $null
        }

        $isValid = $input -match '^\d+$' -and
        [int]$input -ge 1 -and
        [int]$input -le $adapters.Count

        if (-not $isValid) {
            [System.Console]::SetCursorPosition(0, $errorLine)
            Write-Host "❌ Invalid input. Please enter a number between 1 and $($adapters.Count), or Q to cancel." -ForegroundColor Red
            Start-Sleep -Milliseconds 1000
        }

    } until ($isValid)

    return $adapters[[int]$input - 1].Name
}

function Set-StaticIP {
    $jsonFile = "$PSScriptRoot\settings.json"
    $ip = $null; $netmask = $null; $prefix = $null; $gateway = $null; $dns = $null

    # Ask whether to load from JSON or enter manually
    $loadFromFile = Read-Host "`nLoad static IP settings from your presets? (Y/N) [default: N]"
    if ([string]::IsNullOrWhiteSpace($loadFromFile)) {
        $loadFromFile = "N"
    }

    switch ($loadFromFile.ToUpper()) {
        "Y" {
            if (-not (Test-Path $jsonFile)) {
                Write-Host "`n❌ JSON file '$jsonFile' not found." -ForegroundColor Red
                Write-Host "`nPress any key to continue..."
                [System.Console]::ReadKey($true) | Out-Null
                return
            }

            try {
                $json = Get-Content -Path $jsonFile -Raw | ConvertFrom-Json -AsHashtable
            }
            catch {
                Write-Host "`n❌ Failed to read or parse '$jsonFile': $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "⚠️ Consider to create a preset first." -ForegroundColor Yellow
                Write-Host "`nPress any key to continue..."
                [System.Console]::ReadKey($true) | Out-Null
                return
            }

            $adapterName = Select-Adapter
            if (-not $adapterName) {
                Write-Host "`n❌ Operation cancelled by user." -ForegroundColor Yellow
                return
            }

            $presetName = Select-Preset -json $json -adapterName $adapterName
            if (-not $presetName) {
                Write-Host "`n⚠️ No preset selected or found for '$adapterName'." -ForegroundColor Yellow
                Write-Host "`nPress any key to continue..."
                [System.Console]::ReadKey($true) | Out-Null
                return
            }

            if (-not $json.ethershell.network.adapter[$adapterName].ContainsKey($presetName)) {
                Write-Host "`n❌ Preset '$presetName' not found for adapter '$adapterName'." -ForegroundColor Red
                Write-Host "`nPress any key to continue..."
                [System.Console]::ReadKey($true) | Out-Null
                return
            }

            $settings = $json.ethershell.network.adapter[$adapterName][$presetName]
            $ip = $settings.ipv4
            $netmask = $settings.subnet
            $prefix = $settings.prefix
            $gateway = $settings.gateway
            $dns = $settings.dns

            Write-Host "`n✅ Loaded preset '$presetName' for adapter '$adapterName'." -ForegroundColor Green
        }

        "N" {
            $adapterName = Select-Adapter -Title "`nSelect adapter to apply static IP:"
            if (-not $adapterName) {
                Write-Host "`n❌ Operation cancelled by user." -ForegroundColor Yellow
                return
            }

            Write-Host "`nEnter static settings for '$adapterName'" -ForegroundColor DarkCyan

            $ip = Read-Host "IP-Address [default: 192.168.1.2]"
            if ([string]::IsNullOrWhiteSpace($ip)) { $ip = "192.168.1.2" }

            $netmask = Read-Host "Subnetmask [default: 255.255.255.0]"
            if ([string]::IsNullOrWhiteSpace($netmask)) { $netmask = "255.255.255.0" }

            $gateway = Read-Host "Gateway [default: 192.168.1.1]"
            if ([string]::IsNullOrWhiteSpace($gateway)) { $gateway = "192.168.1.1" }

            $dns = Read-Host "DNS-Server [default: 192.168.1.1]"
            if ([string]::IsNullOrWhiteSpace($dns)) { $dns = "192.168.1.1" }

            function Get-PrefixLength($mask) {
                ($mask.Split('.') | ForEach-Object {
                    [Convert]::ToString([int]$_, 2).ToCharArray() | Where-Object { $_ -eq '1' }
                }).Count
            }
            $prefix = Get-PrefixLength $netmask
        }

        default {
            Write-Host "`n❌ Invalid input – aborting." -ForegroundColor Red
            return
        }
    }

    # Show the chosen configuration
    Write-Host "`nChosen Configuration for '$adapterName':" -ForegroundColor DarkCyan
    Write-Host "  IP-Address   : $ip"
    Write-Host "  Subnetmask   : $netmask"
    Write-Host "  Prefix       : $prefix"
    Write-Host "  Gateway      : $gateway"
    Write-Host "  DNS-Server   : $dns"
    Write-Host "`nPress any key to continue..."
    [System.Console]::ReadKey($true) | Out-Null

    # Apply static IP configuration
    try {
        Set-NetIPInterface -InterfaceAlias $adapterName -Dhcp Disabled -PolicyStore ActiveStore -ErrorAction Stop

        Get-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

        Get-NetRoute -InterfaceAlias $adapterName -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

        Write-Host "`nApplying static configuration..." -ForegroundColor DarkCyan

        New-NetIPAddress -InterfaceAlias $adapterName `
            -IPAddress $ip `
            -PrefixLength $prefix `
            -DefaultGateway $gateway `
            -ErrorAction Stop | Out-Null

        Set-DnsClientServerAddress -InterfaceAlias $adapterName `
            -ServerAddresses $dns -ErrorAction Stop

        Write-Host "`n✅ Static configuration successfully applied." -ForegroundColor Green
    }
    catch {
        Write-Host "`n❌ Error while applying configuration: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "`nPress any key to continue..."
        [System.Console]::ReadKey($true) | Out-Null
    }
}

function Show-StatusLegend {
    #Write-Host "`n Adapter Status Color Legend:" -ForegroundColor DarkCyan
    Write-Host "`n ┌─ " -NoNewline
    Write-Host "Green" -ForegroundColor Green -NoNewline
    Write-Host "      : Adapter is UP / Media Connected"

    Write-Host " ├─ " -NoNewline
    Write-Host "Red" -ForegroundColor Red -NoNewline
    Write-Host "        : Disabled (manually turned off)"
    
    Write-Host " ├─ " -NoNewline
    Write-Host "DarkRed" -ForegroundColor DarkRed -NoNewline
    Write-Host "    : Unknown media state"

    Write-Host " ├─ " -NoNewline
    Write-Host "DarkGray" -ForegroundColor DarkGray -NoNewline
    Write-Host "   : Disconnected (no link)"

    Write-Host " └─ " -NoNewline
    Write-Host "Gray" -ForegroundColor Gray -NoNewline
    Write-Host "       : Unspecified / fallback"
}

function Show-NetworkOverview {
    param (
        [string]$activeAdapter = $global:adapterName,
        [switch]$HideIPv6DNS,
        [switch]$OnlyActive
    )

    function Get-SubnetMaskFromPrefix($prefixLength) {
        $binaryMask = ("1" * $prefixLength).PadRight(32, "0")
        $octets = ($binaryMask -split "(.{8})" | Where-Object { $_ }) | ForEach-Object { [Convert]::ToInt32($_, 2) }
        return ($octets -join ".")
    }

    function Get-NetworkAddress($ip, $mask) {
        $ipBytes = [System.Net.IPAddress]::Parse($ip).GetAddressBytes()
        $maskBytes = [System.Net.IPAddress]::Parse($mask).GetAddressBytes()
        $netBytes = for ($i = 0; $i -lt 4; $i++) {
            $ipBytes[$i] -band $maskBytes[$i]
        }
        return [string]::Join('.', $netBytes)
    }

    $adapters = Get-NetAdapter | Sort-Object Name
    if (-not $adapters) {
        Write-Host "`n❌ No network adapters found." -ForegroundColor Red
        return
    }

    # show legend with color reference first
    Show-StatusLegend

    #then check and show present adapters
    foreach ($adapter in $adapters) {
        $isActive = ($adapter.Name -eq $activeAdapter)
        if ($OnlyActive -and -not $isActive) { continue }

        $statusColor = switch ($adapter.Status) {
            "Up" { 'Green' }
            "Disconnected" { 'DarkGray' }
            "Disabled" { 'Red' }
            default { 'Gray' }
        }

        $mediaColor = switch ($adapter.MediaConnectionState) {
            "Connected" { 'Green' }
            "Disconnected" { 'DarkGray' }
            "Unknown" { 'DarkRed' }
            default { 'Gray' }
        }

        Write-Host "`n ┌─ " -NoNewline -ForegroundColor White
        if ($isActive) {
            Write-Host -NoNewline "$($adapter.Name)" -ForegroundColor $statusColor
            Write-Host " (SELECTED)"
        }
        else {
            Write-Host "$($adapter.Name)" -ForegroundColor $statusColor
        }

        Write-Host -NoNewline " │  Status     : "
        Write-Host $adapter.Status -ForegroundColor $statusColor

        Write-Host -NoNewline " │  MediaState : "
        Write-Host $adapter.MediaConnectionState -ForegroundColor $mediaColor

        $ipConfig = $null
        try {
            $ipConfig = Get-NetIPConfiguration -InterfaceAlias $adapter.Name -ErrorAction Stop 2>$null
        }
        catch {}

        if ($ipConfig -and $ipConfig.IPv4Address) {
            $ipv4Obj = $ipConfig.IPv4Address
            $ipv4 = $ipv4Obj.IPAddress
            $prefix = $ipv4Obj.PrefixLength
            $subnetMask = Get-SubnetMaskFromPrefix $prefix
            $networkAddress = Get-NetworkAddress $ipv4 $subnetMask
            $subnet = "$networkAddress/$prefix"

            Write-Host " │  IPv4       : $ipv4"
            Write-Host " │  Subnetmask : $subnetMask"
            Write-Host " │  Subnet     : $subnet"
            Write-Host " │  Prefix     : $prefix"
        }
        else {
            Write-Host " │  IPv4       : Not available"
        }

        Write-Host -NoNewline " │  Gateway    : "
        if ($ipConfig -and $ipConfig.IPv4DefaultGateway) {
            Write-Host $($ipConfig.IPv4DefaultGateway.NextHop)
        }
        else {
            Write-Host "Not available"
        }

        if ($ipConfig -and $ipConfig.DnsServer) {
            $dnsV4 = ($ipConfig.DnsServer.ServerAddresses | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' }) -join ', '
            $dnsV6 = ($ipConfig.DnsServer.ServerAddresses | Where-Object { $_ -notmatch '^\d{1,3}(\.\d{1,3}){3}$' }) -join ', '

            if ($dnsV4) {
                Write-Host " │  DNS        : $dnsV4"
            }

            if ($dnsV6 -and -not $HideIPv6DNS) {
                $wrapped = $dnsV6 -split ", \s*"
                if ($wrapped.Count -gt 0) {
                    Write-Host -NoNewline " │  DNSv6      : "
                    Write-Host $wrapped[0]
                    for ($i = 1; $i -lt $wrapped.Count; $i++) {
                        Write-Host -NoNewline " │               "
                        Write-Host $wrapped[$i]
                    }
                }
            }
        }

        Write-Host " └───────────────────────────────"
    }

    Write-Host "`nPress any key to go back..."
    [Console]::TreatControlCAsInput = $true
    $key = [System.Console]::ReadKey($true)
    [Console]::TreatControlCAsInput = $false
}



function Show-AdapterStatus {
    param (
        [string]$Name = $global:adapterName
    )

    $adapterStatus = (Get-NetAdapter -Name $Name -ErrorAction Stop).Status

    $statusColor = switch ($adapterStatus) {
        "Up" { 'Green' }
        "Disconnected" { 'DarkGray' }
        "Disabled" { 'Red' }
        default { 'Gray' }
    }

    return [pscustomobject]@{
        Status = $adapterStatus
        Color  = $statusColor
    }
}

function Toggle-NetworkInterface {
    param (
        [string]$interfaceName = $global:adapterName
    )

    $adapter = Get-NetAdapter -Name $interfaceName -ErrorAction SilentlyContinue
    if (-not $adapter) {
        Write-Host "❌ Interface '$interfaceName' not found." -ForegroundColor Red
        return
    }

    if ($adapter.Status -in @("Up", "Disconnected")) {
        Disable-NetAdapter -Name $interfaceName -Confirm:$false
        Write-Host "`n✅ $interfaceName disabled." -ForegroundColor Green
        return
    }

    Enable-NetAdapter -Name $interfaceName -Confirm:$false
    Write-Host "`n✅ $interfaceName enabled." -ForegroundColor Green

    if ($interfaceName -match '(?i)^(wi[-]?fi|wlan|wireless)') {
        $waitSeconds = 5
        Write-Host "`n📶 Waiting $waitSeconds seconds for Wi-Fi stack to initialize"
        for ($i = 0; $i -lt $waitSeconds; $i++) {
            Start-Sleep -Seconds 1
            Write-Host -NoNewline "."

        }
        Write-Host -NoNewline "done"
        Write-Host ""

        # Registry paths
        $base = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
        $nonPackaged = Join-Path $base "NonPackaged"
        $desktop = Join-Path $base "Windows.System.Launcher"

        function Is-Allowed($path) {
            try {
                $val = Get-ItemPropertyValue -Path $path -Name "Value" -ErrorAction Stop
                return $val -eq "Allow"
            }
            catch {
                return $true  # Missing key treated as allowed
            }
        }

        if ((Is-Allowed $base) -and (Is-Allowed $nonPackaged) -and (Is-Allowed $desktop)) {
            Write-Host "✅ Location services already enabled." -ForegroundColor DarkGray
        }
        else {
            Write-Host "`n⚠️ The Wi-Fi reconnect feature requires location services to be enabled." -ForegroundColor Yellow
            Write-Host "📍 Do you want to open the settings now? (Y/N): " -NoNewline
            $response = Read-Host

            if ($response -match '^[Yy]$') {
                Start-Process "ms-settings:privacy-location"
            }
            else {
                Write-Host "⚠️ Temporarily skipping location check. Wi-Fi reconnect may not work." -ForegroundColor DarkGray
                return
            }

            while (-not ((Is-Allowed $base) -and (Is-Allowed $nonPackaged) -and (Is-Allowed $desktop))) {
                Write-Host "`n❌ Not all required location settings are enabled." -ForegroundColor Red
                Write-Host "⚠️ Please enable the following:" -ForegroundColor Yellow
                Write-Host "- Location Services"
                Write-Host "- Allow apps to access your location"
                Write-Host "- Allow desktop apps to access your location"
                Write-Host "`n↩ Press ENTER once adjusted, or type N to cancel: " -NoNewline
                $choice = Read-Host
                if ($choice -match '^[Nn]$') {
                    Write-Host "⚠️ Skipping reconnect due to missing permissions." -ForegroundColor DarkGray
                    return
                }
            }
        }

        # Gespeicherte Profile
        $profiles = netsh wlan show profiles | Where-Object { $_ -match ":\s" } | ForEach-Object {
            ($_ -split ":\s*", 2)[1].Trim()
        }

        if (-not $profiles) {
            Write-Host "⚠️ No saved Wi-Fi profiles found." -ForegroundColor Yellow
            Read-Host "`nPress ENTER to continue..."
            return
        }

        # Sichtbare Netzwerke
        $networks = netsh wlan show networks | Where-Object { $_ -match "SSID\s+\d+\s+:\s+" } | ForEach-Object {
            ($_ -split ":\s*", 2)[1].Trim()
        }

        $matches = $profiles | Where-Object { $networks -contains $_ }

        if (-not $matches) {
            Write-Host "⚠️ No matching saved profiles found for currently visible networks." -ForegroundColor Yellow
            Read-Host "`nPress ENTER to continue..."
            return
        }

        Write-Host "`n📶 Available networks with saved profiles:" -ForegroundColor DarkCyan
        $indexed = @{}
        $i = 1
        foreach ($m in $matches) {
            $indexed["$i"] = $m
            Write-Host "[$i] $m"
            $i++
        }

        do {
            $selection = Read-Host "`nEnter the number of the network to connect"
        } while (-not ($indexed.ContainsKey($selection)))

        $selectedSSID = $indexed[$selection]
        Write-Host "`n🔌 Connecting to '$selectedSSID'..."
        $output = netsh wlan connect name="$selectedSSID" interface="$interfaceName" 2>&1

        if ($LASTEXITCODE -eq 0 -and $output -notmatch "Die Schnittstelle ist ausgeschaltet") {
            Write-Host "✅ Connected to '$selectedSSID'" -ForegroundColor Green
        }
        else {
            Write-Host "⚠️ Failed to connect." -ForegroundColor Yellow
            Write-Host "↳ $output" -ForegroundColor DarkGray
        }
    }

    Start-Sleep -Milliseconds 1000
}


function PersistentSettings {
    param (
        [string]$jsonFile = "$PSScriptRoot\settings.json"
    )

    function Get-PrefixLength($netmask) {
        if (-not $netmask -or $netmask -notmatch '^(\d{1,3}\.){3}\d{1,3}$') {
            throw "Invalid subnet mask format: '$netmask'"
        }

        try {
            return ($netmask.Split('.') | ForEach-Object {
                    $byte = [int]$_
                    if ($byte -lt 0 -or $byte -gt 255) {
                        throw "Subnet mask byte out of range: '$byte'"
                    }
                    [Convert]::ToString($byte, 2).ToCharArray() | Where-Object { $_ -eq '1' }
                }).Count
        }
        catch {
            throw "Failed to calculate prefix length: $_"
        }
    }

    function IsValidIPv4($ip) {
        return [System.Net.IPAddress]::TryParse($ip, [ref]$null)
    }

    function IsSameSubnet($ip1, $ip2, $subnet) {
        try {
            $ip1Bytes = [System.Net.IPAddress]::Parse($ip1).GetAddressBytes()
            $ip2Bytes = [System.Net.IPAddress]::Parse($ip2).GetAddressBytes()
            $maskBytes = [System.Net.IPAddress]::Parse($subnet).GetAddressBytes()

            for ($i = 0; $i -lt 4; $i++) {
                if (($ip1Bytes[$i] -band $maskBytes[$i]) -ne ($ip2Bytes[$i] -band $maskBytes[$i])) {
                    return $false
                }
            }
            return $true
        }
        catch {
            return $false
        }
    }

    function Write-Settings {
        $jsonFile = "$PSScriptRoot\settings.json"

        # Adapterauswahl
        $script:adapterName = Select-Adapter
        if (-not $script:adapterName) { return }

        # Preset-Name abfragen
        do {
            $presetName = Read-Host "`nEnter Preset Name [required]"
            $isEmpty = [string]::IsNullOrWhiteSpace($presetName)
            $hasOuterSpaces = ($presetName -ne $presetName.Trim())
            $validPreset = -not $isEmpty -and -not $hasOuterSpaces

            if ($isEmpty) {
                Write-Host "❌ Preset name must not be empty." -ForegroundColor Red
            }
            elseif ($hasOuterSpaces) {
                Write-Host "❌ Preset name must not start or end with a space." -ForegroundColor Red
            }

        } until ($validPreset)


        # IPv4-Adresse
        do {
            $ipv4 = Read-Host "Enter IPv4-Address [default: 192.168.1.2]"
            if ([string]::IsNullOrWhiteSpace($ipv4)) { $ipv4 = "192.168.1.2" }
            $validIP = IsValidIPv4 $ipv4
            if (-not $validIP) {
                Write-Host "❌ Invalid IPv4 address format." -ForegroundColor Red
            }
        } until ($validIP)

        # Subnetmask
        do {
            $netmask = Read-Host "Enter Subnetmask [default: 255.255.255.0]"
            if ([string]::IsNullOrWhiteSpace($netmask)) { $netmask = "255.255.255.0" }
            $validMask = IsValidIPv4 $netmask
            if (-not $validMask) {
                Write-Host "❌ Invalid subnet mask." -ForegroundColor Red
            }
        } until ($validMask)

        # Gateway
        do {
            $gateway = Read-Host "Enter Gateway [default: 192.168.1.1]"
            if ([string]::IsNullOrWhiteSpace($gateway)) { $gateway = "192.168.1.1" }
            $validGW = IsValidIPv4 $gateway
            $sameSubnet = IsSameSubnet $ipv4 $gateway $netmask

            if ($validGW -and -not $sameSubnet) {
                Write-Host "⚠️  Gateway is valid but not in the same subnet as IP address." -ForegroundColor Yellow
                $confirm = Read-Host "Continue anyway? (Y/N)"
                if ($confirm -notmatch '^[yY]$') {
                    $validGW = $false
                }
            }

            if (-not $validGW) {
                Write-Host "❌ Invalid gateway IP address." -ForegroundColor Red
            }
        } until ($validGW)

        # DNS
        do {
            $dns = Read-Host "Enter DNS-Server [default: 192.168.1.1]"
            if ([string]::IsNullOrWhiteSpace($dns)) { $dns = "192.168.1.1" }
            $validDNS = IsValidIPv4 $dns
            if (-not $validDNS) {
                Write-Host "❌ Invalid DNS IP address." -ForegroundColor Red
            }
        } until ($validDNS)

        # Prefix berechnen
        $prefix = Get-PrefixLength $netmask

        # JSON laden oder initialisieren (robust!)
        try {
            if (Test-Path $jsonFile) {
                $jsonRaw = Get-Content -Path $jsonFile -Raw
                if ([string]::IsNullOrWhiteSpace($jsonRaw)) {
                    $json = @{ ethershell = @{ network = @{ adapter = @{} } } }
                }
                else {
                    $json = $jsonRaw | ConvertFrom-Json -AsHashtable
                    if (-not $json.ContainsKey("ethershell")) {
                        $json["ethershell"] = @{ network = @{ adapter = @{} } }
                    }
                    elseif (-not $json.ethershell.ContainsKey("network")) {
                        $json.ethershell["network"] = @{ adapter = @{} }
                    }
                    elseif (-not $json.ethershell.network.ContainsKey("adapter")) {
                        $json.ethershell.network["adapter"] = @{}
                    }
                }
            }
            else {
                $json = @{ ethershell = @{ network = @{ adapter = @{} } } }
            }
        }
        catch {
            Write-Host "`n❌ Failed to load or parse settings file: $($_.Exception.Message)" -ForegroundColor Red
            return
        }

        if (-not $json.ethershell.network.adapter.ContainsKey($script:adapterName)) {
            $json.ethershell.network.adapter[$script:adapterName] = @{}
        }

        if ($json.ethershell.network.adapter[$script:adapterName].ContainsKey($presetName)) {
            Write-Host "`n⚠️ Preset '$presetName' already exists for adapter '$script:adapterName'." -ForegroundColor Yellow
            $confirm = Read-Host "Do you want to overwrite it? (Y/N)"
            if ($confirm -notmatch '^[yY]$') {
                Write-Host "`n❌ Operation cancelled. Preset was not changed." -ForegroundColor Red
                Write-Host "`nPress any key to continue..."
                [System.Console]::ReadKey($true) | Out-Null
                return
            }
        }

        # Speichern
        $json.ethershell.network.adapter[$script:adapterName][$presetName] = @{
            ipv4    = $ipv4
            subnet  = $netmask
            prefix  = $prefix
            gateway = $gateway
            dns     = $dns
        }

        try {
            $json | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonFile -Encoding UTF8
            Write-Host "`n✅ Preset '$presetName' for adapter '$script:adapterName' saved successfully." -ForegroundColor Green
        }
        catch {
            Write-Host "`n❌ Failed to save settings file!" -ForegroundColor Red
            Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
        }

        Write-Host "`nDo you want to apply this preset now? (Y/N)" -ForegroundColor DarkCyan
        $applyNow = Read-Host
        if ($applyNow -match '^[yY]$') {
            Apply-Settings -Adapter $script:adapterName -Preset $presetName
        }
        else {
            Write-Host "`nℹ️ Preset saved only. You can apply it later." -ForegroundColor DarkGray
            Write-Host "`nPress any key to continue..."
            [System.Console]::ReadKey($true) | Out-Null
        }
    }




    function Read-Settings {
        $jsonFile = "$PSScriptRoot\settings.json"

        # Check if the settings file exists
        if (-not (Test-Path $jsonFile)) {
            Write-Host "`n⚠️ No settings file found at '$jsonFile'." -ForegroundColor Yellow
            Write-Host "`nPress any key to continue..."
            [System.Console]::ReadKey($true) | Out-Null
            return
        }

        # Load and validate JSON structure
        try {
            $jsonRaw = Get-Content -Path $jsonFile -Raw
            if ([string]::IsNullOrWhiteSpace($jsonRaw)) {
                throw "The settings file is empty."
            }

            $json = $jsonRaw | ConvertFrom-Json -AsHashtable

            if (-not $json.ContainsKey("ethershell") -or
                -not $json.ethershell.ContainsKey("network") -or
                -not $json.ethershell.network.ContainsKey("adapter")) {
                throw "Missing 'network.adapter' structure in the settings file."
            }

            $adapters = $json.ethershell.network.adapter
        }
        catch {
            Write-Host "`n❌ Failed to read or parse '$jsonFile': $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "⚠️ Consider to create a preset first." -ForegroundColor Yellow
            Write-Host "`nPress any key to continue..."
            [System.Console]::ReadKey($true) | Out-Null
            return
        }

        Write-Host "`nList of available network presets below" -ForegroundColor DarkCyan

        # Iterate over each adapter
        foreach ($adapterEntry in $adapters.GetEnumerator()) {
            $adapterName = $adapterEntry.Key
            $presets = $adapterEntry.Value

            Write-Host "`nAdapter: $adapterName" -ForegroundColor DarkCyan

            if (-not $presets -or -not $presets.Keys.Count) {
                Write-Host "  (no presets defined)" -ForegroundColor Yellow
                continue
            }

            # Iterate over each preset in the adapter
            foreach ($presetEntry in $presets.GetEnumerator()) {
                $presetName = $presetEntry.Key
                $settings = $presetEntry.Value

                Write-Host "  Preset: $presetName" -ForegroundColor Cyan
                Write-Host "    IPv4    : $($settings.ipv4)"
                Write-Host "    Subnet  : $($settings.subnet)"
                Write-Host "    Prefix  : $($settings.prefix)"
                Write-Host "    Gateway : $($settings.gateway)"
                Write-Host "    DNS     : $($settings.dns)"
            }
        }

        Write-Host "`nPress any key to continue..."
        [System.Console]::ReadKey($true) | Out-Null
    }


    function Apply-Settings {
        param (
            [string]$jsonFile = "$PSScriptRoot\settings.json",
            [string]$Adapter,
            [string]$Preset
        )

        # JSON-Datei prüfen und laden
        if (-not (Test-Path $jsonFile)) {
            Write-Host "`n⚠️ No settings file found at '$jsonFile'." -ForegroundColor Yellow
            Write-Host "`nPress any key to continue..."
            [System.Console]::ReadKey($true) | Out-Null
            return
        }

        try {
            $jsonRaw = Get-Content -Path $jsonFile -Raw
            if ([string]::IsNullOrWhiteSpace($jsonRaw)) {
                throw "Empty settings file"
            }
            $json = $jsonRaw | ConvertFrom-Json -AsHashtable
        }
        catch {
            Write-Host "`n❌ Failed to read or parse '$jsonFile': $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "⚠️ Consider to create a preset first." -ForegroundColor Yellow
            Write-Host "`nPress any key to continue..."
            [System.Console]::ReadKey($true) | Out-Null
            return
        }

        # Sicherstellen, dass network.adapter existiert
        if (-not $json.ContainsKey("ethershell") -or
            -not $json.ethershell.ContainsKey("network") -or
            -not $json.ethershell.network.ContainsKey("adapter")) {
            Write-Host "`n⚠️ No adapter presets found in settings file." -ForegroundColor Yellow
            Write-Host "`nPress any key to continue..."
            [System.Console]::ReadKey($true) | Out-Null
            return
        }

        # Determine adapter
        if (-not $Adapter) {
            $global:adapterName = Select-Adapter -Default $global:adapterName
            if (-not $adapterName) { return }
        }
        else {
            # apply settings only without set the apply-preset-adapter to active/selected
            #$adapterName = $Adapter
            # apply settings and change the apply-preset-adapter to active/selected at the same time
            $global:adapterName = $Adapter
        }

        # Check if adapter entry exists and is a hashtable
        if (-not $json.ethershell.network.adapter.ContainsKey($adapterName) -or
            -not ($json.ethershell.network.adapter[$adapterName] -is [hashtable]) -or
            -not $json.ethershell.network.adapter[$adapterName].Keys.Count) {
            Write-Host "`n⚠️ No valid presets found for adapter '$adapterName'." -ForegroundColor Yellow
            Write-Host "`nPress any key to continue..."
            [System.Console]::ReadKey($true) | Out-Null
            return
        }

        # Determine preset
        if ($Preset) {
            $presetName = $Preset
        }
        else {
            Write-Host "`nAvailable Presets for '$adapterName':" -ForegroundColor DarkCyan
            $presets = $json.ethershell.network.adapter[$adapterName].Keys
            for ($j = 0; $j -lt $presets.Count; $j++) {
                Write-Host "[$($j+1)] $($presets[$j])"
            }

            do {
                $pidx = Read-Host "`nSelect preset by number"
                $pvalid = $pidx -match '^\d+$' -and $pidx -ge 1 -and $pidx -le $presets.Count
                if (-not $pvalid) {
                    Write-Host "❌ Please enter a number between 1 and $($presets.Count)." -ForegroundColor Red
                }
            } until ($pvalid)
            $presetName = $presets[$pidx - 1]
        }

        # Retrieve settings
        $settings = $json.ethershell.network.adapter[$adapterName][$presetName]

        # Show settings for confirmation
        Write-Host "`nYou are about to apply preset '$presetName' to interface '$adapterName':" -ForegroundColor DarkCyan
        Write-Host "    IPv4    : $($settings.ipv4)"
        Write-Host "    Subnet  : $($settings.subnet)"
        Write-Host "    Prefix  : $($settings.prefix)"
        Write-Host "    Gateway : $($settings.gateway)"
        Write-Host "    DNS     : $($settings.dns)"
        do {
            $confirm = Read-Host "`nProceed with applying this preset? (Y/N)"
            $proceed = $confirm -match '^[yY]$'
            if (-not ($confirm -match '^[yYnN]$')) {
                Write-Host "❌ Please enter 'Y' or 'N'." -ForegroundColor Red
            }
        } until ($confirm -match '^[yYnN]$')

        if (-not $proceed) {
            Write-Host "`n❌ Operation cancelled. Returning to main menu." -ForegroundColor Yellow
            Write-Host "`nPress any key to continue..."
            [System.Console]::ReadKey($true) | Out-Null
            return
        }

        Write-Host "`nApplying preset '$presetName' to '$adapterName'..." -ForegroundColor DarkCyan

        try {
            # Reset DNS first (some DHCP setups enforce DNS)
            Set-DnsClientServerAddress -InterfaceAlias $adapterName -ResetServerAddresses -ErrorAction SilentlyContinue

            # Disable DHCP explicitly in ActiveStore
            Set-NetIPInterface -InterfaceAlias $adapterName -AddressFamily IPv4 -Dhcp Disabled -PolicyStore ActiveStore -ErrorAction Stop

            # Clear existing IPv4 addresses
            Get-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

            # Clear existing default IPv4 routes
            Get-NetRoute -InterfaceAlias $adapterName -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

            # Apply new static IP and gateway
            New-NetIPAddress -InterfaceAlias $adapterName `
                -IPAddress $settings.ipv4 `
                -PrefixLength $settings.prefix `
                -DefaultGateway $settings.gateway `
                -AddressFamily IPv4 -ErrorAction Stop | Out-Null

            # Apply DNS servers
            Set-DnsClientServerAddress -InterfaceAlias $adapterName `
                -ServerAddresses $settings.dns -ErrorAction Stop

            Write-Host "✅ Preset applied successfully." -ForegroundColor Green
        }
        catch {
            Write-Host "`n❌ Failed to apply preset!" -ForegroundColor Red
            Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
        }

        Start-Sleep 1
    }



    function Delete-Presets {
        if (-not (Test-Path $jsonFile)) {
            Write-Host "`n⚠️ Settings file not found: $jsonFile" -ForegroundColor Yellow
            Write-Host "`nPress any key to continue..."
            [System.Console]::ReadKey($true) | Out-Null
            return
        }

        try {
            $jsonRaw = Get-Content -Path $jsonFile -Raw
            if ([string]::IsNullOrWhiteSpace($jsonRaw)) {
                throw "Settings file is empty"
            }

            $json = $jsonRaw | ConvertFrom-Json -AsHashtable

            if (-not $json.ContainsKey("ethershell") -or
                -not $json.ethershell.ContainsKey("network") -or
                -not $json.ethershell.network.ContainsKey("adapter")) {
                throw "Missing 'network.adapter' section"
            }
        }
        catch {
            Write-Host "`n❌ Failed to load settings: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "`nPress any key to continue..."
            [System.Console]::ReadKey($true) | Out-Null
            return
        }

        $adapterKey = Select-Adapter -Title "`nSelect adapter to delete presets from:"
        if (-not $adapterKey) { return }

        if (-not $json.ethershell.network.adapter.ContainsKey($adapterKey)) {
            Write-Host "`n⚠️ No adapter entry found for '$adapterKey'." -ForegroundColor Yellow
            return
        }

        $presets = $json.ethershell.network.adapter[$adapterKey].Keys

        if (-not $presets -or $presets.Count -eq 0) {
            Write-Host "`n⚠️ No presets found for adapter '$adapterKey'." -ForegroundColor Yellow
            return
        }

        Write-Host "`nAvailable Presets for '$adapterKey':" -ForegroundColor DarkCyan
        for ($j = 0; $j -lt $presets.Count; $j++) {
            Write-Host "[$($j + 1)] $($presets[$j])"
        }

        $presetIndex = Read-Host "`nSelect preset number to delete" -ForegroundColor DarkCyan
        if (-not ($presetIndex -match '^\d+$') -or $presetIndex -lt 1 -or $presetIndex -gt $presets.Count) {
            Write-Host "`n❌ Invalid preset selection." -ForegroundColor Red
            return
        }

        $presetKey = $presets[$presetIndex - 1]

        Write-Host "`nAre you sure you want to delete preset '$presetKey' from '$adapterKey'? (Y/N): " -NoNewline
        $confirm = Read-Host
        if ($confirm -eq "" -or $confirm -match '^[yY]$') {
            $null = $json.ethershell.network.adapter[$adapterKey].Remove($presetKey)

            # Remove adapter if empty
            if ($json.ethershell.network.adapter[$adapterKey].Count -eq 0) {
                $null = $json.ethershell.network.adapter.Remove($adapterKey)
            }

            try {
                $json | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonFile -Encoding UTF8
                Write-Host "`n✅ Preset '$presetKey' deleted successfully." -ForegroundColor Green
            }
            catch {
                Write-Host "`n❌ Failed to write changes to file: $_" -ForegroundColor Red
            }
        }
        else {
            Write-Host "`n❌ Deletion cancelled." -ForegroundColor Yellow
        }

        Write-Host "`nPress any key to continue..."
        [System.Console]::ReadKey($true) | Out-Null
    }

    function Delete-PersistentSettingsFile {
        if (Test-Path $jsonFile) {
            try {
                $fileContent = Get-Content $jsonFile -Raw
            }
            catch {
                Write-Host "`n❌ Could not read '$jsonFile': $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "`nPress any key to continue..."
                [System.Console]::ReadKey($true) | Out-Null
                return
            }

            if ([string]::IsNullOrWhiteSpace($fileContent)) {
                Write-Host "`n⚠️ '$jsonFile' is empty." -ForegroundColor Yellow
            }
            else {
                Write-Host "`n⚠️ The settings file contains data." -ForegroundColor Yellow
            }

            Write-Host "`nDelete entire persistent settings file" -ForegroundColor Red
            Write-Host "`nAre you sure? (Y/N): " -NoNewline
            $confirm = Read-Host
            if ($confirm -eq "" -or $confirm -match '^[yY]$') {
                try {
                    Remove-Item $jsonFile -Force
                    Write-Host "`n✅ Persistent settings file deleted." -ForegroundColor Green
                }
                catch {
                    Write-Host "`n❌ Failed to delete file: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            else {
                Write-Host "`n❌ Deletion cancelled." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "`n⚠️ '$jsonFile' not found." -ForegroundColor Yellow
        }

        Write-Host "`nPress any key to continue..."
        [System.Console]::ReadKey($true) | Out-Null
    }

    do {
        Clear-Host
        Write-Host "`n[1] List " -ForegroundColor White    -NoNewline; Write-Host "  all presets"
        Write-Host "[2] Create " -ForegroundColor Yellow  -NoNewline; Write-Host "preset"
        Write-Host "[3] Apply " -ForegroundColor Cyan  -NoNewline; Write-Host " preset"
        Write-Host "[4] Delete " -ForegroundColor Red     -NoNewline; Write-Host "specific preset"
        Write-Host "[5] Delete " -ForegroundColor Red     -NoNewline; Write-Host "entire persistent settings file"
        Write-Host "[0] or [Q] " -NoNewline; Write-Host "Back to main menu"
        Write-Host
        $choice = Read-Host "Go"
        $choice = $choice.Trim().ToLower()

        switch ($choice) {
            "1" { Read-Settings }
            "2" { Write-Settings }
            "3" { Apply-Settings }
            "4" { Delete-Presets }
            "5" { Delete-PersistentSettingsFile }
            "0" {}  # exit
            "q" {}  # exit
            default {
                Write-Host "`n❌ Invalid input. Please make a choice."
                Read-Host -Prompt "`nPress Enter and try again"
            }
        }
    } while ($choice -ne "0" -and $choice -ne "q")
}


function Start-Ping {
    while ($true) {
        Start-PingLoop
        # Wenn PingLoop mit "exit" endet, dann break
        if ($global:pingExitRequested) { break }
    }
}

function Start-PingLoop {
    $global:pingExitRequested = $false
    Clear-Host

    $settingsFile = "$PSScriptRoot\settings.json"
    $defaultTarget = "8.8.8.8"

    $settings = @{}
    if (Test-Path $settingsFile) {
        try {
            $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json -AsHashtable

            if (
                $settings.ContainsKey("ethershell") -and
                $settings["ethershell"].ContainsKey("lastPingTarget") -and
                -not [string]::IsNullOrWhiteSpace($settings["ethershell"]["lastPingTarget"])
            ) {
                $defaultTarget = $settings["ethershell"]["lastPingTarget"]
            }
        }
        catch {
            Write-Host "⚠️  settings.json was corrupt or invalid. Resetting to default." -ForegroundColor Yellow
            $settings = @{ ethershell = @{ lastPingTarget = $defaultTarget } }
            try {
                $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsFile -Encoding UTF8
                Write-Host "✅ settings.json has been reset." -ForegroundColor Green
            }
            catch {
                Write-Host "❌ Failed to write new settings.json: $_" -ForegroundColor Red
            }
        }
    }


    $target = Read-Host "Enter address or hostname [Hit ENTER for your recent ping: $defaultTarget]"

    if ([string]::IsNullOrWhiteSpace($target)) {
        $target = $defaultTarget
    }

    # IP validation
    $isValidIP = [System.Net.IPAddress]::TryParse($target, [ref]$null)
    if (-not $isValidIP) {
        try {
            [System.Net.Dns]::GetHostEntry($target) | Out-Null
            $isValidIP = $true
        }
        catch {
            $isValidIP = $false
        }
    }

    if (-not $isValidIP) {
        Write-Host "❌ Invalid IP address or hostname" -ForegroundColor Red
        Pause
        return
    }

    # Save target
    if (-not $settings.ContainsKey("ethershell")) { $settings["ethershell"] = @{} }
    $settings["ethershell"]["lastPingTarget"] = $target
    
    try {
        $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsFile -Encoding UTF8
    }
    catch {
        Write-Host "⚠️ Could not write to settings.json: $_" -ForegroundColor Yellow
    }

    # Graphanzeige
    Clear-Host
    Write-Host ""
    Write-Host "Ping: "
    Write-Host "RTT : "
    Write-Host "[Q] Quit  [E] Export recent  [D] Delete exports  [N] New Ping Request" -ForegroundColor White
    Write-Host ""
    Write-Host ""
    Write-Host ""
    Write-Host ""

    # Initialisierung
    $graphBars = @()
    $graphRTTs = @()
    $pingBuffer = @()
    $stopRequested = $false

    $exportDir = "$PSScriptRoot\PingExports"
    New-Item -ItemType Directory -Path $exportDir -Force | Out-Null


    function Export-BufferedPings {
        $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $displayTime = (Get-Date).ToString("dd.MM.yyyy HH:mm:ss")
        $file = Join-Path $exportDir "ping_log_export_$timestamp.txt"

        $count = Read-Host "`nHow many recent pings to export? [default: 4]"
        if ([string]::IsNullOrWhiteSpace($count) -or -not ($count -match '^\d+$')) {
            $count = 4
        }
        else {
            $count = [int]$count
            if ($count -lt 1) { $count = 1 }
        }

        $linesToExport = $pingBuffer | Select-Object -Last $count
        $header = @(
            "[ Ping-Log Export ]",
            "Target: $target",
            "Time: $displayTime",
            "Count: $count",
            ""
        )

        try {
            $header + $linesToExport | Out-File -FilePath $file -Encoding UTF8
            Write-Host "`n✅ Exported to $file" -ForegroundColor Green
        }
        catch {
            Write-Host "`n❌ Export failed: $_" -ForegroundColor Red
        }
    }

    function Delete-AllExports {
        try {
            $files = Get-ChildItem -Path $exportDir -File -ErrorAction SilentlyContinue
            if ($files.Count -eq 0) {
                Write-Host "ℹ️ No files to delete." -ForegroundColor DarkGray
            }
            else {
                $files | Remove-Item -Force
                Write-Host "✅ All export files deleted." -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "❌ Error deleting files: $_" -ForegroundColor Red
        }
    }

    [Console]::TreatControlCAsInput = $true

    try {
        while (-not $stopRequested) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                $char = $key.KeyChar.ToString().ToLower()

                switch ($char) {
                    'e' { Export-BufferedPings }
                    'd' { Delete-AllExports }
                    'n' {
                        $stopRequested = $true
                        return  # zurück zu Start-Ping → Restart
                    }
                    'q' {
                        Write-Host "`nPing cancelled." -ForegroundColor Yellow
                        $global:pingExitRequested = $true
                        $stopRequested = $true
                        return
                    }
                }

                if ($key.Modifiers -band [ConsoleModifiers]::Control -and $key.Key -eq 'C') {
                    Write-Host "`nPing aborted by Ctrl+C." -ForegroundColor Yellow
                    $global:pingExitRequested = $true
                    break
                }
            }

            $pingResult = & ping.exe $target -n 1 -w 1000

            if ($LASTEXITCODE -eq 0 -and ($pingResult -match "Zeit=")) {
                $timeLine = ($pingResult | Select-String "Zeit=" | Select-Object -First 1).Line
                $rtt = [regex]::Match($timeLine, "Zeit=(\d+)ms").Groups[1].Value
                $rtt = [int]$rtt

                # Dynamische Balkenlänge
                $maxLength = 4
                $length = [math]::Min([math]::Ceiling($rtt / 10), $maxLength)
                $bar = "|{0}" -f ("█" * $length).PadRight(4)
                $rttFormatted = " {0,-4}" -f $rtt
                $graphBars += $bar
                $graphRTTs += $rttFormatted
                $output = ("{0} | Reply from {1} | {2}" -f (Get-Date -Format T), $target, $timeLine)
            }
            else {
                $graphBars += "|░░░░"
                $graphRTTs += "     "
                $output = ("{0} | No response from {1}" -f (Get-Date -Format T), $target)
            }

            if ($graphBars.Count -gt 20) { $graphBars = $graphBars[-20..-1] }
            if ($graphRTTs.Count -gt 20) { $graphRTTs = $graphRTTs[-20..-1] }

            # Graph aktualisieren
            $cursorPos = [System.Console]::CursorTop

            function Get-RttColor($rtt) {
                if ($rtt -eq $null) { return "DarkGray" }
                elseif ($rtt -le 30) { return "Green" }
                elseif ($rtt -le 70) { return "Yellow" }
                elseif ($rtt -le 150) { return "DarkYellow" }
                else { return "Red" }
            }

            # Farbige Ping-Balken
            [System.Console]::SetCursorPosition(0, 1)
            Write-Host "Ping: " -NoNewline
            for ($i = 0; $i -lt $graphBars.Count; $i++) {
                $rttVal = ($graphRTTs[$i] -match "\d+") ? [int]$matches[0] : $null
                $color = Get-RttColor($rttVal)
                Write-Host $graphBars[$i] -NoNewline -ForegroundColor $color
            }

            # Neutrale RTT-Zeile (ohne Farben)
            [System.Console]::SetCursorPosition(0, 2)
            Write-Host "RTT : " -NoNewline
            foreach ($rtt in $graphRTTs) {
                Write-Host $rtt -NoNewline
            }

            # Letzte 3 Zeilen anzeigen
            $pingBuffer += $output
            if ($pingBuffer.Count -gt 100) {
                $pingBuffer = $pingBuffer[-100..-1]
            }

            # Letzte 20 Ping-Antworten anzeigen mit schmalem Rahmenkopf
            $maxDisplayLines = 20
            $recent = $pingBuffer | Select-Object -Last $maxDisplayLines
            $displayLines = @()

            # Leere Zeilen auffüllen
            for ($i = 0; $i -lt $maxDisplayLines - $recent.Count; $i++) {
                $displayLines += ""
            }
            $displayLines += $recent

            # Maximale sichtbare Breite ermitteln
            $visibleLineWidth = ($displayLines | Measure-Object -Property Length -Maximum).Maximum
            if (-not $visibleLineWidth -or $visibleLineWidth -lt 40) { $visibleLineWidth = 80 }

            # Rahmenzeile erzeugen
            $headerLine = 4
            $title = " Last 20 Replies "
            $line = "┌" + $title.PadLeft(($visibleLineWidth + $title.Length) / 2, "─").PadRight($visibleLineWidth, "─") + "┐"

            # Leerzeile unter dem Menü
            [System.Console]::SetCursorPosition(0, 4)
            Write-Host (" " * $Host.UI.RawUI.WindowSize.Width)
            $headerLine = 5
            [System.Console]::SetCursorPosition(0, $headerLine)
            Write-Host $line -ForegroundColor DarkGray

            # Zeilen darunter schreiben
            for ($i = 0; $i -lt $maxDisplayLines; $i++) {
                $lineIndex = $headerLine + 1 + $i
                [System.Console]::SetCursorPosition(0, $lineIndex)
                Write-Host (" " * $visibleLineWidth) -NoNewline
                [System.Console]::SetCursorPosition(0, $lineIndex)

                if ($displayLines[$i] -match "No response") {
                    Write-Host $displayLines[$i] -ForegroundColor Red
                }
                else {
                    Write-Host $displayLines[$i] -ForegroundColor Green
                }
            }

            Start-Sleep -Milliseconds 1000
        }
    }
    catch {
        Write-Host "❌ Ping error: $_" -ForegroundColor Red
    }
    finally {
        [Console]::TreatControlCAsInput = $false
    }
}



function Set-DHCP {
    Write-Host

    # Fallback: Detect active adapter if not set
    if (-not $adapterName) {
        $activeAdapter = Get-NetAdapter | Where-Object {
            $_.Status -eq "Up" -and $_.InterfaceOperationalStatus -eq "Up"
        } | Sort-Object -Property InterfaceMetric | Select-Object -First 1

        if ($activeAdapter) {
            $adapterName = $activeAdapter.Name
            Write-Host "→ Active adapter detected: $adapterName"
        }
        else {
            Write-Host "⚠️ No active network adapter found." -ForegroundColor Red
            Start-Sleep -Milliseconds 1000
            return
        }
    }

    # Skip if adapter is disabled
    $adapterStatus = (Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue).Status
    if ($adapterStatus -eq 'Disabled') {
        Write-Host "⚠️ Adapter '$adapterName' is disabled. Skipping DHCP configuration." -ForegroundColor Yellow
        Start-Sleep -Milliseconds 1000
        return
    }

    Write-Host "⚙️ Applying DHCP mode for '$adapterName'..."
    Start-Sleep -Milliseconds 1000

    function Wait-For-IP {
        param([int]$timeoutSeconds = 5)

        Write-Host "`n⏳ Waiting up to $timeoutSeconds seconds for IP address via DHCP (press Q to cancel)"
        Write-Host -NoNewline ""

        for ($i = 1; $i -le $timeoutSeconds; $i++) {
            if ([System.Console]::KeyAvailable) {
                $key = [System.Console]::ReadKey($true)
                if ($key.Key -eq "Q") {
                    Write-Host "`n❌ DHCP wait cancelled by user." -ForegroundColor Red
                    return @{ IP = $null; Cancelled = $true }
                }
            }

            $ip = (Get-NetIPConfiguration -InterfaceAlias $adapterName).IPv4Address.IPAddress
            if ($ip -and $ip -notlike "169.254.*") {
                Write-Host "`n✅ IP address obtained: $ip" -ForegroundColor Green
                return @{ IP = $ip; Cancelled = $false }
            }

            Start-Sleep -Seconds 1
            Write-Host -NoNewline "."
        }
        Write-Host -NoNewline "done"

        Write-Host "`n⚠️ Timeout reached. No valid IP assigned." -ForegroundColor Yellow
        return @{ IP = $null; Cancelled = $false }
    }

    try {
        # Reset config
        Clear-IPConfig -adapterName $adapterName
        Set-DnsClientServerAddress -InterfaceAlias $adapterName -ResetServerAddresses
        Set-NetIPInterface -InterfaceAlias $adapterName -AddressFamily IPv4 -Dhcp Enabled -ErrorAction Stop

        # Load settings
        $settingsFile = "$PSScriptRoot\settings.json"
        $settings = @{}

        if (Test-Path $settingsFile) {
            try {
                $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json -AsHashtable
            }
            catch {
                Write-Host "⚠️ Could not read settings.json. Using fallback DNS." -ForegroundColor Yellow
            }
        }

        # Load existing DNS
        $existingDns = $null
        if (
            $settings.ContainsKey("ethershell") -and
            $settings["ethershell"].ContainsKey("network") -and
            $settings["ethershell"]["network"].ContainsKey("dhcpDns")
        ) {
            $existingDns = $settings["ethershell"]["network"]["dhcpDns"]
        }

        # DNS Eingabeaufforderung anzeigen
        Write-Host ""
        Write-Host "Enter DNS address (optional):" -ForegroundColor DarkCyan
        if ($existingDns) {
            Write-Host " - Press ENTER to keep existing ($existingDns)" -ForegroundColor DarkGray
            Write-Host " - Press DELETE to remove it" -ForegroundColor DarkGray
        }
        Write-Host " - Type new DNS IP and press ENTER to save" -ForegroundColor DarkGray
        Write-Host " - Press ESC to cancel" -ForegroundColor DarkGray

        # Eingabe initialisieren
        $dnsInput = ""
        $customDns = $null

        # Eingabe per Tastendruck (damit DELETE & ESC erkannt werden können)
        while ($true) {
            $key = [Console]::ReadKey($true)

            switch ($key.Key) {
                'Enter' {
                    if (-not [string]::IsNullOrWhiteSpace($dnsInput)) {
                        # Validierung der IP oder Hostname
                        $isValidIP = $false
                        if ([System.Net.IPAddress]::TryParse($dnsInput, [ref]$null)) {
                            $isValidIP = $true
                        }
                        else {
                            try {
                                [System.Net.Dns]::GetHostEntry($dnsInput) | Out-Null
                                $isValidIP = $true
                            }
                            catch {
                                $isValidIP = $false
                            }
                        }

                        if ($isValidIP) {
                            $customDns = $dnsInput
                            Write-Host "`n✅ Using DNS: $customDns" -ForegroundColor Green
                        }
                        else {
                            Write-Host "`n❌ Invalid DNS address." -ForegroundColor Red
                            Pause
                            return
                        }
                    }
                    elseif ($existingDns) {
                        $customDns = $existingDns
                        Write-Host "`n✅ Keeping existing DNS: $customDns" -ForegroundColor Green
                    }
                    else {
                        Write-Host "`nℹ️ No DNS address will be used (DHCP default)." -ForegroundColor DarkGray
                    }
                    break
                }
                'Delete' {
                    if (
                        $settings.ContainsKey("ethershell") -and
                        $settings["ethershell"].ContainsKey("network") -and
                        $settings["ethershell"]["network"].ContainsKey("dhcpDns")
                    ) {
                        $settings["ethershell"]["network"].Remove("dhcpDns")
                        Write-Host "`n🧹 Removed saved DNS from settings." -ForegroundColor Yellow
                    }
                    $customDns = $null
                    break
                }
                'Escape' {
                    Write-Host "`n↩️ DNS entry cancelled." -ForegroundColor DarkGray
                    return
                }
                default {
                    # Zeichen anhängen
                    if ($key.KeyChar -match '\S') {
                        $dnsInput += $key.KeyChar
                        Write-Host -NoNewline $key.KeyChar
                    }
                }
            }

            if ($key.Key -in @('Enter', 'Delete')) { break }
        }


        # DNS speichern, wenn gültig
        if ($customDns) {
            if (-not $settings.ContainsKey("ethershell")) { $settings["ethershell"] = @{} }
            if (-not $settings["ethershell"].ContainsKey("network")) { $settings["ethershell"]["network"] = @{} }
            $settings["ethershell"]["network"]["dhcpDns"] = $customDns
        }

        # speichern
        try {
            $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsFile -Encoding UTF8
        }
        catch {
            Write-Host "⚠️ Failed to write settings.json: $_" -ForegroundColor Yellow
        }

        # Apply DNS if provided
        if ($customDns) {
            Set-DnsClientServerAddress -InterfaceAlias $adapterName -ServerAddresses $customDns -ErrorAction Stop
        }

        # Renew IP
        ipconfig /renew "$adapterName" | Out-Null
        $result = Wait-For-IP

        if ($result.Cancelled) { return }

        if (-not $result.IP) {
            Write-Host "`n🔁 Retrying DHCP renewal in 3 seconds..." -ForegroundColor DarkGray
            Start-Sleep -Seconds 3
            ipconfig /release "$adapterName" | Out-Null
            ipconfig /renew "$adapterName" | Out-Null
            $result = Wait-For-IP
            if ($result.Cancelled) { return }
            if (-not $result.IP) {
                Write-Host "❌ Retry failed: No valid IP address assigned." -ForegroundColor Red
            }
        }
    }
    catch {
        Write-Host "❌ Error while applying DHCP configuration: $_" -ForegroundColor Red
    }

    Start-Sleep -Milliseconds 1000
    return
}


function Select-Preset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$json,

        [Parameter(Mandatory)]
        [string]$adapterName
    )

    if (-not $json.ContainsKey("ethershell") -or
        -not $json.ethershell.ContainsKey("network") -or
        -not $json.ethershell.network.ContainsKey("adapter") -or
        -not $json.ethershell.network.adapter.ContainsKey($adapterName)) {
        return $null
    }

    $presets = $json.ethershell.network.adapter[$adapterName].Keys

    if (-not $presets.Count) {
        return $null
    }

    Write-Host "`nAvailable Presets for '$adapterName':" -ForegroundColor DarkCyan
    for ($j = 0; $j -lt $presets.Count; $j++) {
        Write-Host "[$($j+1)] $($presets[$j])"
    }

    do {
        $pidx = Read-Host "`nSelect preset by number"
        $valid = $pidx -match '^\d+$' -and $pidx -ge 1 -and $pidx -le $presets.Count
        if (-not $valid) {
            Write-Host "`n❌ Invalid selection. Please enter a number between 1 and $($presets.Count)." -ForegroundColor Red
        }
    } until ($valid)

    return $presets[$pidx - 1]
}


function Show-IPConfig {
    Write-Host "`nCurrent IPv4 configuration for interface '$adapterName':" -ForegroundColor DarkCyan

    try {
        $ipConfig = Get-NetIPConfiguration -InterfaceAlias $adapterName -ErrorAction Stop 2>$null

        $ipv4 = $ipConfig.IPv4Address.IPAddress
        $gateway = $ipConfig.IPv4DefaultGateway.NextHop
        $dnsServers = ($ipConfig.DnsServer.ServerAddresses | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' }) -join ", "

        Write-Host "  IPv4-Adresse    : $ipv4"
        Write-Host "  Standardgateway : $gateway"
        Write-Host "  DNS-Server      : $dnsServers"
    }
    catch {
        Write-Host "❌ Adapter '$adapterName' nicht gefunden oder keine Verbindung." -ForegroundColor Red
    }

    Write-Host "`nPress any key to continue..."
    [System.Console]::ReadKey($true) | Out-Null
}


function Clear-IPConfig {
    param (
        [string]$adapterName = "Ethernet"
    )

    Write-Host "`n⚙️ Clearing IP configuration for interface '$adapterName'..."

    try {
        # Reset DNS configuration
        Set-DnsClientServerAddress -InterfaceAlias $adapterName -ResetServerAddresses -ErrorAction Stop
        Write-Host "↳ DNS server addresses reset." -ForegroundColor DarkGray
    }
    catch {
        Write-Host "❌ Failed to reset DNS server addresses: $_" -ForegroundColor Yellow
    }

    try {
        # Remove IPv4 addresses
        $removedIPv4 = Get-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -ErrorAction Stop
        if ($removedIPv4) {
            $removedIPv4 | Remove-NetIPAddress -Confirm:$false -ErrorAction Stop
            Write-Host "↳ Removed $($removedIPv4.Count) IPv4 address(es)." -ForegroundColor DarkGray
        }
        else {
            Write-Host "↳ No IPv4 addresses found to remove." -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "❌ Failed to remove IPv4 addresses: $_" -ForegroundColor Yellow
    }

    try {
        # Remove default IPv4 routes
        $routes = Get-NetRoute -InterfaceAlias $adapterName -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop
        if ($routes) {
            $routes | Remove-NetRoute -Confirm:$false -ErrorAction Stop
            Write-Host "↳ Removed $($routes.Count) default route(s)." -ForegroundColor DarkGray
        }
        else {
            Write-Host "↳ No default routes found to remove." -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "❌ Failed to remove default routes: $_" -ForegroundColor Yellow
    }

    # Optional: IPv6 cleanup (commented)
    <#
    try {
        $ipv6 = Get-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv6 -ErrorAction Stop
        if ($ipv6) {
            $ipv6 | Remove-NetIPAddress -Confirm:$false -ErrorAction Stop
            Write-Host "↳ Removed $($ipv6.Count) IPv6 address(es)." -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "⚠️ Failed to remove IPv6 addresses: $_" -ForegroundColor Yellow
    }
    #>

    Write-Host "✅ Cleared IP settings for interface '$adapterName'." -ForegroundColor Green
}

function Get-WiFiCredential {
    Write-Host "`n📶 Scanning for saved Wi-Fi profiles..." -ForegroundColor DarkCyan

    $output = netsh wlan show profiles 2>&1
    $profiles = @()

    foreach ($line in $output) {
        if ($line -match ":\s*(.+)$") {
            $profiles += $Matches[1].Trim()
        }
    }

    if (-not $profiles) {
        Write-Host "⚠️ No Wi-Fi profiles found." -ForegroundColor Yellow
        return
    }

    Write-Host "`n📋 Saved Wi-Fi Profiles:" -ForegroundColor DarkCyan
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        Write-Host "[$($i+1)] $($profiles[$i])"
    }

    Write-Host
    do {
        $selection = Read-Host "Enter number of Wi-Fi profile to view credentials"
        $valid = $selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $profiles.Count
        if (-not $valid) {
            Write-Host "❌ Invalid selection. Please enter a number between 1 and $($profiles.Count)." -ForegroundColor Red
        }
    } while (-not $valid)

    $selectedProfile = $profiles[[int]$selection - 1]
    Write-Host "`n🔍 Checking credentials for profile: '$selectedProfile'"

    # 🩹 Explizite Umleitung und Dekodierung mit OEM Encoding (Codepage 850)
    $tempFile = [System.IO.Path]::GetTempFileName()
    cmd /c "chcp 850>nul & netsh wlan show profile name=""$selectedProfile"" key=clear" > "$tempFile"

    $detailOutput = Get-Content -Path $tempFile -Encoding Default
    Remove-Item -Path $tempFile -Force

    $password = $null
    foreach ($line in $detailOutput) {
        if ($line -match '^\s*(Key Content|Schlüsselinhalt)\s*:\s*(.+)$') {
            $password = $Matches[2].Trim()
            break
        }
    }

    if ($password) {
        Write-Host "🔑 Password: $password" -ForegroundColor DarkGray
    }
    else {
        Write-Host "`n⚠️ No password found (may be an open network or the profile is corrupted)." -ForegroundColor Yellow
    }

    Write-Host "`nPress any key to return..."
    [Console]::ReadKey($true) | Out-Null
}

function IPConfigAll {
    ipconfig /all
    Write-Host "`nPress any key to continue..."
    [System.Console]::ReadKey($true) | Out-Null
}

# ────────────────────────────────────────────────────────
# about page
# ────────────────────────────────────────────────────────

function Show-About {
    if (-not $script:ToolVersion -or -not $script:RequiredVersion) {
        Initialize-EtherShell-Version
    }

    $about = @"
 
 ┌────────────────────────────────────────────────────────────────────────────────────────┐
 │                                          EtherShell                                    │
 │                            ⚡Terminal Tool for Networkwizardry⚡                       │
 ┌────────────────────────────────────────────────────────────────────────────────────────┐
 │                                                                                        │
 │ EtherShell is a PowerShell-based utility to manage Windows network adapters,           │
 │ IP configurations, adapter presets, interface toggling, and ping diagnostics.          │
 │ It features an interactive terminal menu with visual ping graphs for quick diagnostics.│
 │ All from a single interface.                                                           │
 │                                                                                        │
 ├────────────────────────────────────────────────────────────────────────────────────────┤
 │                                                                                        │
 │ Version         : $script:ToolVersion                                                                │
 │ Author          : Daniel Zöller                                                        │
 │ Tested with     : PowerShell $script:RequiredVersion                                                     │
 │ Current Version : PowerShell $($PSVersionTable.PSVersion)                                                     │
 │                                                                                        │
 ├────────────────────────────────────────────────────────────────────────────────────────┤
 │                                                                                        │
 │ EtherShell is designed to simplify repetitive network tasks                            │
 │ and provide a fast CLI workflow for IT users and power users.                          │
 │                                                                                        │
 └────────────────────────────────────────────────────────────────────────────────────────┘

"@

    Clear-Host
    Write-Host $about
    Write-Host ""
    Write-Host "Press any key to return to the main menu..."
    [Console]::ReadKey($true) | Out-Null
}

function CheckPS {
    winget search Microsoft.PowerShell
    Pause
    Write-Host "`nWant to update Windows PowerShell? (Y/y/Enter): " -NoNewline -ForegroundColor Yellow
    $confirm = Read-Host
    if ($confirm -eq "" -or $confirm -match '^[yY]$') {
        winget install --id Microsoft.PowerShell --source winget
    }
    else {
        Write-Host "`n❌ Update cancelled." -ForegroundColor Yellow
        Start-Sleep -Milliseconds 1000
        continue
    }
}

function EndScript {
    Clear-Host
    Write-Host "`n🐚 Exiting EtherShell" -ForegroundColor $BannerColor -NoNewline
    for ($i = 1; $i -le 3; $i++) {
        Start-Sleep -Milliseconds 250
        Write-Host "." -ForegroundColor $BannerColor -NoNewline
    }
    Start-Sleep -Milliseconds 400
    exit
}

# --- Main ---
if ($PingOnly) {
    Write-Host "▶️ Running in Ping-Only mode..." -ForegroundColor DarkCyan
    Start-Ping
    return
}

do {
    $Host.UI.RawUI.WindowTitle = "EtherShell"
    $choice = Show-Menu
    $choice = $choice.Trim().ToLower()

    # if choice is empty immediately back to menu
    if ([string]::IsNullOrWhiteSpace($choice)) {
        continue
    }

    if ($choice) {
        switch ($choice) {
            "1" { Set-ActiveAdapter }
            "2" { Show-NetworkOverview -activeAdapter $adapterName -HideIPv6DNS -OnlyActive }
            "3" { Set-DHCP }
            "4" { Set-StaticIP }
            #
            { $_ -in "c" } { Clear-IPConfig }
            { $_ -in "i" } { IPConfigAll }
            { $_ -in "m" } { PersistentSettings }
            { $_ -in "n" } { Show-NetworkOverview }
            { $_ -in "p" } {
                $scriptPath = $MyInvocation.MyCommand.Path
                Start-Process "pwsh" -ArgumentList "-ExecutionPolicy Bypass", "-File", "`"$scriptPath`"", "-PingOnly"
            }
            { $_ -in "t" } { Toggle-NetworkInterface }
            { $_ -in "w" } { Get-WiFiCredential }
            #
            { $_ -in "a" } { Show-About }
            { $_ -in "q" } { EndScript }
            "checkps" { CheckPS }
            default {
                # invalid input ? then show menu again
                continue
            }
        }
    }
} while ($true)
