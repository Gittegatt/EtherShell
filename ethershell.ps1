param (
    [switch]$PingOnly,
    [switch]$ManualOnly
)

####################################################################
# EtherShell
# PowerShell network utility
#
# Recommended PowerShell:
#   pwsh
#
# Install/update PowerShell:
#   winget install --id Microsoft.PowerShell --source winget
####################################################################

# ────────────────────────────────────────────────────────
# Script state
# ────────────────────────────────────────────────────────
$script:ToolVersion = '1.1.1'
$script:RequiredVersion = '7.5.1'
$script:AdapterName = $null
$script:SettingsPath = Join-Path $PSScriptRoot 'settings.json'
$script:SettingsMutexName = 'Local\EtherShell.Settings'
$script:PingExitRequested = $false
$script:NetworkReconfigured = $false
$script:ProjectProfileUrl = 'https://github.com/Gittegatt/'
$script:ProjectUrl = 'https://github.com/Gittegatt/EtherShell'
$script:ReleaseApiUrl = 'https://api.github.com/repos/Gittegatt/EtherShell/releases/latest'
$script:LicenseName = 'EtherShell Source Available License 1.0'
$script:NormalTextColor = 'Gray'
try { $script:NormalTextColor = $Host.UI.RawUI.ForegroundColor } catch {}
$script:VibrantPalette = @(
    'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed',
    'DarkMagenta', 'DarkYellow', 'Gray', 'DarkGray',
    'Blue', 'Green', 'Cyan', 'Red', 'Magenta', 'Yellow'
)
$script:BannerColor = $script:NormalTextColor

try {
    [Console]::BackgroundColor = 'Black'

    $restartWidth = 0
    $restartHeight = 0
    $hasRestartWidth = [int]::TryParse([string]$env:ETHERSHELL_RESTART_WIDTH, [ref]$restartWidth)
    $hasRestartHeight = [int]::TryParse([string]$env:ETHERSHELL_RESTART_HEIGHT, [ref]$restartHeight)

    if ($hasRestartWidth -and $hasRestartHeight -and $restartWidth -gt 0 -and $restartHeight -gt 0) {
        # A restart should reopen EtherShell with the same console dimensions.
        try {
            if ([Console]::BufferWidth -lt $restartWidth -or [Console]::BufferHeight -lt $restartHeight) {
                [Console]::SetBufferSize(
                    [Math]::Max([Console]::BufferWidth, $restartWidth),
                    [Math]::Max([Console]::BufferHeight, $restartHeight)
                )
            }
            [Console]::SetWindowSize($restartWidth, $restartHeight)
        }
        catch {
            # Some terminal hosts manage their own dimensions.
        }
    }
    elseif ($Host.UI.RawUI.WindowSize.Height -lt 42) {
        [Console]::WindowHeight = 42
    }

    Remove-Item Env:ETHERSHELL_RESTART_WIDTH -ErrorAction SilentlyContinue
    Remove-Item Env:ETHERSHELL_RESTART_HEIGHT -ErrorAction SilentlyContinue
}
catch {
    # Console sizing is optional and can fail in some hosts.
}

# ────────────────────────────────────────────────────────
# Reliable Windows bootstrap
# ────────────────────────────────────────────────────────
# A .ps1 file may be started through Windows PowerShell 5.1, PowerShell 7,
# a shortcut, or a custom file association. Normalize this before EtherShell
# touches network or settings state.
try {
    $currentIsAdmin = $false
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $currentIsAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        $currentIsAdmin = $false
    }

    $runningCore = $PSVersionTable.PSEdition -eq 'Core'
    $runningVersion = [version]$PSVersionTable.PSVersion
    $minimumVersion = [version]$script:RequiredVersion

    if (-not $runningCore -or $runningVersion -lt $minimumVersion -or (-not $PingOnly -and -not $ManualOnly -and -not $currentIsAdmin)) {
        $pwshPath = $null

        $pwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if ($pwshCommand) {
            $pwshPath = $pwshCommand.Source
        }
        else {
            $candidate = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
            if (Test-Path -LiteralPath $candidate) {
                $pwshPath = $candidate
            }
        }

        if (-not $pwshPath) {
            Write-Host '❌ PowerShell 7 was not found.' -ForegroundColor Red
            Write-Host "   EtherShell requires PowerShell $script:RequiredVersion or newer." -ForegroundColor Yellow
            Write-Host '   Install it with: winget install --id Microsoft.PowerShell --source winget' -ForegroundColor DarkCyan
            Write-Host
            Read-Host 'Press ENTER to close' | Out-Null
            exit 1
        }

        $launchArguments = @(
            '-NoLogo',
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', ('"{0}"' -f $PSCommandPath)
        )
        if ($PingOnly) {
            $launchArguments += '-PingOnly'
        }
        if ($ManualOnly) {
            $launchArguments += '-ManualOnly'
        }

        $startParams = @{
            FilePath     = $pwshPath
            ArgumentList = $launchArguments
            WorkingDirectory = $PSScriptRoot
        }

        # Network-changing mode should always run elevated. Ping-only mode can
        # inherit the current token and does not need another UAC prompt.
        if (-not $PingOnly -and -not $ManualOnly -and -not $currentIsAdmin) {
            $startParams['Verb'] = 'RunAs'
        }

        try {
            Start-Process @startParams -ErrorAction Stop | Out-Null
            exit 0
        }
        catch {
            Write-Host "❌ EtherShell could not relaunch in PowerShell 7: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host
            Read-Host 'Press ENTER to close' | Out-Null
            exit 1
        }
    }
}
catch {
    Write-Host "❌ EtherShell bootstrap failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host
    Read-Host 'Press ENTER to close' | Out-Null
    exit 1
}

Clear-Host

# ────────────────────────────────────────────────────────
# Generic helpers
# ────────────────────────────────────────────────────────
function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Pause-EtherShell {
    param (
        [string]$Message = 'Press any key to continue...'
    )

    Write-Host "`n$Message"
    try {
        [Console]::ReadKey($true) | Out-Null
    }
    catch {
        Read-Host | Out-Null
    }
}

function Confirm-EtherShellAction {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Prompt,

        [switch]$DefaultYes
    )

    do {
        $promptSuffix = if ($DefaultYes) { '(Y/N) [default: Y]' } else { '(Y/N)' }
        $answer = Read-Host "$Prompt $promptSuffix"

        if ([string]::IsNullOrWhiteSpace($answer)) {
            return [bool]$DefaultYes
        }

        if ($answer -match '^[Yy]$') { return $true }
        if ($answer -match '^[Nn]$') { return $false }

        Write-Host "❌ Please enter Y or N." -ForegroundColor Red
    } while ($true)
}

function Get-PreferredAdapterName {
    try {
        $ethernet = Get-NetAdapter -Name 'Ethernet' -ErrorAction SilentlyContinue
        if ($ethernet) {
            return $ethernet.Name
        }

        $up = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } | Sort-Object Name)
        if ($up.Count -gt 0) {
            return $up[0].Name
        }

        $all = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -ne 'Unknown' } | Sort-Object Name)
        if ($all.Count -gt 0) {
            return $all[0].Name
        }
    }
    catch {
        # Fallback below.
    }

    return 'Ethernet'
}

# ────────────────────────────────────────────────────────
# IPv4 validation helpers
# ────────────────────────────────────────────────────────
function Test-IPv4Address {
    param (
        [Parameter(Mandatory)]
        [string]$Address
    )

    # Require canonical dotted-decimal IPv4. IPAddress.TryParse alone also
    # accepts some shortened/non-canonical forms that are undesirable here.
    if ($Address -notmatch '^(?:0|[1-9]\d{0,2})(?:\.(?:0|[1-9]\d{0,2})){3}$') {
        return $false
    }

    foreach ($octet in $Address.Split('.')) {
        if ([int]$octet -gt 255) { return $false }
    }

    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$parsed)) {
        return $false
    }

    return $parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork
}

function Test-IPv4SubnetMask {
    param (
        [Parameter(Mandatory)]
        [string]$Mask
    )

    if (-not (Test-IPv4Address -Address $Mask)) {
        return $false
    }

    $bits = (($Mask.Split('.') | ForEach-Object {
                [Convert]::ToString([int]$_, 2).PadLeft(8, '0')
            }) -join '')

    return $bits -match '^1*0*$'
}

function ConvertTo-PrefixLength {
    param (
        [Parameter(Mandatory)]
        [string]$Mask
    )

    if (-not (Test-IPv4SubnetMask -Mask $Mask)) {
        throw "Invalid IPv4 subnet mask: '$Mask'"
    }

    $bits = (($Mask.Split('.') | ForEach-Object {
                [Convert]::ToString([int]$_, 2).PadLeft(8, '0')
            }) -join '')

    return ($bits.ToCharArray() | Where-Object { $_ -eq '1' }).Count
}

function ConvertTo-SubnetMask {
    param (
        [Parameter(Mandatory)]
        [ValidateRange(0, 32)]
        [int]$PrefixLength
    )

    $binaryMask = ('1' * $PrefixLength).PadRight(32, '0')
    $octets = for ($i = 0; $i -lt 32; $i += 8) {
        [Convert]::ToInt32($binaryMask.Substring($i, 8), 2)
    }

    return ($octets -join '.')
}

function Test-SameIPv4Subnet {
    param (
        [Parameter(Mandatory)] [string]$Address1,
        [Parameter(Mandatory)] [string]$Address2,
        [Parameter(Mandatory)] [string]$Mask
    )

    if (-not (Test-IPv4Address -Address $Address1) -or
        -not (Test-IPv4Address -Address $Address2) -or
        -not (Test-IPv4SubnetMask -Mask $Mask)) {
        return $false
    }

    try {
        $ip1Bytes = [System.Net.IPAddress]::Parse($Address1).GetAddressBytes()
        $ip2Bytes = [System.Net.IPAddress]::Parse($Address2).GetAddressBytes()
        $maskBytes = [System.Net.IPAddress]::Parse($Mask).GetAddressBytes()

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

function Test-PingTargetSyntax {
    param (
        [Parameter(Mandatory)]
        [string]$Target
    )

    $parsed = $null
    if ([System.Net.IPAddress]::TryParse($Target, [ref]$parsed)) {
        return $true
    }

    return [System.Uri]::CheckHostName($Target) -ne [System.UriHostNameType]::Unknown
}

function Test-StaticConfiguration {
    param (
        [Parameter(Mandatory)] [string]$IPv4,
        [Parameter(Mandatory)] [string]$Subnet,
        [Parameter(Mandatory)] [int]$Prefix,
        [Parameter(Mandatory)] [string]$Gateway,
        [Parameter(Mandatory)] [string]$Dns
    )

    $errors = @()

    if (-not (Test-IPv4Address -Address $IPv4)) {
        $errors += "Invalid IPv4 address: $IPv4"
    }
    if (-not (Test-IPv4SubnetMask -Mask $Subnet)) {
        $errors += "Invalid subnet mask: $Subnet"
    }
    else {
        $calculatedPrefix = ConvertTo-PrefixLength -Mask $Subnet
        if ($Prefix -ne $calculatedPrefix) {
            $errors += "Prefix $Prefix does not match subnet mask $Subnet (expected $calculatedPrefix)."
        }
    }
    if (-not (Test-IPv4Address -Address $Gateway)) {
        $errors += "Invalid gateway address: $Gateway"
    }
    if (-not (Test-IPv4Address -Address $Dns)) {
        $errors += "Invalid DNS server address: $Dns"
    }

    return @($errors)
}

# ────────────────────────────────────────────────────────
# settings.json - centralized and race-safe access
# ────────────────────────────────────────────────────────
function New-DefaultEtherShellSettings {
    return @{
        ethershell = @{
            defaultAdapter        = ''
            lastPingTarget        = ''
            vibrantMode           = $true
            skippedReleaseVersion = ''
            network               = @{
                dhcpDns      = ''
                vpnTestURL   = @('', '')
                systemPresets = @{
                    'dhcp-auto' = @{
                        id        = 0
                        type      = 'dhcp'
                        dnsMode   = 'auto'
                        protected = $true
                    }
                }
                adapter      = @{}
            }
        }
    }
}

function Initialize-SettingsStructure {
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    if (-not $Settings.Contains('ethershell') -or
        -not ($Settings['ethershell'] -is [System.Collections.IDictionary])) {
        $Settings['ethershell'] = @{}
    }

    $root = $Settings['ethershell']

    if (-not $root.Contains('defaultAdapter')) { $root['defaultAdapter'] = '' }
    if (-not $root.Contains('lastPingTarget')) { $root['lastPingTarget'] = '' }
    if (-not $root.Contains('vibrantMode')) {
        $root['vibrantMode'] = $true
    }
    elseif (-not ($root['vibrantMode'] -is [bool])) {
        $parsedVibrantMode = $true
        if ([bool]::TryParse([string]$root['vibrantMode'], [ref]$parsedVibrantMode)) {
            $root['vibrantMode'] = $parsedVibrantMode
        }
        else {
            $root['vibrantMode'] = $true
        }
    }
    if (-not $root.Contains('skippedReleaseVersion')) {
        $root['skippedReleaseVersion'] = ''
    }
    else {
        $root['skippedReleaseVersion'] = ([string]$root['skippedReleaseVersion']).Trim()
    }

    if (-not $root.Contains('network') -or
        -not ($root['network'] -is [System.Collections.IDictionary])) {
        $root['network'] = @{}
    }

    $network = $root['network']
    if (-not $network.Contains('dhcpDns')) { $network['dhcpDns'] = '' }
    if (-not $network.Contains('vpnTestURL')) { $network['vpnTestURL'] = @('', '') }
    if (-not $network.Contains('systemPresets') -or
        -not ($network['systemPresets'] -is [System.Collections.IDictionary])) {
        $network['systemPresets'] = @{}
    }
    if (-not $network.Contains('adapter') -or
        -not ($network['adapter'] -is [System.Collections.IDictionary])) {
        $network['adapter'] = @{}
    }

    # dhcp-auto is a protected EtherShell system preset. Re-create its canonical
    # definition whenever settings are read/written so script operations cannot
    # remove, rename, re-ID or alter it.
    $network['systemPresets']['dhcp-auto'] = @{
        id        = 0
        type      = 'dhcp'
        dnsMode   = 'auto'
        protected = $true
    }

    # Migrate existing user presets without changing their network values.
    # Legacy presets are static. Existing valid unique IDs are preserved; every
    # missing/invalid/duplicate ID is assigned the smallest free number >= 1.
    $usedIds = [System.Collections.Generic.HashSet[int]]::new()
    $null = $usedIds.Add(0)
    $needsId = [System.Collections.Generic.List[object]]::new()

    $adapterEntries = @($network['adapter'].GetEnumerator() | Sort-Object Key)
    foreach ($adapterEntry in $adapterEntries) {
        $presets = $adapterEntry.Value
        if (-not ($presets -is [System.Collections.IDictionary])) { continue }

        foreach ($presetEntry in @($presets.GetEnumerator() | Sort-Object Key)) {
            $preset = $presetEntry.Value
            if (-not ($preset -is [System.Collections.IDictionary])) { continue }

            if (-not $preset.Contains('type') -or [string]::IsNullOrWhiteSpace([string]$preset['type'])) {
                $preset['type'] = 'static'
            }
            else {
                $preset['type'] = ([string]$preset['type']).Trim().ToLowerInvariant()
            }

            if ($preset['type'] -eq 'dhcp' -and -not $preset.Contains('dnsMode')) {
                $preset['dnsMode'] = 'custom'
            }

            $candidateId = -1
            if ($preset.Contains('id')) {
                try { $candidateId = [int]$preset['id'] } catch { $candidateId = -1 }
            }

            if ($candidateId -ge 1 -and $usedIds.Add($candidateId)) {
                $preset['id'] = $candidateId
            }
            else {
                $needsId.Add($preset)
            }
        }
    }

    foreach ($preset in $needsId) {
        $nextId = 1
        while ($usedIds.Contains($nextId)) { $nextId++ }
        $preset['id'] = $nextId
        $null = $usedIds.Add($nextId)
    }

    return $Settings
}

function Read-EtherShellSettingsUnlocked {
    param (
        [switch]$CreateIfMissing
    )

    if (-not (Test-Path -LiteralPath $script:SettingsPath)) {
        if ($CreateIfMissing) {
            return New-DefaultEtherShellSettings
        }
        throw "Settings file not found: $script:SettingsPath"
    }

    $raw = Get-Content -LiteralPath $script:SettingsPath -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Settings file is empty: $script:SettingsPath"
    }

    $settings = $raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    if (-not ($settings -is [System.Collections.IDictionary])) {
        throw 'The root of settings.json is not a JSON object.'
    }

    return Initialize-SettingsStructure -Settings $settings
}

function Write-EtherShellSettingsUnlocked {
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $settingsDirectory = Split-Path -Parent $script:SettingsPath
    if (-not (Test-Path -LiteralPath $settingsDirectory)) {
        New-Item -ItemType Directory -Path $settingsDirectory -Force -ErrorAction Stop | Out-Null
    }

    $Settings = Initialize-SettingsStructure -Settings $Settings
    $json = $Settings | ConvertTo-Json -Depth 12
    $tempPath = Join-Path $settingsDirectory ('.settings.{0}.tmp' -f [guid]::NewGuid().ToString('N'))
    $backupPath = "$script:SettingsPath.bak"

    try {
        [System.IO.File]::WriteAllText(
            $tempPath,
            $json,
            [System.Text.UTF8Encoding]::new($false)
        )

        # Validate the exact file that is about to replace settings.json.
        $null = Get-Content -LiteralPath $tempPath -Raw -ErrorAction Stop |
            ConvertFrom-Json -AsHashtable -ErrorAction Stop

        if (Test-Path -LiteralPath $script:SettingsPath) {
            [System.IO.File]::Replace($tempPath, $script:SettingsPath, $backupPath, $true)
        }
        else {
            [System.IO.File]::Move($tempPath, $script:SettingsPath)
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-WithSettingsLock {
    param (
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    $mutex = [System.Threading.Mutex]::new($false, $script:SettingsMutexName)
    $lockTaken = $false

    try {
        try {
            $lockTaken = $mutex.WaitOne([TimeSpan]::FromSeconds(5))
        }
        catch [System.Threading.AbandonedMutexException] {
            $lockTaken = $true
        }

        if (-not $lockTaken) {
            throw 'Timed out waiting for the EtherShell settings lock.'
        }

        return & $ScriptBlock
    }
    finally {
        if ($lockTaken) {
            try { $mutex.ReleaseMutex() } catch {}
        }
        $mutex.Dispose()
    }
}

function Get-EtherShellSettings {
    param (
        [switch]$CreateIfMissing
    )

    return Read-EtherShellSettingsUnlocked -CreateIfMissing:$CreateIfMissing
}

function Update-EtherShellSettings {
    param (
        [Parameter(Mandatory)]
        [scriptblock]$UpdateAction
    )

    return Invoke-WithSettingsLock -ScriptBlock {
        $settings = Read-EtherShellSettingsUnlocked -CreateIfMissing
        $result = & $UpdateAction $settings
        if ($result -is [System.Collections.IDictionary]) {
            $settings = $result
        }
        Write-EtherShellSettingsUnlocked -Settings $settings
        return $settings
    }
}

function Ensure-SettingsFile {
    try {
        Invoke-WithSettingsLock -ScriptBlock {
            if (-not (Test-Path -LiteralPath $script:SettingsPath)) {
                Write-Host "⚙️ Creating default settings.json..." -ForegroundColor DarkGray
                Write-EtherShellSettingsUnlocked -Settings (New-DefaultEtherShellSettings)
                Write-Host "✅ settings.json created." -ForegroundColor DarkGray
                return
            }

            # Parse the existing file without replacing invalid user data.
            $raw = Get-Content -LiteralPath $script:SettingsPath -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($raw)) {
                throw "Settings file is empty: $script:SettingsPath"
            }

            $parsed = $raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            if (-not ($parsed -is [System.Collections.IDictionary])) {
                throw 'The root of settings.json is not a JSON object.'
            }

            $before = $parsed | ConvertTo-Json -Depth 12 -Compress
            $normalized = Initialize-SettingsStructure -Settings $parsed
            $after = $normalized | ConvertTo-Json -Depth 12 -Compress

            # Persist schema upgrades (dhcp-auto, preset type and IDs) once.
            if ($before -ne $after) {
                Write-EtherShellSettingsUnlocked -Settings $normalized
                Write-Host '✅ settings.json preset metadata updated.' -ForegroundColor DarkGray
            }
        } | Out-Null
    }
    catch {
        Write-Host "❌ settings.json could not be read safely: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   The existing file was NOT overwritten." -ForegroundColor Yellow
        if (Test-Path -LiteralPath "$script:SettingsPath.bak") {
            Write-Host "   A backup is available at: $script:SettingsPath.bak" -ForegroundColor DarkGray
        }
    }
}

function Load-DefaultAdapterFromSettings {
    $fallback = Get-PreferredAdapterName
    $script:AdapterName = $fallback

    try {
        $settings = Get-EtherShellSettings
        $configured = [string]$settings['ethershell']['defaultAdapter']

        if (-not [string]::IsNullOrWhiteSpace($configured)) {
            $exists = Get-NetAdapter -Name $configured -ErrorAction SilentlyContinue
            if ($exists) {
                $script:AdapterName = $configured
                Write-Host "🔌 Default adapter '$script:AdapterName' loaded from settings.json." -ForegroundColor DarkGray
                return
            }

            Write-Host "⚠️ Saved adapter '$configured' was not found. Using '$fallback'." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "⚠️ Could not load adapter from settings.json. Using '$fallback'." -ForegroundColor Yellow
    }
}

function Get-VibrantModeEnabled {
    try {
        $settings = Get-EtherShellSettings
        return [bool]$settings['ethershell']['vibrantMode']
    }
    catch {
        return $true
    }
}

function Set-EtherShellDisplayColor {
    if (Get-VibrantModeEnabled) {
        $script:BannerColor = Get-Random -InputObject $script:VibrantPalette
    }
    else {
        $script:BannerColor = $script:NormalTextColor
    }
}

function Toggle-VibrantMode {
    try {
        $current = Get-VibrantModeEnabled
        $newValue = -not $current

        Update-EtherShellSettings -UpdateAction {
            param($settings)
            $settings['ethershell']['vibrantMode'] = [bool]$newValue
        } | Out-Null

        Set-EtherShellDisplayColor
        $state = if ($newValue) { 'On' } else { 'Off' }
        $stateColor = if ($newValue) { 'Green' } else { 'DarkGray' }
        Write-Host "`nVibrant Mode is now $state." -ForegroundColor $stateColor

        if ($newValue) {
            Write-Host 'A new random highlight color will be selected on every EtherShell start.' -ForegroundColor DarkGray
        }
        else {
            Write-Host 'The logo and menu borders now use the normal console text color.' -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "`nFailed to change Vibrant Mode: $($_.Exception.Message)" -ForegroundColor Red
    }

    Pause-EtherShell
}

function ConvertTo-EtherShellVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$VersionText
    )

    $match = [regex]::Match($VersionText.Trim(), '(?<!\d)(\d+(?:\.\d+){1,3})(?!\d)')
    if (-not $match.Success) {
        return $null
    }

    try {
        $parts = @($match.Groups[1].Value.Split('.') | ForEach-Object { [int]$_ })
        while ($parts.Count -lt 4) {
            $parts += 0
        }
        return [version]::new($parts[0], $parts[1], $parts[2], $parts[3])
    }
    catch {
        return $null
    }
}

function Check-EtherShellRelease {
    Write-Host '🔎 Checking for newer EtherShell releases...' -ForegroundColor DarkGray

    try {
        $headers = @{ 'User-Agent' = 'EtherShell' }
        $release = Invoke-RestMethod `
            -Uri $script:ReleaseApiUrl `
            -Headers $headers `
            -TimeoutSec 5 `
            -ErrorAction Stop

        $latestTag = ([string]$release.tag_name).Trim()
        $latestVersion = ConvertTo-EtherShellVersion -VersionText $latestTag
        $currentVersion = ConvertTo-EtherShellVersion -VersionText $script:ToolVersion

        if (-not $latestVersion -or -not $currentVersion) {
            throw 'The release version could not be parsed.'
        }

        if ($latestVersion -le $currentVersion) {
            Write-Host '✅ No newer EtherShell release found.' -ForegroundColor DarkGray
            return
        }

        $settings = Get-EtherShellSettings
        $skippedTag = ([string]$settings['ethershell']['skippedReleaseVersion']).Trim()

        Write-Host ("⬆️ New EtherShell release available: {0} (current: v{1})." -f $latestTag, $script:ToolVersion) -ForegroundColor Yellow

        if ($skippedTag -eq $latestTag) {
            Write-Host '   This release is marked as skipped. You will be prompted again when a newer release is published.' -ForegroundColor DarkGray
            return
        }

        Write-Host '[1] Visit the repository website'
        Write-Host '[2] Skip this version'
        Write-Host '[Q] Continue without opening the website'

        do {
            $choice = (Read-Host "`nGo").Trim().ToLowerInvariant()
            switch ($choice) {
                '1' {
                    try {
                        Start-Process $script:ProjectUrl -ErrorAction Stop
                    }
                    catch {
                        Write-Host "Could not open the repository website: $($_.Exception.Message)" -ForegroundColor Red
                    }
                    return
                }
                '2' {
                    Update-EtherShellSettings -UpdateAction {
                        param($latestSettings)
                        $latestSettings['ethershell']['skippedReleaseVersion'] = $latestTag
                    } | Out-Null
                    Write-Host "Release $latestTag will remain visible at startup, but the prompt is paused until a newer release appears." -ForegroundColor DarkGray
                    return
                }
                'q' { return }
                default { Write-Host 'Enter 1, 2, or Q.' -ForegroundColor Red }
            }
        } while ($true)
    }
    catch {
        Write-Host "⚠️ Release check unavailable: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

# ────────────────────────────────────────────────────────
# PowerShell / startup
# ────────────────────────────────────────────────────────
function Ensure-PwshVersion {
    $currentVersion = [version]$PSVersionTable.PSVersion
    $requiredVersion = [version]$script:RequiredVersion

    if ($currentVersion -ge $requiredVersion) {
        Write-Host "✅ PowerShell version $currentVersion meets or exceeds required version $requiredVersion." -ForegroundColor DarkGray
        return $true
    }

    Write-Host "The tool requires PowerShell $requiredVersion or newer." -ForegroundColor Yellow
    Write-Host "Your current version is: $currentVersion" -ForegroundColor DarkYellow
    Write-Host

    $consent = Confirm-EtherShellAction -Prompt "Install PowerShell $requiredVersion using winget?"
    if (-not $consent) {
        Write-Host "⚠️ Update skipped. EtherShell will not continue in this unsupported PowerShell session." -ForegroundColor Yellow
        return $false
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "❌ 'winget' is not available." -ForegroundColor Red
        Write-Host "Microsoft: https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows" -ForegroundColor DarkCyan
        Write-Host "GitHub:    https://github.com/PowerShell/PowerShell/releases" -ForegroundColor DarkCyan
        return $false
    }

    Write-Host "`n🔄 Starting PowerShell installation/update..." -ForegroundColor DarkCyan

    $pwshInstalled = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshInstalled) {
        & winget upgrade --id Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements
        $wingetExitCode = $LASTEXITCODE

        if ($wingetExitCode -ne 0) {
            Write-Host "⚠️ winget upgrade returned exit code $wingetExitCode. Trying install as fallback..." -ForegroundColor Yellow
            & winget install --id Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements
            $wingetExitCode = $LASTEXITCODE
        }
    }
    else {
        & winget install --id Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements
        $wingetExitCode = $LASTEXITCODE
    }

    if ($wingetExitCode -ne 0) {
        Write-Host "❌ winget failed with exit code $wingetExitCode." -ForegroundColor Red
        return $false
    }

    Write-Host "✅ PowerShell installation/update completed. Restart EtherShell with pwsh." -ForegroundColor Green
    return $false
}

function New-EtherShellShortcut {
    # Use the path of the currently running script instead of a hard-coded
    # filename. The canonical filename is "ethershell.ps1".
    $scriptPath = $PSCommandPath
    $shortcutPath = Join-Path $PSScriptRoot 'EtherShell.lnk'
    $iconSourcePath = Join-Path $PSScriptRoot 'ethershell-v2.ico'

    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    $targetPath = if ($pwshCommand) {
        $pwshCommand.Source
    }
    else {
        Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    }

    if ([string]::IsNullOrWhiteSpace($scriptPath) -or -not (Test-Path -LiteralPath $scriptPath)) {
        Write-Host "⚠️ 'ethershell.ps1' was not found at the expected location. Shortcut creation skipped." -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path -LiteralPath $targetPath)) {
        Write-Host '⚠️ pwsh.exe was not found. Shortcut creation skipped.' -ForegroundColor Yellow
        return
    }

    $shortcutIconPath = $null

    if (Test-Path -LiteralPath $iconSourcePath) {
        try {
            # Windows caches shortcut icons aggressively by path. Pointing the
            # shortcut directly at a replaced ICO can therefore keep showing an
            # older image. Use a content-hashed cache filename so every changed
            # icon automatically gets a new path and bypasses the stale cache.
            $iconHash = (Get-FileHash -LiteralPath $iconSourcePath -Algorithm SHA256 -ErrorAction Stop).Hash
            $iconHashShort = $iconHash.Substring(0, 16).ToLowerInvariant()
            $iconCacheDirectory = Join-Path $PSScriptRoot '.ethershell-icon-cache'
            $iconCachePath = Join-Path $iconCacheDirectory ("ethershell-v2-$iconHashShort.ico")

            if (-not (Test-Path -LiteralPath $iconCacheDirectory)) {
                New-Item -ItemType Directory -Path $iconCacheDirectory -Force -ErrorAction Stop | Out-Null
                try {
                    $cacheDirectoryItem = Get-Item -LiteralPath $iconCacheDirectory -ErrorAction Stop
                    $cacheDirectoryItem.Attributes = $cacheDirectoryItem.Attributes -bor [System.IO.FileAttributes]::Hidden
                }
                catch {
                    # Hiding the cache directory is cosmetic only.
                }
            }

            if (-not (Test-Path -LiteralPath $iconCachePath)) {
                Copy-Item -LiteralPath $iconSourcePath -Destination $iconCachePath -Force -ErrorAction Stop
            }

            $shortcutIconPath = $iconCachePath
        }
        catch {
            Write-Host "⚠️ Could not prepare the icon cache: $($_.Exception.Message)" -ForegroundColor Yellow
            $shortcutIconPath = $iconSourcePath
        }
    }

    try {
        $wScriptShell = New-Object -ComObject WScript.Shell
        $shortcut = $wScriptShell.CreateShortcut($shortcutPath)

        # Always refresh an existing shortcut. This keeps its target, arguments,
        # working directory and icon synchronized with the current EtherShell
        # installation instead of preserving stale shortcut metadata.
        $shortcut.TargetPath = $targetPath
        $shortcut.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        $shortcut.WorkingDirectory = $PSScriptRoot
        $shortcut.Description = 'Launch EtherShell with administrator privileges'

        if ($shortcutIconPath -and (Test-Path -LiteralPath $shortcutIconPath)) {
            $shortcut.IconLocation = "$shortcutIconPath,0"
        }
        else {
            # Explicitly reset the icon to pwsh.exe if the custom icon is
            # missing. This also prevents an existing shortcut from keeping an
            # obsolete IconLocation value.
            $shortcut.IconLocation = "$targetPath,0"
        }

        $shortcut.Save()

        # Set the Shell Link RunAsUser flag every time the shortcut is updated.
        $bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
        if ($bytes.Length -le 21) {
            throw 'Shortcut file is unexpectedly short.'
        }
        $bytes[21] = $bytes[21] -bor 0x20
        [System.IO.File]::WriteAllBytes($shortcutPath, $bytes)

        Write-Host '✅ Shortcut created/updated with administrator privileges.' -ForegroundColor DarkGray
        if (-not (Test-Path -LiteralPath $iconSourcePath)) {
            Write-Host "⚠️ 'ethershell-v2.ico' was not found; the default PowerShell icon is used." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "⚠️ Shortcut could not be created/updated completely: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Initialize-EtherShellStartup {
    Write-Host ("Tool Version: v{0}" -f $script:ToolVersion) -ForegroundColor DarkGray
    Write-Host "`nInitializing EtherShell. Please wait..." -ForegroundColor DarkGray

    if (-not (Ensure-PwshVersion)) {
        return $false
    }

    Ensure-SettingsFile
    Set-EtherShellDisplayColor
    Load-DefaultAdapterFromSettings

    if (-not $PingOnly -and -not $ManualOnly) {
        New-EtherShellShortcut
    }

    if (-not $PingOnly -and -not $ManualOnly -and -not (Test-IsAdministrator)) {
        Write-Host 'EtherShell is not running elevated. Read-only functions will work, but network changes require Administrator privileges.' -ForegroundColor Yellow
    }

    Write-Host '✅ Initialization complete.' -ForegroundColor DarkGray

    if (-not $PingOnly -and -not $ManualOnly) {
        Check-EtherShellRelease
    }

    Start-Sleep -Milliseconds 700
    return $true
}


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
"@ -ForegroundColor $script:BannerColor

    Write-Host '    ┌─────────────────────────────────────────────────────────────────────────────┐' -ForegroundColor $script:BannerColor
    Write-Host '    │            ' -NoNewline -ForegroundColor $script:BannerColor
    Write-Host '⚡ EtherShell - Terminal Tool for Networkwizardry ⚡' -NoNewline -ForegroundColor $script:NormalTextColor
    Write-Host '             │' -ForegroundColor $script:BannerColor
    Write-Host '    └─────────────────────────────────────────────────────────────────────────────┘' -ForegroundColor $script:BannerColor
}


function Get-InternetStatus {
    $urls = @(
        'https://www.msftconnecttest.com/connecttest.txt',
        'https://clients3.google.com/generate_204'
    )

    foreach ($url in $urls) {
        try {
            $response = Invoke-WebRequest -Uri $url -TimeoutSec 2 -ErrorAction Stop
            if ($response.StatusCode -in @(200, 204)) {
                return @{ Status = 'Online'; Color = 'Green' }
            }
        }
        catch {
            # Try the next endpoint.
        }
    }

    return @{ Status = 'Offline'; Color = 'DarkRed' }
}

function Test-LikelyVpnAdapterConnected {
    try {
        $vpnPattern = '(?i)(vpn client|secure client|\bvpn\b|globalprotect|fortinet|forticlient|pulse secure|ivanti|wireguard|openvpn)'
        $vpnAdapters = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object {
                $_.Status -eq 'Up' -and
                (([string]$_.Name + ' ' + [string]$_.InterfaceDescription) -match $vpnPattern)
            })
        return $vpnAdapters.Count -gt 0
    }
    catch {
        return $false
    }
}

function Get-VPNStatus {
    try {
        $settings = Get-EtherShellSettings
        $vpnTestURLs = @($settings['ethershell']['network']['vpnTestURL']) |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    }
    catch {
        return @{ Status = 'Settings Error'; Color = 'Yellow'; URL = '' }
    }

    if ($vpnTestURLs.Count -eq 0) {
        return @{ Status = 'Not Configured'; Color = 'DarkGray'; URL = '' }
    }

    $vpnAdapterConnected = Test-LikelyVpnAdapterConnected
    $sawConnectedDnsUnavailable = $false
    $dnsUnavailableUrl = ''

    foreach ($url in $vpnTestURLs) {
        $urlString = ([string]$url).Trim()
        $fullUrl = if ($urlString -match '^https?://') { $urlString } else { "http://$urlString" }

        try {
            $uri = [System.Uri]$fullUrl
        }
        catch {
            # Invalid configured URL. Try the next endpoint.
            continue
        }

        # Resolve the hostname before starting HTTP/TCP probes. This prevents a
        # broken VPN DNS state from making the main menu wait through repeated
        # connection timeouts. IP-literal endpoints skip this DNS check.
        $parsedAddress = $null
        $hostIsIpAddress = [System.Net.IPAddress]::TryParse($uri.DnsSafeHost, [ref]$parsedAddress)
        if (-not $hostIsIpAddress) {
            try {
                Resolve-DnsName -Name $uri.DnsSafeHost -QuickTimeout -ErrorAction Stop | Out-Null
            }
            catch {
                $dnsErrorText = ('{0} {1}' -f $_.Exception.Message, $_.FullyQualifiedErrorId)
                $dnsWasRefused = $dnsErrorText -match '(?i)(refused|DNS_ERROR_RCODE_REFUSED)'

                if ($vpnAdapterConnected -or $dnsWasRefused) {
                    $sawConnectedDnsUnavailable = $true
                    if ([string]::IsNullOrWhiteSpace($dnsUnavailableUrl)) {
                        $dnsUnavailableUrl = $uri.AbsoluteUri
                    }
                }

                # DNS failed, so HTTP/TCP by hostname cannot succeed. Try the
                # next configured endpoint immediately instead of waiting.
                continue
            }
        }

        # Any real HTTP response proves that the configured VPN endpoint is
        # reachable. Disable keep-alive so adapter changes cannot reuse a stale
        # persistent connection. One bounded request keeps menu redraws fast.
        try {
            $response = Invoke-WebRequest `
                -Uri $uri.AbsoluteUri `
                -TimeoutSec 2 `
                -DisableKeepAlive `
                -SkipHttpErrorCheck `
                -ErrorAction Stop

            $statusCode = [int]$response.StatusCode
            if ($statusCode -ge 100 -and $statusCode -le 599) {
                $script:NetworkReconfigured = $false
                return @{ Status = 'Online'; Color = 'Green'; URL = $uri.AbsoluteUri }
            }
        }
        catch {
            # Fall back to a short TCP reachability check below.
        }

        $port = if ($uri.IsDefaultPort) {
            if ($uri.Scheme -eq 'https') { 443 } else { 80 }
        }
        else {
            $uri.Port
        }

        $tcpClient = $null
        try {
            $tcpClient = [System.Net.Sockets.TcpClient]::new()
            $connectTask = $tcpClient.ConnectAsync($uri.DnsSafeHost, $port)
            if ($connectTask.Wait(800) -and $tcpClient.Connected) {
                $script:NetworkReconfigured = $false
                return @{ Status = 'Online'; Color = 'Green'; URL = $uri.AbsoluteUri }
            }
        }
        catch {
            # Try the next configured VPN endpoint.
        }
        finally {
            if ($tcpClient) {
                $tcpClient.Dispose()
            }
        }
    }

    if ($sawConnectedDnsUnavailable) {
        return @{ Status = 'Connected / DNS unavailable'; Color = 'Yellow'; URL = $dnsUnavailableUrl }
    }

    return @{ Status = 'Offline'; Color = 'DarkRed'; URL = '' }
}

function Write-VpnDnsReconnectHint {
    param (
        [Parameter(Mandatory)]
        $VpnInfo
    )

    if (-not $script:NetworkReconfigured -or
        [string]$VpnInfo.Status -ne 'Connected / DNS unavailable') {
        return
    }

    Write-Host 'VPN DNS resolution failed after network reconfiguration.' -ForegroundColor Yellow
    Write-Host 'A manual VPN reconnect may be required.' -ForegroundColor Yellow
}

function Show-AdapterStatus {
    [CmdletBinding()]
    param (
        [string]$Name = $script:AdapterName
    )

    $adapter = Get-NetAdapter -Name $Name -ErrorAction Stop
    $statusColor = switch ($adapter.Status) {
        'Up' { 'Green' }
        'Disconnected' { 'DarkRed' }
        'Disabled' { 'DarkGray' }
        'Unknown' { 'DarkYellow' }
        default { 'DarkYellow' }
    }

    return [pscustomobject]@{
        Status = $adapter.Status
        Color  = $statusColor
    }
}


function Show-Menu {
    Clear-Host
    Write-Host 'Refreshing network status...' -ForegroundColor DarkGray

    $internetInfo = Get-InternetStatus
    $vpnInfo = Get-VPNStatus

    $adapterStatus = 'Unknown'
    $statusColor = 'DarkYellow'
    $mediaState = 'Unknown'
    $mediaColor = 'DarkYellow'
    $ipMode = 'Unknown'
    $ipv4 = 'Not available'
    $gateway = 'Not available'
    $dnsDisplay = 'Not available'
    $presetInfo = [pscustomobject]@{ Display = 'None'; Color = 'DarkGray' }

    try {
        $adapter = Get-NetAdapter -Name $script:AdapterName -ErrorAction Stop
        $adapterStatus = [string]$adapter.Status
        $statusColor = switch ($adapterStatus) {
            'Up' { 'Green' }
            'Disconnected' { 'DarkRed' }
            'Disabled' { 'DarkGray' }
            'Unknown' { 'DarkYellow' }
            default { 'DarkYellow' }
        }

        $mediaState = [string]$adapter.MediaConnectionState
        $mediaColor = switch ($mediaState) {
            'Connected' { 'Green' }
            'Disconnected' { 'DarkRed' }
            'Unknown' { 'DarkYellow' }
            default { 'DarkYellow' }
        }

        $ipConfig = Get-NetIPConfiguration -InterfaceAlias $script:AdapterName -ErrorAction SilentlyContinue
        if ($ipConfig) {
            if ($ipConfig.IPv4Address) {
                $ipv4 = @($ipConfig.IPv4Address.IPAddress) -join ', '
            }
            if ($ipConfig.IPv4DefaultGateway) {
                $gateway = @($ipConfig.IPv4DefaultGateway.NextHop) -join ', '
            }

            $dnsV4 = @($ipConfig.DnsServer.ServerAddresses | Where-Object {
                    $candidate = [string]$_
                    -not [string]::IsNullOrWhiteSpace($candidate) -and (Test-IPv4Address -Address $candidate)
                })
            if ($dnsV4.Count -gt 0) {
                $dnsDisplay = $dnsV4 -join ', '
            }
        }

        $ipv4Interface = Get-NetIPInterface -InterfaceAlias $script:AdapterName -AddressFamily IPv4 -ErrorAction Stop |
            Select-Object -First 1
        if ($ipv4Interface.Dhcp -eq 'Enabled') {
            $ipMode = 'DHCP'
        }
        else {
            $ipMode = 'Static'
        }

        $presetInfo = Get-ActivePresetInfo -AdapterName $script:AdapterName
    }
    catch {
        # Keep fallback display values so the main menu remains usable.
    }

    Clear-Host
    Show-StartBanner

    Write-Host '┌' -NoNewline -ForegroundColor $script:BannerColor
    Write-Host ' Status'
    Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
    Write-Host " Adapter     : $script:AdapterName"
    Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
    Write-Host ' Status      : ' -NoNewline
    Write-Host $adapterStatus -ForegroundColor $statusColor
    Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
    Write-Host ' Media State : ' -NoNewline
    Write-Host $mediaState -ForegroundColor $mediaColor
    Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
    Write-Host " Mode        : $ipMode"
    Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
    Write-Host ' Preset      : ' -NoNewline
    Write-Host $presetInfo.Display -ForegroundColor $presetInfo.Color
    Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
    Write-Host " IPv4 Address: $ipv4"
    Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
    Write-Host " Gateway     : $gateway"
    Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
    Write-Host " DNS         : $dnsDisplay"
    Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
    Write-Host ' Internet    : ' -NoNewline
    Write-Host $internetInfo.Status -ForegroundColor $internetInfo.Color
    Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
    Write-Host ' VPN         : ' -NoNewline
    Write-Host $vpnInfo.Status -ForegroundColor $vpnInfo.Color
    Write-Host '└──────────────────────────────────────────────' -ForegroundColor $script:BannerColor
    Write-VpnDnsReconnectHint -VpnInfo $vpnInfo

    Write-Host '┌' -NoNewline -ForegroundColor $script:BannerColor
    Write-Host ' Main Menu'
    foreach ($entry in @(
            '[1] Network Configuration',
            '[2] Network Information',
            '[3] Network Tools',
            '[4] Wi-Fi',
            '[5] Settings'
        )) {
        Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
        Write-Host " $entry"
    }
    Write-Host '├──────────────────────────────────────────────' -ForegroundColor $script:BannerColor
    Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
    Write-Host ' [P] Presets    [R] Restart        [Q] Quit'
    Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
    Write-Host ' [M] Manual     [A] About/Info' -ForegroundColor DarkGray
    Write-Host '├──────────────────────────────────────────────' -ForegroundColor $script:BannerColor
    Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
    Write-Host ' Type a preset name to apply directly.' -ForegroundColor DarkGray
    Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
    Write-Host ' Or enter a preset ID (e.g. id1).' -ForegroundColor DarkGray
    Write-Host '└──────────────────────────────────────────────' -ForegroundColor $script:BannerColor

    return Read-Host "`nGo"
}


function Show-SectionHeader {
    param (
        [Parameter(Mandatory)]
        [string]$Title,

        [string]$Subtitle = ''
    )

    Clear-Host
    Write-Host '┌' -NoNewline -ForegroundColor $script:BannerColor
    Write-Host " EtherShell > $Title"
    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
        Write-Host " $Subtitle" -ForegroundColor DarkGray
    }
    Write-Host '└──────────────────────────────────────────────' -ForegroundColor $script:BannerColor
    Write-Host
}

# ────────────────────────────────────────────────────────
# Adapter selection / overview
# ────────────────────────────────────────────────────────
function Select-Adapter {
    [CmdletBinding()]
    param (
        [string]$Title = "`nPlease select a network adapter:"
    )

    $presetAdapters = @{}
    try {
        $settings = Get-EtherShellSettings
        $adapterPresets = $settings['ethershell']['network']['adapter']
        foreach ($entry in $adapterPresets.GetEnumerator()) {
            if ($entry.Value -is [System.Collections.IDictionary] -and $entry.Value.Count -gt 0) {
                $presetAdapters[$entry.Key] = $true
            }
        }
    }
    catch {
        # Adapter selection still works if settings.json is unavailable.
    }

    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -ne 'Unknown' } |
        Sort-Object Name)

    if ($adapters.Count -eq 0) {
        Write-Host '❌ No network adapters found.' -ForegroundColor Red
        return $null
    }

    Write-Host $Title -ForegroundColor DarkCyan
    Write-Host "( * ) = preset exists`n" -ForegroundColor DarkGray

    $indexWidth = [Math]::Max(3, ($adapters.Count.ToString().Length + 2))
    $nameMaxLength = 30

    for ($i = 0; $i -lt $adapters.Count; $i++) {
        $entry = $adapters[$i]
        $statusColor = switch ($entry.Status) {
            'Up' { 'Green' }
            'Disconnected' { 'DarkGray' }
            'Disabled' { 'Red' }
            default { 'Gray' }
        }

        $marker = if ($entry.Name -ieq $script:AdapterName) { ' (SELECTED)' } else { '' }
        $shortName = if ($entry.Name.Length -gt $nameMaxLength) {
            $entry.Name.Substring(0, $nameMaxLength - 1) + '…'
        }
        else {
            $entry.Name
        }

        $index = '[{0}]' -f ($i + 1)
        $presetMark = if ($presetAdapters.ContainsKey($entry.Name)) { ' *' } else { '' }

        Write-Host -NoNewline ("{0} " -f $index.PadRight($indexWidth))
        Write-Host -NoNewline $shortName.PadRight($nameMaxLength) -ForegroundColor $statusColor
        Write-Host -NoNewline ' |  '
        Write-Host ("{0}{1}" -f ($entry.Status + $marker), $presetMark) -ForegroundColor $statusColor
    }

    do {
        $inputValue = Read-Host "Enter adapter number [1-$($adapters.Count)] or Q to cancel"
        if ($inputValue.Trim() -match '^[Qq]$') {
            Write-Host '↩️ Cancelled by user.' -ForegroundColor DarkGray
            return $null
        }

        $valid = $inputValue -match '^\d+$' -and
            [int]$inputValue -ge 1 -and
            [int]$inputValue -le $adapters.Count

        if (-not $valid) {
            Write-Host "❌ Invalid input. Enter 1-$($adapters.Count), or Q to cancel." -ForegroundColor Red
        }
    } until ($valid)

    return $adapters[[int]$inputValue - 1].Name
}

function Set-ActiveAdapter {
    $selected = Select-Adapter -Title "`nSelect active network adapter:"
    if (-not $selected) { return }

    if ($selected -eq $script:AdapterName) {
        Write-Host "`n↪️ No changes made. Adapter remains '$script:AdapterName'." -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 700
        return
    }

    try {
        Update-EtherShellSettings -UpdateAction {
            param($settings)
            $settings['ethershell']['defaultAdapter'] = $selected
            return $settings
        } | Out-Null

        $script:AdapterName = $selected
        Write-Host "`n✅ Active adapter set to '$script:AdapterName'." -ForegroundColor Green
        Write-Host '💾 Saved default adapter.' -ForegroundColor DarkGray
    }
    catch {
        Write-Host "`n❌ Could not save the selected adapter: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'The current adapter selection was not changed.' -ForegroundColor Yellow
    }

    Start-Sleep -Milliseconds 900
}

function Show-StatusLegend {
    Write-Host "`n ┌─ " -NoNewline
    Write-Host 'Green' -ForegroundColor Green -NoNewline
    Write-Host '      : Adapter is UP / Media Connected'
    Write-Host ' ├─ ' -NoNewline
    Write-Host 'Red' -ForegroundColor Red -NoNewline
    Write-Host '        : Disabled'
    Write-Host ' ├─ ' -NoNewline
    Write-Host 'DarkRed' -ForegroundColor DarkRed -NoNewline
    Write-Host '    : Unknown media state'
    Write-Host ' ├─ ' -NoNewline
    Write-Host 'DarkGray' -ForegroundColor DarkGray -NoNewline
    Write-Host '   : Disconnected'
    Write-Host ' └─ ' -NoNewline
    Write-Host 'Gray' -ForegroundColor Gray -NoNewline
    Write-Host '       : Unspecified / fallback'
}

function Show-NetworkOverview {
    [CmdletBinding()]
    param (
        [string]$ActiveAdapter = $script:AdapterName,
        [switch]$HideIPv6DNS,
        [switch]$OnlyActive
    )

    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($adapters.Count -eq 0) {
        Write-Host "`n❌ No network adapters found." -ForegroundColor Red
        return
    }

    Show-StatusLegend

    foreach ($adapter in $adapters) {
        $isActive = $adapter.Name -ieq $ActiveAdapter
        if ($OnlyActive -and -not $isActive) { continue }

        $statusColor = switch ($adapter.Status) {
            'Up' { 'Green' }
            'Disconnected' { 'DarkGray' }
            'Disabled' { 'Red' }
            default { 'Gray' }
        }

        $mediaColor = switch ([string]$adapter.MediaConnectionState) {
            'Connected' { 'Green' }
            'Disconnected' { 'DarkGray' }
            'Unknown' { 'DarkRed' }
            default { 'Gray' }
        }

        Write-Host "`n ┌─ " -NoNewline -ForegroundColor White
        Write-Host -NoNewline $adapter.Name -ForegroundColor $statusColor
        if ($isActive) { Write-Host ' (SELECTED)' } else { Write-Host }

        Write-Host -NoNewline ' │  Status     : '
        Write-Host $adapter.Status -ForegroundColor $statusColor
        Write-Host -NoNewline ' │  MediaState : '
        Write-Host $adapter.MediaConnectionState -ForegroundColor $mediaColor

        $ipConfig = Get-NetIPConfiguration -InterfaceAlias $adapter.Name -ErrorAction SilentlyContinue
        $ipv4Addresses = @()
        if ($ipConfig) {
            $ipv4Addresses = @($ipConfig.IPv4Address)
        }

        if ($ipv4Addresses.Count -gt 0) {
            foreach ($ipv4Obj in $ipv4Addresses) {
                $ipv4 = [string]$ipv4Obj.IPAddress
                $prefix = [int]$ipv4Obj.PrefixLength
                $subnetMask = ConvertTo-SubnetMask -PrefixLength $prefix

                $ipBytes = [System.Net.IPAddress]::Parse($ipv4).GetAddressBytes()
                $maskBytes = [System.Net.IPAddress]::Parse($subnetMask).GetAddressBytes()
                $netBytes = for ($i = 0; $i -lt 4; $i++) {
                    $ipBytes[$i] -band $maskBytes[$i]
                }
                $networkAddress = [string]::Join('.', $netBytes)

                Write-Host " │  IPv4       : $ipv4"
                Write-Host " │  Subnetmask : $subnetMask"
                Write-Host " │  Subnet     : $networkAddress/$prefix"
                Write-Host " │  Prefix     : $prefix"
            }
        }
        else {
            Write-Host ' │  IPv4       : Not available'
        }

        Write-Host -NoNewline ' │  Gateway    : '
        if ($ipConfig -and $ipConfig.IPv4DefaultGateway) {
            Write-Host (@($ipConfig.IPv4DefaultGateway.NextHop) -join ', ')
        }
        else {
            Write-Host 'Not available'
        }

        if ($ipConfig -and $ipConfig.DnsServer) {
            $dnsAddresses = @($ipConfig.DnsServer.ServerAddresses)
            $dnsV4 = @($dnsAddresses | Where-Object { Test-IPv4Address -Address ([string]$_) })
            $dnsV6 = @($dnsAddresses | Where-Object { -not (Test-IPv4Address -Address ([string]$_)) })

            if ($dnsV4.Count -gt 0) {
                Write-Host " │  DNS        : $($dnsV4 -join ', ')"
            }
            if ($dnsV6.Count -gt 0 -and -not $HideIPv6DNS) {
                Write-Host " │  DNSv6      : $($dnsV6 -join ', ')"
            }
        }

        Write-Host ' └───────────────────────────────'
    }

    Pause-EtherShell -Message 'Press any key to go back...'
}

# ────────────────────────────────────────────────────────
# IPv4 state / safe apply helpers
# ────────────────────────────────────────────────────────
function Get-IPv4ConfigurationSnapshot {
    param (
        [Parameter(Mandatory)]
        [string]$AdapterName
    )

    $ipInterface = Get-NetIPInterface -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction Stop |
        Select-Object -First 1

    $addresses = @(Get-NetIPAddress -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -ne '127.0.0.1' } |
        ForEach-Object {
            [pscustomobject]@{
                IPAddress    = [string]$_.IPAddress
                PrefixLength = [int]$_.PrefixLength
                SkipAsSource = [bool]$_.SkipAsSource
            }
        })

    $routes = @(Get-NetRoute -InterfaceAlias $AdapterName -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        ForEach-Object {
            [pscustomobject]@{
                NextHop     = [string]$_.NextHop
                RouteMetric = [int]$_.RouteMetric
            }
        })

    $dns = @(Get-DnsClientServerAddress -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        ForEach-Object { $_.ServerAddresses } |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

    $dnsIsStatic = $false
    try {
        $netAdapter = Get-NetAdapter -Name $AdapterName -ErrorAction Stop
        $interfaceGuid = ([guid]$netAdapter.InterfaceGuid).ToString('B')
        $tcpipKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$interfaceGuid"
        $nameServer = Get-ItemPropertyValue -Path $tcpipKey -Name 'NameServer' -ErrorAction SilentlyContinue
        $dnsIsStatic = -not [string]::IsNullOrWhiteSpace([string]$nameServer)
    }
    catch {
        # If the source cannot be determined, preserve the observed addresses on rollback.
        $dnsIsStatic = $dns.Count -gt 0
    }

    return [pscustomobject]@{
        Dhcp        = [string]$ipInterface.Dhcp
        Addresses   = $addresses
        Routes      = $routes
        DnsServers  = $dns
        DnsIsStatic = $dnsIsStatic
    }
}

function Clear-IPv4ConfigurationInternal {
    param (
        [Parameter(Mandatory)]
        [string]$AdapterName,
        [switch]$DisableDhcp,
        [switch]$ResetDns
    )

    if ($DisableDhcp) {
        Set-NetIPInterface -InterfaceAlias $AdapterName -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop
    }

    $existingAddresses = @(Get-NetIPAddress -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    if ($existingAddresses.Count -gt 0) {
        $existingAddresses | Remove-NetIPAddress -Confirm:$false -ErrorAction Stop | Out-Null
    }

    $existingDefaultRoutes = @(Get-NetRoute -InterfaceAlias $AdapterName -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)
    if ($existingDefaultRoutes.Count -gt 0) {
        $existingDefaultRoutes | Remove-NetRoute -Confirm:$false -ErrorAction Stop | Out-Null
    }

    if ($ResetDns) {
        Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ResetServerAddresses -ErrorAction Stop
    }
}

function Restore-IPv4ConfigurationSnapshot {
    param (
        [Parameter(Mandatory)] [string]$AdapterName,
        [Parameter(Mandatory)] $Snapshot
    )

    try {
        Clear-IPv4ConfigurationInternal -AdapterName $AdapterName -DisableDhcp -ResetDns

        if ($Snapshot.Dhcp -eq 'Enabled') {
            Set-NetIPInterface -InterfaceAlias $AdapterName -AddressFamily IPv4 -Dhcp Enabled -ErrorAction Stop

            if ($Snapshot.DnsIsStatic -and @($Snapshot.DnsServers).Count -gt 0) {
                Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ServerAddresses @($Snapshot.DnsServers) -ErrorAction Stop
            }
            else {
                Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ResetServerAddresses -ErrorAction Stop
            }

            & ipconfig.exe /renew "$AdapterName" | Out-Null
            return $true
        }

        Set-NetIPInterface -InterfaceAlias $AdapterName -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop

        foreach ($address in @($Snapshot.Addresses)) {
            New-NetIPAddress -InterfaceAlias $AdapterName `
                -AddressFamily IPv4 `
                -IPAddress $address.IPAddress `
                -PrefixLength $address.PrefixLength `
                -SkipAsSource $address.SkipAsSource `
                -ErrorAction Stop | Out-Null
        }

        foreach ($route in @($Snapshot.Routes)) {
            if (-not [string]::IsNullOrWhiteSpace($route.NextHop) -and $route.NextHop -ne '0.0.0.0') {
                New-NetRoute -InterfaceAlias $AdapterName `
                    -AddressFamily IPv4 `
                    -DestinationPrefix '0.0.0.0/0' `
                    -NextHop $route.NextHop `
                    -RouteMetric $route.RouteMetric `
                    -ErrorAction Stop | Out-Null
            }
        }

        if ($Snapshot.DnsIsStatic -and @($Snapshot.DnsServers).Count -gt 0) {
            Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ServerAddresses @($Snapshot.DnsServers) -ErrorAction Stop
        }
        else {
            Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ResetServerAddresses -ErrorAction Stop
        }

        return $true
    }
    catch {
        Write-Host "⚠️ Automatic rollback failed: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

function Set-StaticIPv4ConfigurationInternal {
    param (
        [Parameter(Mandatory)] [string]$AdapterName,
        [Parameter(Mandatory)] [string]$IPv4,
        [Parameter(Mandatory)] [string]$Subnet,
        [Parameter(Mandatory)] [int]$Prefix,
        [Parameter(Mandatory)] [string]$Gateway,
        [Parameter(Mandatory)] [string]$Dns
    )

    $validationErrors = Test-StaticConfiguration -IPv4 $IPv4 -Subnet $Subnet -Prefix $Prefix -Gateway $Gateway -Dns $Dns
    if ($validationErrors.Count -gt 0) {
        throw ($validationErrors -join ' ')
    }

    $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction Stop
    if ($adapter.Status -eq 'Disabled') {
        throw "Adapter '$AdapterName' is disabled."
    }

    $snapshot = Get-IPv4ConfigurationSnapshot -AdapterName $AdapterName

    try {
        Set-NetIPInterface -InterfaceAlias $AdapterName -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop

        $existingAddresses = @(Get-NetIPAddress -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue)
        if ($existingAddresses.Count -gt 0) {
            $existingAddresses | Remove-NetIPAddress -Confirm:$false -ErrorAction Stop | Out-Null
        }

        $existingDefaultRoutes = @(Get-NetRoute -InterfaceAlias $AdapterName -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)
        if ($existingDefaultRoutes.Count -gt 0) {
            $existingDefaultRoutes | Remove-NetRoute -Confirm:$false -ErrorAction Stop | Out-Null
        }

        New-NetIPAddress -InterfaceAlias $AdapterName `
            -AddressFamily IPv4 `
            -IPAddress $IPv4 `
            -PrefixLength $Prefix `
            -DefaultGateway $Gateway `
            -ErrorAction Stop | Out-Null

        Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ServerAddresses $Dns -ErrorAction Stop
        $script:NetworkReconfigured = $true
        return $true
    }
    catch {
        $originalError = $_.Exception.Message
        Write-Host "⚠️ Applying the new configuration failed. Attempting rollback..." -ForegroundColor Yellow
        $rollbackOk = Restore-IPv4ConfigurationSnapshot -AdapterName $AdapterName -Snapshot $snapshot
        if ($rollbackOk) {
            throw "$originalError Previous IPv4 configuration was restored."
        }
        throw "$originalError Rollback also failed; verify the adapter configuration manually."
    }
}

function Set-DhcpIPv4ConfigurationInternal {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$AdapterName,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$DnsServer,

        [switch]$AutoDns
    )

    if (-not $AutoDns -and -not (Test-IPv4Address -Address $DnsServer)) {
        throw "Invalid DHCP DNS server address: $DnsServer"
    }

    $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction Stop
    if ($adapter.Status -eq 'Disabled') {
        throw "Adapter '$AdapterName' is disabled."
    }

    $snapshot = Get-IPv4ConfigurationSnapshot -AdapterName $AdapterName

    try {
        Clear-IPv4ConfigurationInternal -AdapterName $AdapterName -DisableDhcp -ResetDns
        Set-NetIPInterface -InterfaceAlias $AdapterName -AddressFamily IPv4 -Dhcp Enabled -ErrorAction Stop

        if ($AutoDns) {
            Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ResetServerAddresses -ErrorAction Stop
        }
        else {
            Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ServerAddresses $DnsServer -ErrorAction Stop
        }

        & ipconfig.exe /renew "$AdapterName" | Out-Null
        $script:NetworkReconfigured = $true
        return $true
    }
    catch {
        $originalError = $_.Exception.Message
        Write-Host '⚠️ Applying the DHCP preset failed. Attempting rollback...' -ForegroundColor Yellow
        $rollbackOk = Restore-IPv4ConfigurationSnapshot -AdapterName $AdapterName -Snapshot $snapshot
        if ($rollbackOk) {
            throw "$originalError Previous IPv4 configuration was restored."
        }
        throw "$originalError Rollback also failed; verify the adapter configuration manually."
    }
}

function Read-StaticIPv4Configuration {
    param (
        [Parameter(Mandatory)]
        [string]$AdapterName
    )

    Write-Host "`nEnter static settings for '$AdapterName'" -ForegroundColor DarkCyan

    do {
        $ipv4 = Read-Host 'IP-Address [default: 192.168.1.2]'
        if ([string]::IsNullOrWhiteSpace($ipv4)) { $ipv4 = '192.168.1.2' }
        $valid = Test-IPv4Address -Address $ipv4
        if (-not $valid) { Write-Host '❌ Invalid IPv4 address.' -ForegroundColor Red }
    } until ($valid)

    do {
        $subnet = Read-Host 'Subnetmask [default: 255.255.255.0]'
        if ([string]::IsNullOrWhiteSpace($subnet)) { $subnet = '255.255.255.0' }
        $valid = Test-IPv4SubnetMask -Mask $subnet
        if (-not $valid) { Write-Host '❌ Invalid or non-contiguous subnet mask.' -ForegroundColor Red }
    } until ($valid)

    $prefix = ConvertTo-PrefixLength -Mask $subnet

    do {
        $gateway = Read-Host 'Gateway [default: 192.168.1.1]'
        if ([string]::IsNullOrWhiteSpace($gateway)) { $gateway = '192.168.1.1' }
        $valid = Test-IPv4Address -Address $gateway
        if (-not $valid) {
            Write-Host '❌ Invalid gateway address.' -ForegroundColor Red
            continue
        }

        if (-not (Test-SameIPv4Subnet -Address1 $ipv4 -Address2 $gateway -Mask $subnet)) {
            Write-Host '⚠️ Gateway is not in the same subnet as the IPv4 address.' -ForegroundColor Yellow
            $valid = Confirm-EtherShellAction -Prompt 'Continue with this gateway anyway?'
        }
    } until ($valid)

    do {
        $dns = Read-Host 'DNS-Server [default: 192.168.1.1]'
        if ([string]::IsNullOrWhiteSpace($dns)) { $dns = '192.168.1.1' }
        $valid = Test-IPv4Address -Address $dns
        if (-not $valid) { Write-Host '❌ DNS server must be an IPv4 address.' -ForegroundColor Red }
    } until ($valid)

    return [pscustomobject]@{
        IPv4    = $ipv4
        Subnet  = $subnet
        Prefix  = $prefix
        Gateway = $gateway
        Dns     = $dns
    }
}

function Show-StaticConfiguration {
    param (
        [Parameter(Mandatory)] [string]$AdapterName,
        [Parameter(Mandatory)] $Configuration,
        [string]$PresetName
    )

    if ($PresetName) {
        Write-Host "`nPreset '$PresetName' for '$AdapterName':" -ForegroundColor DarkCyan
    }
    else {
        Write-Host "`nChosen configuration for '$AdapterName':" -ForegroundColor DarkCyan
    }

    Write-Host "  IP-Address   : $($Configuration.IPv4)"
    Write-Host "  Subnetmask   : $($Configuration.Subnet)"
    Write-Host "  Prefix       : $($Configuration.Prefix)"
    Write-Host "  Gateway      : $($Configuration.Gateway)"
    Write-Host "  DNS-Server   : $($Configuration.Dns)"
}

function Convert-PresetToConfiguration {
    param (
        [Parameter(Mandatory)]
        $PresetSettings
    )

    $configuration = [pscustomobject]@{
        IPv4    = [string]$PresetSettings['ipv4']
        Subnet  = [string]$PresetSettings['subnet']
        Prefix  = [int]$PresetSettings['prefix']
        Gateway = [string]$PresetSettings['gateway']
        Dns     = [string]$PresetSettings['dns']
    }

    $errors = Test-StaticConfiguration `
        -IPv4 $configuration.IPv4 `
        -Subnet $configuration.Subnet `
        -Prefix $configuration.Prefix `
        -Gateway $configuration.Gateway `
        -Dns $configuration.Dns

    if ($errors.Count -gt 0) {
        throw ("Preset is invalid: " + ($errors -join ' '))
    }

    return $configuration
}

# ────────────────────────────────────────────────────────
# Static IP / presets
# ────────────────────────────────────────────────────────
function Test-ReservedPresetName {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )

    $normalizedName = $Name.Trim().ToLowerInvariant()
    if ($normalizedName -in @('1', '2', '3', '4', '5', 'a', 'm', 'p', 'q', 'r', 'dhcp-auto')) {
        return $true
    }

    # idN is reserved for direct preset-ID invocation in the main menu.
    return $normalizedName -match '^id\d+$'
}

function Get-PresetNameMatches {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $normalizedName = $Name.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($normalizedName)) { return @() }

    $records = @(Get-AllPresetRecords -Settings $Settings)
    return @($records | Where-Object {
            $_.PresetName.Trim().ToLowerInvariant() -eq $normalizedName
        })
}

function Get-AllPresetRecords {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $settingsNormalized = Initialize-SettingsStructure -Settings $Settings
    $network = $settingsNormalized['ethershell']['network']
    $records = @()

    $systemPresets = $network['systemPresets']
    foreach ($entry in @($systemPresets.GetEnumerator() | Sort-Object Key)) {
        if (-not ($entry.Value -is [System.Collections.IDictionary])) { continue }
        $id = -1
        try { $id = [int]$entry.Value['id'] } catch {}
        $records += [pscustomobject]@{
            Id          = $id
            PresetName  = [string]$entry.Key
            AdapterName = ''
            Scope       = 'System'
            Type        = ([string]$entry.Value['type']).Trim().ToLowerInvariant()
            Protected   = [bool]$entry.Value['protected']
            Settings    = $entry.Value
        }
    }

    $adapterPresets = $network['adapter']
    foreach ($adapterEntry in @($adapterPresets.GetEnumerator() | Sort-Object Key)) {
        $adapterName = [string]$adapterEntry.Key
        $presets = $adapterEntry.Value
        if (-not ($presets -is [System.Collections.IDictionary])) { continue }

        foreach ($presetEntry in @($presets.GetEnumerator() | Sort-Object Key)) {
            if (-not ($presetEntry.Value -is [System.Collections.IDictionary])) { continue }
            $id = -1
            try { $id = [int]$presetEntry.Value['id'] } catch {}
            $type = if ($presetEntry.Value.Contains('type')) {
                ([string]$presetEntry.Value['type']).Trim().ToLowerInvariant()
            }
            else { 'static' }

            $records += [pscustomobject]@{
                Id          = $id
                PresetName  = [string]$presetEntry.Key
                AdapterName = $adapterName
                Scope       = 'Adapter'
                Type        = $type
                Protected   = $false
                Settings    = $presetEntry.Value
            }
        }
    }

    return @($records)
}

function Get-PresetIdMatches {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [int]$Id,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    return @(Get-AllPresetRecords -Settings $Settings | Where-Object { $_.Id -eq $Id })
}

function Get-NextFreePresetId {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $usedIds = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($record in @(Get-AllPresetRecords -Settings $Settings)) {
        if ($record.Id -ge 0) { $null = $usedIds.Add([int]$record.Id) }
    }

    $candidate = 1
    while ($usedIds.Contains($candidate)) { $candidate++ }
    return $candidate
}

function Resolve-PresetReference {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Reference,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings
    )

    $normalized = $Reference.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($normalized)) { return @() }

    if ($normalized -match '^id(\d+)$') {
        return @(Get-PresetIdMatches -Id ([int]$Matches[1]) -Settings $Settings)
    }

    return @(Get-PresetNameMatches -Name $normalized -Settings $Settings)
}

function Remove-PresetRecordFromSettings {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Settings,

        [Parameter(Mandatory)]
        $Record
    )

    if ($Record.Scope -eq 'System' -or $Record.Protected -or $Record.Id -eq 0 -or
        $Record.PresetName.Trim().ToLowerInvariant() -eq 'dhcp-auto') {
        throw "Preset 'dhcp-auto' (id0) is protected and cannot be deleted or overwritten."
    }

    $adapters = $Settings['ethershell']['network']['adapter']
    if ($adapters.Contains($Record.AdapterName) -and
        $adapters[$Record.AdapterName] -is [System.Collections.IDictionary] -and
        $adapters[$Record.AdapterName].Contains($Record.PresetName)) {
        $adapters[$Record.AdapterName].Remove($Record.PresetName)
        if ($adapters[$Record.AdapterName].Count -eq 0) {
            $adapters.Remove($Record.AdapterName)
        }
    }
}

function Get-PresetType {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$PresetSettings
    )

    if (-not $PresetSettings.Contains('type') -or
        [string]::IsNullOrWhiteSpace([string]$PresetSettings['type'])) {
        return 'static'
    }

    return ([string]$PresetSettings['type']).Trim().ToLowerInvariant()
}

function Show-PresetConfiguration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        $Record,

        [Parameter(Mandatory)]
        [string]$AdapterName
    )

    $idText = if ($Record.Id -ge 0) { "id$($Record.Id)" } else { 'no-id' }
    Write-Host "`nPreset '$($Record.PresetName)' ($idText) for '$AdapterName':" -ForegroundColor DarkCyan

    if ($Record.Type -eq 'dhcp') {
        $dnsMode = if ($Record.Settings.Contains('dnsMode')) {
            ([string]$Record.Settings['dnsMode']).Trim().ToLowerInvariant()
        }
        else { 'custom' }

        Write-Host '  Type         : DHCP'
        if ($dnsMode -eq 'auto') {
            Write-Host '  DNS          : Automatic (DHCP-provided)'
        }
        else {
            Write-Host "  DNS          : $([string]$Record.Settings['dns'])"
        }
        return
    }

    $configuration = Convert-PresetToConfiguration -PresetSettings $Record.Settings
    Write-Host '  Type         : Static IPv4'
    Write-Host "  IP-Address   : $($configuration.IPv4)"
    Write-Host "  Subnetmask   : $($configuration.Subnet)"
    Write-Host "  Prefix       : $($configuration.Prefix)"
    Write-Host "  Gateway      : $($configuration.Gateway)"
    Write-Host "  DNS-Server   : $($configuration.Dns)"
}

function Apply-PresetRecord {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        $Record,

        [string]$AdapterName,

        [switch]$SkipConfirmation
    )

    $targetAdapter = if ($Record.Scope -eq 'System') {
        if ([string]::IsNullOrWhiteSpace($AdapterName)) { $script:AdapterName } else { $AdapterName }
    }
    else {
        [string]$Record.AdapterName
    }

    if ([string]::IsNullOrWhiteSpace($targetAdapter)) {
        Write-Host '`n❌ No adapter is selected.' -ForegroundColor Red
        Pause-EtherShell
        return
    }

    $adapter = Get-NetAdapter -Name $targetAdapter -ErrorAction SilentlyContinue
    if (-not $adapter) {
        Write-Host "`n❌ Preset '$($Record.PresetName)' targets adapter '$targetAdapter', but that adapter was not found." -ForegroundColor Red
        Pause-EtherShell
        return
    }
    if ($adapter.Status -eq 'Disabled') {
        Write-Host "`n❌ Adapter '$targetAdapter' is disabled." -ForegroundColor Red
        Pause-EtherShell
        return
    }

    try {
        Show-PresetConfiguration -Record $Record -AdapterName $targetAdapter
    }
    catch {
        Write-Host "`n❌ Preset '$($Record.PresetName)' is invalid: $($_.Exception.Message)" -ForegroundColor Red
        Pause-EtherShell
        return
    }

    if (-not $SkipConfirmation -and -not (Confirm-EtherShellAction -Prompt 'Apply this preset?')) {
        Write-Host '`n↩️ Operation cancelled.' -ForegroundColor DarkGray
        return
    }

    Write-Host "`nApplying preset '$($Record.PresetName)' (id$($Record.Id)) to '$targetAdapter'..." -ForegroundColor DarkCyan

    try {
        if ($Record.Type -eq 'dhcp') {
            $dnsMode = if ($Record.Settings.Contains('dnsMode')) {
                ([string]$Record.Settings['dnsMode']).Trim().ToLowerInvariant()
            }
            else { 'custom' }

            if ($dnsMode -eq 'auto') {
                Set-DhcpIPv4ConfigurationInternal -AdapterName $targetAdapter -AutoDns | Out-Null
            }
            else {
                $dnsServer = [string]$Record.Settings['dns']
                if (-not (Test-IPv4Address -Address $dnsServer)) {
                    throw "Preset contains an invalid DHCP DNS server: $dnsServer"
                }
                Set-DhcpIPv4ConfigurationInternal -AdapterName $targetAdapter -DnsServer $dnsServer | Out-Null
            }
        }
        elseif ($Record.Type -eq 'static') {
            $configuration = Convert-PresetToConfiguration -PresetSettings $Record.Settings
            Set-StaticIPv4ConfigurationInternal `
                -AdapterName $targetAdapter `
                -IPv4 $configuration.IPv4 `
                -Subnet $configuration.Subnet `
                -Prefix $configuration.Prefix `
                -Gateway $configuration.Gateway `
                -Dns $configuration.Dns | Out-Null
        }
        else {
            throw "Unsupported preset type '$($Record.Type)'."
        }

        $script:AdapterName = $targetAdapter
        Update-EtherShellSettings -UpdateAction {
            param($latest)
            $latest['ethershell']['defaultAdapter'] = $targetAdapter
            if ($Record.Type -eq 'dhcp') {
                $dnsMode = if ($Record.Settings.Contains('dnsMode')) {
                    ([string]$Record.Settings['dnsMode']).Trim().ToLowerInvariant()
                }
                else { 'custom' }
                $latest['ethershell']['network']['dhcpDns'] = if ($dnsMode -eq 'auto') { '' } else { [string]$Record.Settings['dns'] }
            }
            return $latest
        } | Out-Null

        Write-Host '✅ Preset applied successfully.' -ForegroundColor Green
    }
    catch {
        Write-Host "`n❌ Failed to apply preset: $($_.Exception.Message)" -ForegroundColor Red
        Pause-EtherShell
        return
    }

    Start-Sleep -Milliseconds 900
}

function Get-ActivePresetInfo {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$AdapterName
    )

    $none = [pscustomobject]@{ Name = 'None'; Id = $null; Display = 'None'; Color = 'DarkGray' }

    try {
        $settings = Get-EtherShellSettings
        $snapshot = Get-IPv4ConfigurationSnapshot -AdapterName $AdapterName
        $records = @(Get-AllPresetRecords -Settings $settings)
    }
    catch {
        return $none
    }

    if ($snapshot.Dhcp -eq 'Enabled') {
        if (-not $snapshot.DnsIsStatic) {
            return [pscustomobject]@{ Name = 'dhcp-auto'; Id = 0; Display = 'dhcp-auto (id0)'; Color = 'Cyan' }
        }

        $activeDns = @($snapshot.DnsServers | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
        $matches = @($records | Where-Object {
                $_.Scope -eq 'Adapter' -and
                $_.AdapterName -eq $AdapterName -and
                $_.Type -eq 'dhcp' -and
                ($(if ($_.Settings.Contains('dnsMode')) { ([string]$_.Settings['dnsMode']).Trim().ToLowerInvariant() } else { 'custom' }) -eq 'custom') -and
                $activeDns.Count -eq 1 -and
                $activeDns[0] -eq ([string]$_.Settings['dns']).Trim()
            })
    }
    else {
        $addresses = @($snapshot.Addresses | Where-Object { $_.IPAddress -and $_.IPAddress -notlike '169.254.*' })
        $routes = @($snapshot.Routes | Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' })
        $dns = @($snapshot.DnsServers | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })

        $matches = @()
        foreach ($record in @($records | Where-Object {
                    $_.Scope -eq 'Adapter' -and $_.AdapterName -eq $AdapterName -and $_.Type -eq 'static'
                })) {
            try {
                $configuration = Convert-PresetToConfiguration -PresetSettings $record.Settings
                $addressMatches = $addresses.Count -eq 1 -and
                    $addresses[0].IPAddress -eq $configuration.IPv4 -and
                    [int]$addresses[0].PrefixLength -eq [int]$configuration.Prefix
                $gatewayMatches = $routes.Count -ge 1 -and (@($routes.NextHop) -contains $configuration.Gateway)
                $dnsMatches = $dns.Count -eq 1 -and $dns[0] -eq $configuration.Dns

                if ($addressMatches -and $gatewayMatches -and $dnsMatches) {
                    $matches += $record
                }
            }
            catch {
                # Invalid preset does not match the live configuration.
            }
        }
    }

    if ($matches.Count -eq 1) {
        return [pscustomobject]@{
            Name    = $matches[0].PresetName
            Id      = $matches[0].Id
            Display = "$($matches[0].PresetName) (id$($matches[0].Id))"
            Color   = 'Cyan'
        }
    }

    if ($matches.Count -gt 1) {
        return [pscustomobject]@{ Name = 'Multiple'; Id = $null; Display = 'Multiple'; Color = 'Yellow' }
    }

    return $none
}


function Invoke-MainMenuPreset {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )

    $reference = $Name.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($reference)) { return }

    try {
        $settings = Get-EtherShellSettings
        $matches = @(Resolve-PresetReference -Reference $reference -Settings $settings)
    }
    catch {
        Write-Host "`n❌ Preset lookup failed because settings.json could not be read: $($_.Exception.Message)" -ForegroundColor Red
        Pause-EtherShell
        return
    }

    if ($matches.Count -eq 0) {
        Write-Host "`n❌ Unknown menu choice or preset: '$reference'." -ForegroundColor Red
        Start-Sleep -Milliseconds 900
        return
    }

    if ($matches.Count -gt 1) {
        Write-Host "`n❌ Preset reference '$reference' is ambiguous." -ForegroundColor Red
        foreach ($match in ($matches | Sort-Object Id, AdapterName, PresetName)) {
            $adapterText = if ($match.Scope -eq 'System') { 'current adapter' } else { $match.AdapterName }
            Write-Host "   - id$($match.Id) : $($match.PresetName) [$adapterText]" -ForegroundColor DarkCyan
        }
        Write-Host '   Resolve duplicate preset metadata before applying a preset.' -ForegroundColor Yellow
        Pause-EtherShell
        return
    }

    Apply-PresetRecord -Record $matches[0] -AdapterName $script:AdapterName -SkipConfirmation
}

function Select-Preset {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Json,

        [Parameter(Mandatory)]
        [string]$AdapterName
    )

    $records = @(Get-AllPresetRecords -Settings $Json | Where-Object {
            $_.Scope -eq 'System' -or $_.AdapterName -eq $AdapterName
        } | Sort-Object Id, PresetName)

    if ($records.Count -eq 0) { return $null }

    Write-Host "`nAvailable Presets for '$AdapterName':" -ForegroundColor DarkCyan
    for ($i = 0; $i -lt $records.Count; $i++) {
        $record = $records[$i]
        $typeText = if ($record.Type -eq 'dhcp') {
            $dnsMode = if ($record.Settings.Contains('dnsMode')) { ([string]$record.Settings['dnsMode']).Trim().ToLowerInvariant() } else { 'custom' }
            if ($dnsMode -eq 'auto') { 'DHCP / Auto DNS' } else { "DHCP / DNS $([string]$record.Settings['dns'])" }
        }
        else { 'Static IPv4' }
        $protectedText = if ($record.Protected) { ' [protected]' } else { '' }
        Write-Host "[$($i + 1)] id$($record.Id)  $($record.PresetName)  ($typeText)$protectedText"
    }

    do {
        $selection = (Read-Host "`nSelect number, preset name, ID (e.g. id1), or Q to cancel").Trim()
        if ($selection -match '^[Qq]$') { return $null }

        if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $records.Count) {
            return $records[[int]$selection - 1]
        }

        $matches = @(Resolve-PresetReference -Reference $selection -Settings $Json | Where-Object {
                $_.Scope -eq 'System' -or $_.AdapterName -eq $AdapterName
            })
        if ($matches.Count -eq 1) { return $matches[0] }

        if ($matches.Count -gt 1) {
            Write-Host '❌ That preset reference is ambiguous.' -ForegroundColor Red
        }
        else {
            Write-Host '❌ Preset not found for the selected adapter.' -ForegroundColor Red
        }
    } while ($true)
}

function Apply-Settings {
    [CmdletBinding()]
    param (
        [string]$Adapter,
        [string]$Preset,
        [switch]$SkipConfirmation
    )

    try {
        $json = Get-EtherShellSettings
    }
    catch {
        Write-Host "`n❌ Failed to read settings.json: $($_.Exception.Message)" -ForegroundColor Red
        Pause-EtherShell
        return
    }

    $targetAdapter = if ([string]::IsNullOrWhiteSpace($Adapter)) { $script:AdapterName } else { $Adapter }
    if ([string]::IsNullOrWhiteSpace($targetAdapter)) { return }

    if ([string]::IsNullOrWhiteSpace($Preset)) {
        $record = Select-Preset -Json $json -AdapterName $targetAdapter
        if (-not $record) { return }
    }
    else {
        $matches = @(Resolve-PresetReference -Reference $Preset -Settings $json)
        if ($matches.Count -eq 0) {
            Write-Host "`n❌ Preset '$Preset' does not exist." -ForegroundColor Red
            Pause-EtherShell
            return
        }
        if ($matches.Count -gt 1) {
            Write-Host "`n❌ Preset reference '$Preset' is ambiguous." -ForegroundColor Red
            Pause-EtherShell
            return
        }
        $record = $matches[0]
    }

    Apply-PresetRecord -Record $record -AdapterName $targetAdapter -SkipConfirmation:$SkipConfirmation
}

function Set-StaticIP {
    $targetAdapter = $script:AdapterName
    $adapter = Get-NetAdapter -Name $targetAdapter -ErrorAction SilentlyContinue

    if (-not $adapter) {
        $targetAdapter = Select-Adapter -Title "`nSelected adapter was not found. Choose an adapter:"
        if (-not $targetAdapter) { return }
        $adapter = Get-NetAdapter -Name $targetAdapter -ErrorAction SilentlyContinue
    }

    if (-not $adapter) {
        Write-Host "❌ No usable network adapter found." -ForegroundColor Red
        Pause-EtherShell
        return
    }

    if ($adapter.Status -eq 'Disabled') {
        Write-Host "⚠️ Adapter '$targetAdapter' is disabled. Enable it first." -ForegroundColor Yellow
        Pause-EtherShell
        return
    }

    $configuration = Read-StaticIPv4Configuration -AdapterName $targetAdapter
    Show-StaticConfiguration -AdapterName $targetAdapter -Configuration $configuration

    if (-not (Confirm-EtherShellAction -Prompt 'Apply this static configuration?' -DefaultYes)) {
        Write-Host "`n↩️ Operation cancelled. No network settings were changed." -ForegroundColor DarkGray
        return
    }

    try {
        Set-StaticIPv4ConfigurationInternal `
            -AdapterName $targetAdapter `
            -IPv4 $configuration.IPv4 `
            -Subnet $configuration.Subnet `
            -Prefix $configuration.Prefix `
            -Gateway $configuration.Gateway `
            -Dns $configuration.Dns | Out-Null

        $script:AdapterName = $targetAdapter
        try {
            Update-EtherShellSettings -UpdateAction {
                param($settings)
                $settings['ethershell']['defaultAdapter'] = $targetAdapter
                return $settings
            } | Out-Null
        }
        catch {
            Write-Host "⚠️ Static IPv4 was applied, but the selected adapter could not be saved: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        Write-Host "`n✅ Static configuration successfully applied." -ForegroundColor Green
        Start-Sleep -Milliseconds 900
    }
    catch {
        Write-Host "`n❌ Error while applying configuration: $($_.Exception.Message)" -ForegroundColor Red
        Pause-EtherShell
    }
}

function Read-Settings {
    try {
        $settings = Get-EtherShellSettings
        $records = @(Get-AllPresetRecords -Settings $settings | Sort-Object Id, PresetName)
    }
    catch {
        Write-Host "`n❌ Failed to read settings.json: $($_.Exception.Message)" -ForegroundColor Red
        Pause-EtherShell
        return
    }

    Write-Host "`nList of available network presets" -ForegroundColor DarkCyan

    $systemRecords = @($records | Where-Object { $_.Scope -eq 'System' })
    Write-Host "`nSystem Presets" -ForegroundColor DarkCyan
    foreach ($record in $systemRecords) {
        Write-Host "  id$($record.Id)  $($record.PresetName)" -ForegroundColor Cyan
        Write-Host '    Type    : DHCP'
        Write-Host '    DNS     : Automatic (DHCP-provided)'
        Write-Host '    Status  : Protected'
    }

    $userRecords = @($records | Where-Object { $_.Scope -eq 'Adapter' })
    if ($userRecords.Count -eq 0) {
        Write-Host "`nUser Presets" -ForegroundColor DarkCyan
        Write-Host '  (no user presets defined)' -ForegroundColor Yellow
        Pause-EtherShell
        return
    }

    foreach ($adapterName in @($userRecords.AdapterName | Sort-Object -Unique)) {
        Write-Host "`nAdapter: $adapterName" -ForegroundColor DarkCyan
        foreach ($record in @($userRecords | Where-Object { $_.AdapterName -eq $adapterName } | Sort-Object Id, PresetName)) {
            Write-Host "  id$($record.Id)  $($record.PresetName)" -ForegroundColor Cyan
            try {
                if ($record.Type -eq 'dhcp') {
                    Write-Host '    Type    : DHCP'
                    Write-Host "    DNS     : $([string]$record.Settings['dns'])"
                }
                else {
                    $configuration = Convert-PresetToConfiguration -PresetSettings $record.Settings
                    Write-Host '    Type    : Static IPv4'
                    Write-Host "    IPv4    : $($configuration.IPv4)"
                    Write-Host "    Subnet  : $($configuration.Subnet)"
                    Write-Host "    Prefix  : $($configuration.Prefix)"
                    Write-Host "    Gateway : $($configuration.Gateway)"
                    Write-Host "    DNS     : $($configuration.Dns)"
                }
            }
            catch {
                Write-Host "    INVALID : $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    Pause-EtherShell
}

function Write-Settings {
    $targetAdapter = $script:AdapterName
    if (-not (Get-NetAdapter -Name $targetAdapter -ErrorAction SilentlyContinue)) {
        Write-Host "`n❌ Selected adapter '$targetAdapter' was not found." -ForegroundColor Red
        Write-Host 'Select a valid adapter first.' -ForegroundColor Yellow
        Pause-EtherShell
        return
    }

    Write-Host "`nCreating preset for selected adapter: $targetAdapter" -ForegroundColor DarkCyan

    do {
        $presetName = (Read-Host "`nEnter Preset Name [required]").Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($presetName)) {
            Write-Host '❌ Preset name must not be empty.' -ForegroundColor Red
            continue
        }
        if (Test-ReservedPresetName -Name $presetName) {
            Write-Host "❌ Preset name '$presetName' is reserved by EtherShell." -ForegroundColor Red
            continue
        }
        break
    } while ($true)

    try {
        $settings = Get-EtherShellSettings -CreateIfMissing
        $nameMatches = @(Get-PresetNameMatches -Name $presetName -Settings $settings)
    }
    catch {
        Write-Host "`n❌ Cannot safely read settings.json: $($_.Exception.Message)" -ForegroundColor Red
        Pause-EtherShell
        return
    }

    if ($nameMatches.Count -gt 1) {
        Write-Host "`n❌ Multiple existing presets resolve to '$presetName'. Resolve them before continuing." -ForegroundColor Red
        Pause-EtherShell
        return
    }

    $nameRecordToReplace = $null
    if ($nameMatches.Count -eq 1) {
        $existing = $nameMatches[0]
        if ($existing.Scope -eq 'System' -or $existing.Protected) {
            Write-Host "`n❌ Preset '$presetName' is protected and cannot be overwritten." -ForegroundColor Red
            Pause-EtherShell
            return
        }
        if ($existing.AdapterName -ne $targetAdapter) {
            Write-Host "`n❌ Preset name '$presetName' is already used by adapter '$($existing.AdapterName)'." -ForegroundColor Red
            Write-Host 'Preset names must be globally unique across all adapters.' -ForegroundColor Yellow
            Pause-EtherShell
            return
        }
        Write-Host "Existing preset: id$($existing.Id) '$($existing.PresetName)'" -ForegroundColor DarkGray
        if (-not (Confirm-EtherShellAction -Prompt "Preset '$($existing.PresetName)' already exists. Overwrite it?")) {
            Write-Host '`n↩️ Operation cancelled.' -ForegroundColor DarkGray
            Pause-EtherShell
            return
        }
        $nameRecordToReplace = $existing
    }

    # ID selection. id0 is permanently reserved for dhcp-auto.
    $idRecordToReplace = $null
    do {
        $settings = Get-EtherShellSettings -CreateIfMissing
        $automaticId = Get-NextFreePresetId -Settings $settings
        Write-Host "`nPreset ID:" -ForegroundColor DarkCyan
        Write-Host " - Press ENTER to automatically use the next free ID: id$automaticId" -ForegroundColor DarkGray
        Write-Host ' - Or enter a number >= 1 to choose the ID yourself' -ForegroundColor DarkGray
        $idInput = (Read-Host 'ID number').Trim()

        if ([string]::IsNullOrWhiteSpace($idInput)) {
            $chosenId = $automaticId
            $idRecordToReplace = $null
            Write-Host "✅ Using id$chosenId." -ForegroundColor Green
            break
        }

        if ($idInput -notmatch '^\d+$') {
            Write-Host '❌ Enter only the numeric ID (for example: 3 for id3), or press ENTER.' -ForegroundColor Red
            continue
        }

        $chosenId = [int]$idInput
        if ($chosenId -eq 0) {
            Write-Host "❌ id0 is permanently reserved for the protected preset 'dhcp-auto'." -ForegroundColor Red
            continue
        }
        if ($chosenId -lt 1) {
            Write-Host '❌ User preset IDs must be 1 or higher.' -ForegroundColor Red
            continue
        }

        $idMatches = @(Get-PresetIdMatches -Id $chosenId -Settings $settings)
        if ($idMatches.Count -gt 1) {
            Write-Host "❌ id$chosenId is duplicated in settings.json. Resolve the duplicate first." -ForegroundColor Red
            continue
        }

        if ($idMatches.Count -eq 0) {
            $idRecordToReplace = $null
            break
        }

        $occupied = $idMatches[0]
        if ($occupied.Scope -eq 'System' -or $occupied.Protected) {
            Write-Host "❌ id$chosenId belongs to protected preset '$($occupied.PresetName)' and cannot be overwritten." -ForegroundColor Red
            continue
        }

        $adapterText = if ([string]::IsNullOrWhiteSpace($occupied.AdapterName)) { 'system' } else { $occupied.AdapterName }
        Write-Host "⚠️ id$chosenId is already used by preset '$($occupied.PresetName)' on '$adapterText'." -ForegroundColor Yellow
        if (Confirm-EtherShellAction -Prompt "Already exists - overwrite '$($occupied.PresetName)'?") {
            $idRecordToReplace = $occupied
            break
        }

        Write-Host '↩️ Choose another ID.' -ForegroundColor DarkGray
    } while ($true)

    Write-Host "`nPreset type:" -ForegroundColor DarkCyan
    Write-Host '[1] Static IPv4'
    Write-Host '[2] DHCP with custom DNS'
    Write-Host '[Q] Cancel'
    do {
        $typeChoice = (Read-Host 'Type').Trim().ToLowerInvariant()
        switch ($typeChoice) {
            '1' { $presetType = 'static'; break }
            '2' { $presetType = 'dhcp'; break }
            'q' { Write-Host '↩️ Preset creation cancelled.' -ForegroundColor DarkGray; return }
            default { Write-Host '❌ Choose 1, 2, or Q.' -ForegroundColor Red }
        }
    } while (-not $presetType)

    if ($presetType -eq 'static') {
        $configuration = Read-StaticIPv4Configuration -AdapterName $targetAdapter
        $newPresetData = @{
            id      = $chosenId
            type    = 'static'
            ipv4    = $configuration.IPv4
            subnet  = $configuration.Subnet
            prefix  = $configuration.Prefix
            gateway = $configuration.Gateway
            dns     = $configuration.Dns
        }
    }
    else {
        do {
            $customDns = (Read-Host 'Enter custom IPv4 DNS server [required]').Trim()
            $validDns = Test-IPv4Address -Address $customDns
            if (-not $validDns) { Write-Host '❌ Invalid IPv4 DNS server.' -ForegroundColor Red }
        } until ($validDns)

        $newPresetData = @{
            id      = $chosenId
            type    = 'dhcp'
            dnsMode = 'custom'
            dns     = $customDns
        }
    }

    try {
        Update-EtherShellSettings -UpdateAction {
            param($latest)

            $latest = Initialize-SettingsStructure -Settings $latest
            $currentNameMatches = @(Get-PresetNameMatches -Name $presetName -Settings $latest)
            $currentIdMatches = @(Get-PresetIdMatches -Id $chosenId -Settings $latest)

            # Never permit any operation to overwrite the protected system preset.
            if (@($currentNameMatches | Where-Object { $_.Protected -or $_.Scope -eq 'System' }).Count -gt 0 -or
                @($currentIdMatches | Where-Object { $_.Protected -or $_.Scope -eq 'System' }).Count -gt 0) {
                throw "Protected preset 'dhcp-auto' (id0) cannot be overwritten."
            }

            # If the confirmed targets still exist, remove them. If a new conflict
            # appeared after confirmation, abort instead of deleting unexpected data.
            foreach ($record in @($currentNameMatches)) {
                $approved = $nameRecordToReplace -and
                    $record.AdapterName -eq $nameRecordToReplace.AdapterName -and
                    $record.PresetName -eq $nameRecordToReplace.PresetName
                if (-not $approved) {
                    throw "Preset name '$presetName' changed while you were editing. Retry the operation."
                }
                Remove-PresetRecordFromSettings -Settings $latest -Record $record
            }

            # Re-read after potential name removal.
            $currentIdMatches = @(Get-PresetIdMatches -Id $chosenId -Settings $latest)
            foreach ($record in @($currentIdMatches)) {
                $approved = $idRecordToReplace -and
                    $record.AdapterName -eq $idRecordToReplace.AdapterName -and
                    $record.PresetName -eq $idRecordToReplace.PresetName
                if (-not $approved) {
                    throw "id$chosenId changed while you were editing. Retry the operation."
                }
                Remove-PresetRecordFromSettings -Settings $latest -Record $record
            }

            $adapters = $latest['ethershell']['network']['adapter']
            if (-not $adapters.Contains($targetAdapter) -or
                -not ($adapters[$targetAdapter] -is [System.Collections.IDictionary])) {
                $adapters[$targetAdapter] = @{}
            }

            $adapters[$targetAdapter][$presetName] = $newPresetData
            return $latest
        } | Out-Null

        Write-Host "`n✅ Preset '$presetName' (id$chosenId) for '$targetAdapter' saved successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "`n❌ Failed to save preset: $($_.Exception.Message)" -ForegroundColor Red
        Pause-EtherShell
        return
    }

    if (Confirm-EtherShellAction -Prompt 'Apply this preset now?') {
        Apply-Settings -Adapter $targetAdapter -Preset $presetName -SkipConfirmation
    }
    else {
        Write-Host '`nℹ️ Preset saved only. You can apply it later.' -ForegroundColor DarkGray
        Pause-EtherShell
    }
}

function Delete-Presets {
    try {
        $settings = Get-EtherShellSettings
        $records = @(Get-AllPresetRecords -Settings $settings | Where-Object {
                $_.Scope -eq 'System' -or $_.AdapterName -eq $script:AdapterName
            } | Sort-Object Id, PresetName)
    }
    catch {
        Write-Host "`n❌ Failed to read settings.json: $($_.Exception.Message)" -ForegroundColor Red
        Pause-EtherShell
        return
    }

    Write-Host "`nPresets visible for '$script:AdapterName':" -ForegroundColor DarkCyan
    for ($i = 0; $i -lt $records.Count; $i++) {
        $record = $records[$i]
        $protectedText = if ($record.Protected) { ' [protected]' } else { '' }
        Write-Host "[$($i + 1)] id$($record.Id)  $($record.PresetName)$protectedText"
    }

    do {
        $selection = (Read-Host "`nSelect number, preset name, ID (e.g. id1), or Q to cancel").Trim()
        if ($selection -match '^[Qq]$') { return }

        $record = $null
        if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $records.Count) {
            $record = $records[[int]$selection - 1]
        }
        else {
            $matches = @(Resolve-PresetReference -Reference $selection -Settings $settings | Where-Object {
                    $_.Scope -eq 'System' -or $_.AdapterName -eq $script:AdapterName
                })
            if ($matches.Count -eq 1) { $record = $matches[0] }
        }

        if (-not $record) {
            Write-Host '❌ Preset not found.' -ForegroundColor Red
            continue
        }

        if ($record.Protected -or $record.Scope -eq 'System' -or $record.Id -eq 0 -or
            $record.PresetName.Trim().ToLowerInvariant() -eq 'dhcp-auto') {
            Write-Host "❌ Preset 'dhcp-auto' (id0) is protected and cannot be deleted." -ForegroundColor Red
            Pause-EtherShell
            return
        }
        break
    } while ($true)

    if (-not (Confirm-EtherShellAction -Prompt "Delete preset '$($record.PresetName)' (id$($record.Id)) from '$($record.AdapterName)'?")) {
        Write-Host '`n↩️ Deletion cancelled.' -ForegroundColor DarkGray
        Pause-EtherShell
        return
    }

    try {
        Update-EtherShellSettings -UpdateAction {
            param($latest)
            $matches = @(Get-PresetIdMatches -Id $record.Id -Settings $latest | Where-Object {
                    $_.AdapterName -eq $record.AdapterName -and $_.PresetName -eq $record.PresetName
                })
            if ($matches.Count -ne 1) {
                throw 'Preset changed before it could be deleted. Retry the operation.'
            }
            Remove-PresetRecordFromSettings -Settings $latest -Record $matches[0]
            return $latest
        } | Out-Null
        Write-Host "`n✅ Preset '$($record.PresetName)' (id$($record.Id)) deleted successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "`n❌ Failed to delete preset: $($_.Exception.Message)" -ForegroundColor Red
    }

    Pause-EtherShell
}

function Delete-PersistentSettingsFile {
    Write-Host "`n⚠️ This resets EtherShell settings to defaults." -ForegroundColor Red
    Write-Host "   All user presets and preferences will be removed." -ForegroundColor Yellow
    Write-Host "   Protected preset 'dhcp-auto' (id0) will remain." -ForegroundColor DarkGray

    if (-not (Confirm-EtherShellAction -Prompt 'Reset EtherShell settings to defaults?')) {
        Write-Host '`n↩️ Reset cancelled.' -ForegroundColor DarkGray
        Pause-EtherShell
        return
    }

    try {
        Invoke-WithSettingsLock -ScriptBlock {
            Write-EtherShellSettingsUnlocked -Settings (New-DefaultEtherShellSettings)
        } | Out-Null
        Load-DefaultAdapterFromSettings
        Write-Host "`n✅ EtherShell settings reset to defaults. 'dhcp-auto' (id0) is available." -ForegroundColor Green
    }
    catch {
        Write-Host "`n❌ Failed to reset settings: $($_.Exception.Message)" -ForegroundColor Red
    }

    Pause-EtherShell
}

function Delete-AllPresets {
    try {
        $settings = Get-EtherShellSettings -CreateIfMissing
        $userPresets = @(Get-AllPresetRecords -Settings $settings | Where-Object { $_.Scope -eq 'Adapter' })
    }
    catch {
        Write-Host "`n❌ Failed to read settings.json: $($_.Exception.Message)" -ForegroundColor Red
        Pause-EtherShell
        return
    }

    if ($userPresets.Count -eq 0) {
        Write-Host "`nℹ️ No user presets are stored. Protected preset 'dhcp-auto' (id0) remains available." -ForegroundColor DarkGray
        Pause-EtherShell
        return
    }

    Write-Host "`n⚠️ This will delete all $($userPresets.Count) user preset(s)." -ForegroundColor Yellow
    Write-Host "   Protected preset 'dhcp-auto' (id0) will be kept." -ForegroundColor DarkGray
    if (-not (Confirm-EtherShellAction -Prompt 'Delete all user presets?')) {
        Write-Host '`n↩️ Deletion cancelled.' -ForegroundColor DarkGray
        Pause-EtherShell
        return
    }

    try {
        Update-EtherShellSettings -UpdateAction {
            param($latest)
            $latest['ethershell']['network']['adapter'] = @{}
            return $latest
        } | Out-Null
        Write-Host "`n✅ All user presets were deleted. 'dhcp-auto' (id0) was preserved." -ForegroundColor Green
    }
    catch {
        Write-Host "`n❌ Failed to delete presets: $($_.Exception.Message)" -ForegroundColor Red
    }

    Pause-EtherShell
}

function Show-PresetsQuickView {
    Clear-Host
    Read-Settings
}


function PersistentSettings {
    do {
        Show-SectionHeader -Title 'Network Presets' -Subtitle "Selected adapter: $script:AdapterName"
        Write-Host '┌' -ForegroundColor $script:BannerColor
        foreach ($entry in @(
                '[1] List Presets',
                '[2] Create Preset',
                '[3] Apply Preset',
                '[4] Delete Preset',
                '[5] Delete All Presets'
            )) {
            Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
            Write-Host " $entry"
        }
        Write-Host '├──────────────────────────────────────────────' -ForegroundColor $script:BannerColor
        Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
        Write-Host ' [Q] Back'
        Write-Host '└──────────────────────────────────────────────' -ForegroundColor $script:BannerColor

        $choice = (Read-Host "`nGo").Trim().ToLowerInvariant()
        switch ($choice) {
            '1' { Read-Settings }
            '2' { Write-Settings }
            '3' { Apply-Settings -Adapter $script:AdapterName }
            '4' { Delete-Presets }
            '5' { Delete-AllPresets }
            'q' { }
            default {
                Write-Host "`n❌ Invalid input. Please make a choice." -ForegroundColor Red
                Start-Sleep -Milliseconds 700
            }
        }
    } while ($choice -ne 'q')
}

# ────────────────────────────────────────────────────────
# DHCP
# ────────────────────────────────────────────────────────
function Read-DhcpDnsChoice {
    param (
        [string]$ExistingDns
    )

    Write-Host
    Write-Host 'Enter DNS address (optional):' -ForegroundColor DarkCyan
    if (-not [string]::IsNullOrWhiteSpace($ExistingDns)) {
        Write-Host " - Press ENTER to keep existing ($ExistingDns)" -ForegroundColor DarkGray
        Write-Host ' - Press DELETE to remove it and use DHCP DNS' -ForegroundColor DarkGray
    }
    else {
        Write-Host ' - Press ENTER to use DHCP-provided DNS' -ForegroundColor DarkGray
    }
    Write-Host ' - Type a new IPv4 DNS server and press ENTER' -ForegroundColor DarkGray
    Write-Host ' - Press ESC to cancel' -ForegroundColor DarkGray

    $dnsInput = ''

    while ($true) {
        $key = [Console]::ReadKey($true)

        switch ($key.Key) {
            'Escape' {
                Write-Host "`n↩️ DNS entry cancelled." -ForegroundColor DarkGray
                return [pscustomobject]@{ Cancelled = $true; Dns = $null; RemoveSaved = $false }
            }
            'Delete' {
                Write-Host "`n🧹 Custom DHCP DNS will be removed." -ForegroundColor Yellow
                return [pscustomobject]@{ Cancelled = $false; Dns = $null; RemoveSaved = $true }
            }
            'Backspace' {
                if ($dnsInput.Length -gt 0) {
                    $dnsInput = $dnsInput.Substring(0, $dnsInput.Length - 1)
                    Write-Host "`b `b" -NoNewline
                }
            }
            'Enter' {
                if ([string]::IsNullOrWhiteSpace($dnsInput)) {
                    if (-not [string]::IsNullOrWhiteSpace($ExistingDns)) {
                        Write-Host "`n✅ Keeping existing DNS: $ExistingDns" -ForegroundColor Green
                        return [pscustomobject]@{ Cancelled = $false; Dns = $ExistingDns; RemoveSaved = $false }
                    }

                    Write-Host "`nℹ️ DHCP-provided DNS will be used." -ForegroundColor DarkGray
                    return [pscustomobject]@{ Cancelled = $false; Dns = $null; RemoveSaved = $true }
                }

                if (Test-IPv4Address -Address $dnsInput) {
                    Write-Host "`n✅ Using DNS: $dnsInput" -ForegroundColor Green
                    return [pscustomobject]@{ Cancelled = $false; Dns = $dnsInput; RemoveSaved = $false }
                }

                Write-Host "`n❌ DNS server must be a valid IPv4 address. Try again." -ForegroundColor Red
                $dnsInput = ''
            }
            default {
                if (-not [char]::IsControl($key.KeyChar)) {
                    $dnsInput += $key.KeyChar
                    Write-Host -NoNewline $key.KeyChar
                }
            }
        }
    }
}

function Wait-ForDhcpIPv4 {
    param (
        [Parameter(Mandatory)] [string]$AdapterName,
        [int]$TimeoutSeconds = 10
    )

    Write-Host "`n⏳ Waiting up to $TimeoutSeconds seconds for a DHCP IPv4 address (press Q to stop waiting)"

    for ($i = 1; $i -le $TimeoutSeconds; $i++) {
        try {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq 'Q') {
                    Write-Host "`n↩️ DHCP wait cancelled by user." -ForegroundColor Yellow
                    return [pscustomobject]@{ IP = $null; Cancelled = $true }
                }
            }
        }
        catch {}

        $ipConfig = Get-NetIPConfiguration -InterfaceAlias $AdapterName -ErrorAction SilentlyContinue
        $ip = @($ipConfig.IPv4Address.IPAddress | Where-Object { $_ -and $_ -notlike '169.254.*' }) | Select-Object -First 1
        if ($ip) {
            Write-Host "`n✅ IPv4 address obtained: $ip" -ForegroundColor Green
            return [pscustomobject]@{ IP = $ip; Cancelled = $false }
        }

        Start-Sleep -Seconds 1
        Write-Host '.' -NoNewline
    }

    Write-Host "`n⚠️ Timeout reached. No valid DHCP IPv4 address assigned." -ForegroundColor Yellow
    return [pscustomobject]@{ IP = $null; Cancelled = $false }
}

function Set-DHCP {
    $targetAdapter = $script:AdapterName
    $adapter = Get-NetAdapter -Name $targetAdapter -ErrorAction SilentlyContinue

    if (-not $adapter) {
        $targetAdapter = Select-Adapter -Title "`nSelected adapter was not found. Choose an adapter for DHCP:"
        if (-not $targetAdapter) { return }
        $adapter = Get-NetAdapter -Name $targetAdapter -ErrorAction SilentlyContinue
    }

    if (-not $adapter) {
        Write-Host "⚠️ No usable network adapter found." -ForegroundColor Red
        return
    }

    if ($adapter.Status -eq 'Disabled') {
        Write-Host "⚠️ Adapter '$targetAdapter' is disabled. Enable it first." -ForegroundColor Yellow
        Start-Sleep -Milliseconds 1000
        return
    }

    $existingDns = ''
    $settingsReadable = $true
    try {
        $settings = Get-EtherShellSettings -CreateIfMissing
        $existingDns = [string]$settings['ethershell']['network']['dhcpDns']
    }
    catch {
        $settingsReadable = $false
        Write-Host "⚠️ settings.json could not be read safely. DHCP can still be applied, but DNS preference will not be saved." -ForegroundColor Yellow
    }

    $dnsChoice = Read-DhcpDnsChoice -ExistingDns $existingDns
    if ($dnsChoice.Cancelled) {
        Write-Host 'No network settings were changed.' -ForegroundColor DarkGray
        return
    }

    Write-Host "`n⚙️ Applying DHCP mode for '$targetAdapter'..." -ForegroundColor DarkCyan
    $snapshot = $null

    try {
        $snapshot = Get-IPv4ConfigurationSnapshot -AdapterName $targetAdapter

        Clear-IPv4ConfigurationInternal -AdapterName $targetAdapter -DisableDhcp -ResetDns
        Set-NetIPInterface -InterfaceAlias $targetAdapter -AddressFamily IPv4 -Dhcp Enabled -ErrorAction Stop

        if ($dnsChoice.Dns) {
            Set-DnsClientServerAddress -InterfaceAlias $targetAdapter -ServerAddresses $dnsChoice.Dns -ErrorAction Stop
        }
        else {
            Set-DnsClientServerAddress -InterfaceAlias $targetAdapter -ResetServerAddresses -ErrorAction Stop
        }

        & ipconfig.exe /renew "$targetAdapter" | Out-Null
        $script:NetworkReconfigured = $true
    }
    catch {
        $message = $_.Exception.Message
        Write-Host "❌ Error while applying DHCP configuration: $message" -ForegroundColor Red
        if ($snapshot) {
            Write-Host '⚠️ Attempting rollback...' -ForegroundColor Yellow
            if (Restore-IPv4ConfigurationSnapshot -AdapterName $targetAdapter -Snapshot $snapshot) {
                Write-Host '✅ Previous IPv4 configuration restored.' -ForegroundColor Green
            }
        }
        return
    }

    if ($settingsReadable) {
        try {
            Update-EtherShellSettings -UpdateAction {
                param($latest)
                $latest['ethershell']['network']['dhcpDns'] = if ($dnsChoice.Dns) { $dnsChoice.Dns } else { '' }
                $latest['ethershell']['defaultAdapter'] = $targetAdapter
                return $latest
            } | Out-Null
        }
        catch {
            Write-Host "⚠️ DHCP was applied, but settings.json could not be updated: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    $script:AdapterName = $targetAdapter
    $result = Wait-ForDhcpIPv4 -AdapterName $targetAdapter -TimeoutSeconds 10
    if ($result.Cancelled) { return }

    if (-not $result.IP) {
        Write-Host "`n🔁 Retrying DHCP renewal..." -ForegroundColor DarkGray
        & ipconfig.exe /release "$targetAdapter" | Out-Null
        Start-Sleep -Seconds 2
        & ipconfig.exe /renew "$targetAdapter" | Out-Null
        $result = Wait-ForDhcpIPv4 -AdapterName $targetAdapter -TimeoutSeconds 10
        if (-not $result.Cancelled -and -not $result.IP) {
            Write-Host '❌ Retry failed: No valid IPv4 address assigned.' -ForegroundColor Red
        }
    }

    Start-Sleep -Milliseconds 800
}

# ────────────────────────────────────────────────────────
# Clear IP configuration
# ────────────────────────────────────────────────────────
function Clear-IPConfig {
    [CmdletBinding()]
    param (
        [string]$AdapterName = $script:AdapterName
    )

    if (-not (Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue)) {
        Write-Host "❌ Adapter '$AdapterName' was not found." -ForegroundColor Red
        return
    }

    Write-Host "`n⚠️ This will disable DHCP and remove IPv4 addresses, the IPv4 default route, and custom DNS from '$AdapterName'." -ForegroundColor Yellow
    if (-not (Confirm-EtherShellAction -Prompt 'Continue?')) {
        Write-Host '↩️ Operation cancelled.' -ForegroundColor DarkGray
        return
    }

    $snapshot = $null
    try {
        $snapshot = Get-IPv4ConfigurationSnapshot -AdapterName $AdapterName
        Clear-IPv4ConfigurationInternal -AdapterName $AdapterName -DisableDhcp -ResetDns
        $script:NetworkReconfigured = $true
        Write-Host "✅ Cleared IPv4 settings for '$AdapterName'." -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to clear IPv4 settings: $($_.Exception.Message)" -ForegroundColor Red
        if ($snapshot) {
            Write-Host '⚠️ Attempting rollback...' -ForegroundColor Yellow
            if (Restore-IPv4ConfigurationSnapshot -AdapterName $AdapterName -Snapshot $snapshot) {
                Write-Host '✅ Previous IPv4 configuration restored.' -ForegroundColor Green
            }
        }
    }

    Start-Sleep -Milliseconds 900
}

# ────────────────────────────────────────────────────────
# Toggle adapter / Wi-Fi reconnect
# ────────────────────────────────────────────────────────
function Test-LocationPermissionRegistry {
    $base = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
    $nonPackaged = Join-Path $base 'NonPackaged'
    $desktop = Join-Path $base 'Windows.System.Launcher'

    foreach ($path in @($base, $nonPackaged, $desktop)) {
        try {
            $value = Get-ItemPropertyValue -Path $path -Name 'Value' -ErrorAction Stop
            if ($value -ne 'Allow') { return $false }
        }
        catch {
            # Missing per-app keys do not necessarily mean location is blocked.
            if ($path -eq $base) { return $false }
        }
    }

    return $true
}

function Convert-WiFiAuthenticationDisplay {
    [CmdletBinding()]
    param (
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Authentication
    )

    if ([string]::IsNullOrWhiteSpace($Authentication)) {
        return 'Unknown'
    }

    $value = $Authentication.Trim()

    switch -Regex ($value) {
        '^(?i)open$'             { return 'Open' }
        '^(?i)shared$'           { return 'WEP-Shared' }
        '^(?i)WPAPSK$'           { return 'WPA-Personal' }
        '^(?i)WPA2PSK$'          { return 'WPA2-Personal' }
        '^(?i)WPA3SAE$'          { return 'WPA3-Personal' }
        '^(?i)WPA$'              { return 'WPA-Enterprise' }
        '^(?i)WPA2$'             { return 'WPA2-Enterprise' }
        '^(?i)WPA3$'             { return 'WPA3-Enterprise' }
        '^(?i)OWE$'              { return 'OWE' }
        '^(?i)WPA-Personal$'     { return 'WPA-Personal' }
        '^(?i)WPA2-Personal$'    { return 'WPA2-Personal' }
        '^(?i)WPA3-Personal$'    { return 'WPA3-Personal' }
        '^(?i)WPA-Enterprise$'   { return 'WPA-Enterprise' }
        '^(?i)WPA2-Enterprise$'  { return 'WPA2-Enterprise' }
        '^(?i)WPA3-Enterprise$'  { return 'WPA3-Enterprise' }
        default                  { return 'Unknown' }
    }
}

function Convert-WiFiEncryptionDisplay {
    [CmdletBinding()]
    param (
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Encryption
    )

    if ([string]::IsNullOrWhiteSpace($Encryption)) {
        return 'Unknown'
    }

    $value = $Encryption.Trim()

    switch -Regex ($value) {
        '^(?i)none$'       { return 'None' }
        '^(?i)AES$'        { return 'AES/CCMP' }
        '^(?i)CCMP$'       { return 'AES/CCMP' }
        '^(?i)CCMP-256$'   { return 'CCMP-256' }
        '^(?i)GCMP$'       { return 'GCMP' }
        '^(?i)GCMP-256$'   { return 'GCMP-256' }
        '^(?i)TKIP$'       { return 'TKIP' }
        '^(?i)WEP$'        { return 'WEP' }
        default            { return 'Unknown' }
    }
}

function Get-WiFiSecurityDisplay {
    [CmdletBinding()]
    param (
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Authentication,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Encryption
    )

    $authDisplay = Convert-WiFiAuthenticationDisplay -Authentication $Authentication
    $encryptionDisplay = Convert-WiFiEncryptionDisplay -Encryption $Encryption

    if ($authDisplay -eq 'Open' -and $encryptionDisplay -in @('None', 'Unknown')) {
        return 'Open'
    }

    if ($authDisplay -eq 'Unknown' -and $encryptionDisplay -eq 'Unknown') {
        return 'Unknown'
    }

    if ($encryptionDisplay -eq 'Unknown') {
        return $authDisplay
    }

    if ($authDisplay -eq 'Unknown') {
        return $encryptionDisplay
    }

    return "$authDisplay / $encryptionDisplay"
}

function Write-WiFiNetworkTable {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object[]]$Networks
    )

    $items = @($Networks)
    if ($items.Count -eq 0) {
        return
    }

    # Designed for EtherShell's 100-column terminal layout.
    $ssidWidth = 44
    $securityWidth = 36

    Write-Host
    Write-Host ("{0,-6} {1,-$ssidWidth} {2,-$securityWidth}" -f 'No.', 'SSID', 'Security') -ForegroundColor DarkCyan
    Write-Host ("{0,-6} {1,-$ssidWidth} {2,-$securityWidth}" -f ('-' * 4), ('-' * $ssidWidth), ('-' * $securityWidth)) -ForegroundColor DarkGray

    for ($i = 0; $i -lt $items.Count; $i++) {
        $ssid = [string]$items[$i].SSID
        $security = [string]$items[$i].Security

        if ([string]::IsNullOrWhiteSpace($security)) {
            $security = 'Unknown'
        }

        if ($ssid.Length -gt $ssidWidth) {
            $ssid = $ssid.Substring(0, $ssidWidth - 3) + '...'
        }

        if ($security.Length -gt $securityWidth) {
            $security = $security.Substring(0, $securityWidth - 3) + '...'
        }

        Write-Host ("{0,-6} {1,-$ssidWidth} {2,-$securityWidth}" -f ("[$($i + 1)]"), $ssid, $security)
    }
}

function Get-SavedWiFiProfileDetails {
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('EtherShell_WlanProfiles_' + [guid]::NewGuid().ToString('N'))

    try {
        New-Item -ItemType Directory -Path $tempDir -Force -ErrorAction Stop | Out-Null
        & netsh.exe wlan export profile "folder=$tempDir" | Out-Null

        $profiles = foreach ($file in @(Get-ChildItem -LiteralPath $tempDir -Filter '*.xml' -File -ErrorAction SilentlyContinue)) {
            try {
                [xml]$profileXml = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop

                $nameNode = $profileXml.SelectSingleNode("/*[local-name()='WLANProfile']/*[local-name()='name']")
                if (-not $nameNode -or [string]::IsNullOrWhiteSpace($nameNode.InnerText)) {
                    continue
                }

                $authenticationNode = $profileXml.SelectSingleNode("//*[local-name()='authEncryption']/*[local-name()='authentication']")
                $encryptionNode = $profileXml.SelectSingleNode("//*[local-name()='authEncryption']/*[local-name()='encryption']")
                $connectionModeNode = $profileXml.SelectSingleNode("/*[local-name()='WLANProfile']/*[local-name()='connectionMode']")

                $authentication = if ($authenticationNode) { [string]$authenticationNode.InnerText } else { '' }
                $encryption = if ($encryptionNode) { [string]$encryptionNode.InnerText } else { '' }
                $connectionMode = if ($connectionModeNode) { [string]$connectionModeNode.InnerText } else { '' }

                [pscustomobject]@{
                    SSID           = $nameNode.InnerText.Trim()
                    Authentication = $authentication
                    Encryption     = $encryption
                    Security       = Get-WiFiSecurityDisplay -Authentication $authentication -Encryption $encryption
                    AutoConnect    = ($connectionMode -eq 'auto')
                }
            }
            catch {
                # Ignore one malformed/unreadable exported profile and continue.
            }
        }

        # A profile can be exported more than once when it exists on multiple
        # WLAN interfaces. Show one row per unique SSID.
        return @(
            $profiles |
                Sort-Object SSID |
                Group-Object SSID |
                ForEach-Object { $_.Group | Select-Object -First 1 }
        )
    }
    finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-SavedWiFiProfiles {
    return @(
        Get-SavedWiFiProfileDetails |
            ForEach-Object { $_.SSID } |
            Sort-Object -Unique
    )
}


function Test-WiFiLocationPermissionMessage {
    [CmdletBinding()]
    param (
        [AllowNull()]
        [object[]]$Output
    )

    $message = (@($Output) | ForEach-Object { [string]$_ }) -join "`n"
    if ([string]::IsNullOrWhiteSpace($message)) {
        return $false
    }

    # Only react to explicit location/privacy wording. A generic WLAN error
    # must not automatically be treated as a Location Services problem.
    return ($message -match '(?i)\blocation\b|location services|location permission') -or (-not (Test-LocationPermissionRegistry))
}

function Get-VisibleWiFiNetworks {
    [CmdletBinding()]
    param (
        [string]$InterfaceName
    )

    $netshArgs = @('wlan', 'show', 'networks', 'mode=bssid')
    if (-not [string]::IsNullOrWhiteSpace($InterfaceName)) {
        $netshArgs += "interface=$InterfaceName"
    }

    $output = @(& netsh.exe @netshArgs 2>&1)
    $exitCode = $LASTEXITCODE

    $details = @()
    $current = $null

    foreach ($line in $output) {
        $lineText = [string]$line

        if ($lineText -match '^\s*SSID\s+\d+\s*:\s*(.*)$') {
            if ($current) {
                $current.Security = Get-WiFiSecurityDisplay `
                    -Authentication $current.Authentication `
                    -Encryption $current.Encryption
                $details += [pscustomobject]$current
            }

            $ssid = $Matches[1].Trim()
            $current = [ordered]@{
                SSID           = $ssid
                Authentication = ''
                Encryption     = ''
                Security       = 'Unknown'
            }
            continue
        }

        if (-not $current) {
            continue
        }

        if ($lineText -match '^\s*Authentication\s*:\s*(.+?)\s*$') {
            $current.Authentication = $Matches[2].Trim()
            continue
        }

        if ($lineText -match '^\s*Encryption\s*:\s*(.+?)\s*$') {
            $current.Encryption = $Matches[2].Trim()
            continue
        }

        # Fallback for other Windows UI languages: security values themselves
        # are much less localized than the field labels.
        if ([string]::IsNullOrWhiteSpace([string]$current.Authentication) -and
            $lineText -match ':\s*((?:WPA3|WPA2|WPA|OWE|Open)[^:]*)$') {
            $candidate = $Matches[1].Trim()
            if ($candidate -match '(?i)WPA|OWE|Open') {
                $current.Authentication = $candidate
                continue
            }
        }

        if ([string]::IsNullOrWhiteSpace([string]$current.Encryption) -and
            $lineText -match ':\s*(CCMP-256|CCMP|GCMP-256|GCMP|AES|TKIP|WEP|None)\s*$') {
            $current.Encryption = $Matches[1].Trim()
        }
    }

    if ($current) {
        $current.Security = Get-WiFiSecurityDisplay `
            -Authentication $current.Authentication `
            -Encryption $current.Encryption
        $details += [pscustomobject]$current
    }

    $details = @(
        $details |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.SSID) } |
            Sort-Object SSID |
            Group-Object SSID |
            ForEach-Object {
                # Prefer the row containing the most complete security data.
                $_.Group |
                    Sort-Object @{
                        Expression = {
                            ([int](-not [string]::IsNullOrWhiteSpace([string]$_.Authentication))) +
                            ([int](-not [string]::IsNullOrWhiteSpace([string]$_.Encryption)))
                        }
                        Descending = $true
                    } |
                    Select-Object -First 1
            }
    )

    return [pscustomobject]@{
        Success                    = ($exitCode -eq 0)
        ExitCode                   = $exitCode
        Networks                   = @($details | ForEach-Object { $_.SSID })
        NetworkDetails             = @($details)
        Output                     = @($output)
        LocationPermissionRequired = (Test-WiFiLocationPermissionMessage -Output $output)
    }
}


function Get-WiFiConnectionState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$InterfaceName
    )

    $output = @(& netsh.exe wlan show interfaces 2>&1)
    $exitCode = $LASTEXITCODE
    $locationBlocked = Test-WiFiLocationPermissionMessage -Output $output

    if ($exitCode -ne 0) {
        return [pscustomobject]@{
            VerificationAvailable      = $false
            LocationPermissionRequired = $locationBlocked
            SSID                       = $null
            Output                     = @($output)
            ExitCode                   = $exitCode
        }
    }

    $inTargetInterface = $false

    foreach ($line in $output) {
        $lineText = [string]$line

        # Detect the target interface by matching the value side of any field.
        # This avoids depending on localized field labels.
        if ($lineText -match '^\s*[^:]+\s*:\s*(.+?)\s*$') {
            $fieldValue = $Matches[1].Trim()
            if ($fieldValue -eq $InterfaceName) {
                $inTargetInterface = $true
                continue
            }
        }

        if ($inTargetInterface -and $lineText -match '^\s*SSID\s*:\s*(.+)$') {
            return [pscustomobject]@{
                VerificationAvailable      = $true
                LocationPermissionRequired = $false
                SSID                       = $Matches[1].Trim()
                Output                     = @($output)
                ExitCode                   = $exitCode
            }
        }

        if ($inTargetInterface -and [string]::IsNullOrWhiteSpace($lineText)) {
            $inTargetInterface = $false
        }
    }

    return [pscustomobject]@{
        VerificationAvailable      = $true
        LocationPermissionRequired = $false
        SSID                       = $null
        Output                     = @($output)
        ExitCode                   = $exitCode
    }
}


function Get-CurrentWiFiSSID {
    param (
        [Parameter(Mandatory)]
        [string]$InterfaceName
    )

    $state = Get-WiFiConnectionState -InterfaceName $InterfaceName
    if (-not $state.VerificationAvailable) {
        return $null
    }

    return $state.SSID
}


function Toggle-NetworkInterface {
    [CmdletBinding()]
    param (
        [string]$InterfaceName = $script:AdapterName
    )

    $adapter = Get-NetAdapter -Name $InterfaceName -ErrorAction SilentlyContinue
    if (-not $adapter) {
        Write-Host "❌ Interface '$InterfaceName' not found." -ForegroundColor Red
        return
    }

    if ($adapter.Status -in @('Up', 'Disconnected')) {
        try {
            Disable-NetAdapter -Name $InterfaceName -Confirm:$false -ErrorAction Stop
            Start-Sleep -Milliseconds 500
            $newStatus = (Get-NetAdapter -Name $InterfaceName -ErrorAction Stop).Status
            if ($newStatus -ne 'Disabled') {
                throw "Adapter status is '$newStatus' after Disable-NetAdapter."
            }
            $script:NetworkReconfigured = $true
            Write-Host "`n✅ $InterfaceName disabled." -ForegroundColor Green
        }
        catch {
            Write-Host "`n❌ Failed to disable '$InterfaceName': $($_.Exception.Message)" -ForegroundColor Red
        }
        return
    }

    try {
        Enable-NetAdapter -Name $InterfaceName -Confirm:$false -ErrorAction Stop
        Start-Sleep -Milliseconds 500
        $newStatus = (Get-NetAdapter -Name $InterfaceName -ErrorAction Stop).Status
        if ($newStatus -eq 'Disabled') {
            throw 'Adapter still reports Disabled after Enable-NetAdapter.'
        }
        $script:NetworkReconfigured = $true
        Write-Host "`n✅ $InterfaceName enabled." -ForegroundColor Green
    }
    catch {
        Write-Host "`n❌ Failed to enable '$InterfaceName': $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    $isWiFi = $adapter.NdisPhysicalMedium -eq 9 -or
        $adapter.InterfaceDescription -match '(?i)wireless|wi-?fi|wlan' -or
        $InterfaceName -match '(?i)wi-?fi|wlan|wireless'

    if (-not $isWiFi) {
        Start-Sleep -Milliseconds 900
        return
    }

    $waitSeconds = 5
    Write-Host "`n📶 Waiting $waitSeconds seconds for Wi-Fi stack to initialize" -NoNewline
    for ($i = 0; $i -lt $waitSeconds; $i++) {
        Start-Sleep -Seconds 1
        Write-Host '.' -NoNewline
    }
    Write-Host 'done'

    $profiles = @(Get-SavedWiFiProfiles)
    if ($profiles.Count -eq 0) {
        Write-Host '⚠️ No saved Wi-Fi profiles found.' -ForegroundColor Yellow
        Pause-EtherShell
        return
    }

    $scan = Get-VisibleWiFiNetworks -InterfaceName $InterfaceName
    if (-not $scan.Success) {
        if ($scan.LocationPermissionRequired) {
            Show-WiFiScanLocationHelp
        }
        else {
            Write-Host '⚠️ Automatic Wi-Fi reconnect scan failed.' -ForegroundColor Yellow
            foreach ($line in @($scan.Output)) {
                Write-Host "   $line" -ForegroundColor DarkGray
            }
        }
        Pause-EtherShell
        return
    }

    $visibleSsids = @($scan.Networks)
    $savedDetails = @(Get-SavedWiFiProfileDetails)
    $matches = @($savedDetails | Where-Object { $visibleSsids -contains $_.SSID })

    if ($matches.Count -eq 0) {
        Write-Host '⚠️ No visible network matches a saved Wi-Fi profile.' -ForegroundColor Yellow
        Pause-EtherShell
        return
    }

    Write-Host "`n📶 Available networks with saved profiles:" -ForegroundColor DarkCyan
    Write-WiFiNetworkTable -Networks $matches

    do {
        $selection = Read-Host "`nEnter network number or Q to cancel"
        if ($selection -match '^[Qq]$') { return }
        $valid = $selection -match '^\d+$' -and
            [int]$selection -ge 1 -and
            [int]$selection -le $matches.Count
        if (-not $valid) { Write-Host '❌ Invalid selection.' -ForegroundColor Red }
    } until ($valid)

    $selectedSSID = [string]$matches[[int]$selection - 1].SSID
    Write-Host "`n🔌 Connecting to '$selectedSSID'..."
    & netsh.exe wlan connect "name=$selectedSSID" "interface=$InterfaceName" | Out-Null
    $netshExitCode = $LASTEXITCODE

    Start-Sleep -Seconds 2
    $connectedSsid = Get-CurrentWiFiSSID -InterfaceName $InterfaceName
    if ($netshExitCode -eq 0 -and $connectedSsid -eq $selectedSSID) {
        Write-Host "✅ Connected to '$selectedSSID'." -ForegroundColor Green
    }
    else {
        Write-Host "⚠️ Connection could not be confirmed." -ForegroundColor Yellow
        if ($connectedSsid) {
            Write-Host "Current SSID: $connectedSsid" -ForegroundColor DarkGray
        }
    }
}

# ────────────────────────────────────────────────────────
# Ping diagnostics
# ────────────────────────────────────────────────────────
function Start-Ping {
    while ($true) {
        Start-PingLoop
        if ($script:PingExitRequested) { break }
    }
}

function Start-PingLoop {
    $script:PingExitRequested = $false
    Clear-Host

    $defaultTarget = '8.8.8.8'
    try {
        $settings = Get-EtherShellSettings -CreateIfMissing
        $savedTarget = [string]$settings['ethershell']['lastPingTarget']
        if (-not [string]::IsNullOrWhiteSpace($savedTarget)) {
            $defaultTarget = $savedTarget
        }
    }
    catch {
        Write-Host "⚠️ settings.json is unavailable or invalid. It will NOT be overwritten by Ping mode." -ForegroundColor Yellow
    }

    $target = Read-Host "Enter address or hostname [ENTER for recent target: $defaultTarget]"
    if ([string]::IsNullOrWhiteSpace($target)) { $target = $defaultTarget }
    $target = $target.Trim()

    if (-not (Test-PingTargetSyntax -Target $target)) {
        Write-Host '❌ Invalid IP address or hostname syntax.' -ForegroundColor Red
        Pause-EtherShell
        return
    }

    try {
        Update-EtherShellSettings -UpdateAction {
            param($latest)
            $latest['ethershell']['lastPingTarget'] = $target
            return $latest
        } | Out-Null
    }
    catch {
        Write-Host "⚠️ Could not save recent ping target: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Clear-Host
    Write-Host
    Write-Host 'Ping: '
    Write-Host 'RTT : '
    Write-Host '[Q] Quit  [E] Export recent  [D] Delete exports  [N] New Ping Request' -ForegroundColor White
    Write-Host
    Write-Host
    Write-Host
    Write-Host

    $graphBars = @()
    $graphRTTs = @()
    $pingBuffer = @()
    $stopRequested = $false
    $exportDir = Join-Path $PSScriptRoot 'PingExports'
    New-Item -ItemType Directory -Path $exportDir -Force -ErrorAction SilentlyContinue | Out-Null

    function Export-BufferedPings {
        if ($pingBuffer.Count -eq 0) {
            Write-Host "`nℹ️ No ping results to export yet." -ForegroundColor DarkGray
            return
        }

        $countInput = Read-Host "`nHow many recent pings to export? [default: 4]"
        if ([string]::IsNullOrWhiteSpace($countInput) -or $countInput -notmatch '^\d+$') {
            $requestedCount = 4
        }
        else {
            $requestedCount = [Math]::Max(1, [int]$countInput)
        }

        $linesToExport = @($pingBuffer | Select-Object -Last $requestedCount)
        $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
        $displayTime = (Get-Date).ToString('dd.MM.yyyy HH:mm:ss')
        $file = Join-Path $exportDir "ping_log_export_$timestamp.txt"

        $header = @(
            '[ Ping-Log Export ]',
            "Target: $target",
            "Time: $displayTime",
            "Count: $($linesToExport.Count)",
            ''
        )

        try {
            $header + $linesToExport | Out-File -FilePath $file -Encoding utf8 -ErrorAction Stop
            Write-Host "`n✅ Exported to $file" -ForegroundColor Green
        }
        catch {
            Write-Host "`n❌ Export failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    function Delete-AllExports {
        $files = @(Get-ChildItem -Path $exportDir -File -ErrorAction SilentlyContinue)
        if ($files.Count -eq 0) {
            Write-Host "`nℹ️ No export files to delete." -ForegroundColor DarkGray
            return
        }

        if (-not (Confirm-EtherShellAction -Prompt "Delete all $($files.Count) ping export file(s)?" -DefaultYes)) {
            Write-Host '↩️ Deletion cancelled.' -ForegroundColor DarkGray
            return
        }

        try {
            $files | Remove-Item -Force -ErrorAction Stop
            Write-Host '✅ All ping export files deleted.' -ForegroundColor Green
        }
        catch {
            Write-Host "❌ Error deleting exports: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    function Get-RttColor {
        param ($Rtt)
        if ($null -eq $Rtt) { return 'DarkGray' }
        if ($Rtt -le 30) { return 'Green' }
        if ($Rtt -le 70) { return 'Yellow' }
        if ($Rtt -le 150) { return 'DarkYellow' }
        return 'Red'
    }

    [Console]::TreatControlCAsInput = $true

    try {
        while (-not $stopRequested) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)

                if (($key.Modifiers -band [ConsoleModifiers]::Control) -and $key.Key -eq 'C') {
                    Write-Host "`nPing aborted by Ctrl+C." -ForegroundColor Yellow
                    $script:PingExitRequested = $true
                    break
                }

                switch ($key.Key) {
                    'E' { Export-BufferedPings }
                    'D' { Delete-AllExports }
                    'N' { return }
                    'Q' {
                        Write-Host "`nPing cancelled." -ForegroundColor Yellow
                        $script:PingExitRequested = $true
                        return
                    }
                }
            }

            $reply = $null
            try {
                $reply = Test-Connection -TargetName $target -Count 1 -TimeoutSeconds 1 -ErrorAction SilentlyContinue |
                    Select-Object -First 1
            }
            catch {
                $reply = $null
            }

            $rtt = $null
            if ($reply -and [string]$reply.Status -eq 'Success') {
                $rtt = [int]$reply.Latency
                $address = if ($reply.Address) { [string]$reply.Address } else { $target }
                $maxLength = 4
                $length = [Math]::Max(1, [Math]::Min([Math]::Ceiling($rtt / 10.0), $maxLength))
                $graphBars += ('|{0}' -f (('█' * $length).PadRight(4)))
                $graphRTTs += (' {0,-4}' -f $rtt)
                $output = ('{0} | Reply from {1} | RTT={2}ms' -f (Get-Date -Format T), $address, $rtt)
            }
            else {
                $graphBars += '|░░░░'
                $graphRTTs += '     '
                $output = ('{0} | No response from {1}' -f (Get-Date -Format T), $target)
            }

            $windowWidth = 100
            try { $windowWidth = $Host.UI.RawUI.WindowSize.Width } catch {}
            $graphCapacity = [Math]::Max(4, [Math]::Min(20, [Math]::Floor(($windowWidth - 6) / 5)))

            if ($graphBars.Count -gt $graphCapacity) {
                $graphBars = @($graphBars | Select-Object -Last $graphCapacity)
            }
            if ($graphRTTs.Count -gt $graphCapacity) {
                $graphRTTs = @($graphRTTs | Select-Object -Last $graphCapacity)
            }

            [Console]::SetCursorPosition(0, 1)
            Write-Host (' ' * [Math]::Max(1, $windowWidth - 1)) -NoNewline
            [Console]::SetCursorPosition(0, 1)
            Write-Host 'Ping: ' -NoNewline
            for ($i = 0; $i -lt $graphBars.Count; $i++) {
                $rttValue = $null
                if ($graphRTTs[$i] -match '\d+') { $rttValue = [int]$Matches[0] }
                Write-Host $graphBars[$i] -NoNewline -ForegroundColor (Get-RttColor -Rtt $rttValue)
            }

            [Console]::SetCursorPosition(0, 2)
            Write-Host (' ' * [Math]::Max(1, $windowWidth - 1)) -NoNewline
            [Console]::SetCursorPosition(0, 2)
            Write-Host 'RTT : ' -NoNewline
            foreach ($rttText in $graphRTTs) {
                Write-Host $rttText -NoNewline
            }

            $pingBuffer += $output
            if ($pingBuffer.Count -gt 100) {
                $pingBuffer = @($pingBuffer | Select-Object -Last 100)
            }

            $maxDisplayLines = 20
            $recent = @($pingBuffer | Select-Object -Last $maxDisplayLines)
            $displayLines = @()
            for ($i = 0; $i -lt ($maxDisplayLines - $recent.Count); $i++) {
                $displayLines += ''
            }
            $displayLines += $recent

            $measuredWidth = ($displayLines | Measure-Object -Property Length -Maximum).Maximum
            if (-not $measuredWidth) { $measuredWidth = 40 }
            $visibleLineWidth = [Math]::Max(40, $measuredWidth)
            $visibleLineWidth = [Math]::Min($visibleLineWidth, [Math]::Max(40, $windowWidth - 2))

            $title = ' Last 20 Replies '
            $padding = [Math]::Max(0, [Math]::Floor(($visibleLineWidth - $title.Length) / 2))
            $line = '┌' + ('─' * $padding) + $title
            if ($line.Length -lt ($visibleLineWidth + 1)) {
                $line += ('─' * (($visibleLineWidth + 1) - $line.Length))
            }
            $line += '┐'

            $headerLine = 5
            [Console]::SetCursorPosition(0, 4)
            Write-Host (' ' * [Math]::Max(1, $windowWidth - 1))
            [Console]::SetCursorPosition(0, $headerLine)
            Write-Host $line -ForegroundColor DarkGray

            for ($i = 0; $i -lt $maxDisplayLines; $i++) {
                $lineIndex = $headerLine + 1 + $i
                [Console]::SetCursorPosition(0, $lineIndex)
                Write-Host (' ' * [Math]::Max(1, [Math]::Min($visibleLineWidth, $windowWidth - 1))) -NoNewline
                [Console]::SetCursorPosition(0, $lineIndex)

                $displayText = [string]$displayLines[$i]
                if ($displayText.Length -gt $visibleLineWidth) {
                    $displayText = $displayText.Substring(0, $visibleLineWidth)
                }

                if ($displayText -match 'No response') {
                    Write-Host $displayText -ForegroundColor Red
                }
                elseif ($displayText) {
                    Write-Host $displayText -ForegroundColor Green
                }
            }

            Start-Sleep -Milliseconds 1000
        }
    }
    catch {
        Write-Host "`n❌ Ping display error: $($_.Exception.Message)" -ForegroundColor Red
        Pause-EtherShell
    }
    finally {
        [Console]::TreatControlCAsInput = $false
    }
}

# ────────────────────────────────────────────────────────
# Wi-Fi credentials
# ────────────────────────────────────────────────────────
function Get-WiFiCredential {
    Write-Host "`n📶 Reading known Wi-Fi profiles..." -ForegroundColor DarkCyan
    $profileDetails = @(Get-SavedWiFiProfileDetails)

    if ($profileDetails.Count -eq 0) {
        Write-Host '⚠️ No known Wi-Fi networks found.' -ForegroundColor Yellow
        Pause-EtherShell
        return
    }

    Write-WiFiNetworkTable -Networks $profileDetails

    do {
        $selection = Read-Host "`nEnter number of Wi-Fi profile to view credentials or Q to cancel"
        if ($selection -match '^[Qq]$') { return }
        $valid = $selection -match '^\d+$' -and
            [int]$selection -ge 1 -and
            [int]$selection -le $profileDetails.Count
        if (-not $valid) {
            Write-Host "❌ Invalid selection. Enter 1-$($profileDetails.Count), or Q." -ForegroundColor Red
        }
    } until ($valid)

    $selectedProfile = [string]$profileDetails[[int]$selection - 1].SSID
    Write-Host "`n🔍 Checking credentials for profile '$selectedProfile'..."

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('EtherShell_WlanKey_' + [guid]::NewGuid().ToString('N'))
    $password = $null

    try {
        New-Item -ItemType Directory -Path $tempDir -Force -ErrorAction Stop | Out-Null

        & netsh.exe wlan export profile "name=$selectedProfile" "folder=$tempDir" key=clear | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "netsh exited with code $LASTEXITCODE."
        }

        $profileFiles = @(Get-ChildItem -LiteralPath $tempDir -Filter '*.xml' -File -ErrorAction Stop)
        if ($profileFiles.Count -eq 0) {
            throw 'No WLAN profile XML was exported.'
        }

        [xml]$profileXml = Get-Content -LiteralPath $profileFiles[0].FullName -Raw -ErrorAction Stop
        $keyNode = $profileXml.SelectSingleNode("//*[local-name()='keyMaterial']")
        if ($keyNode) {
            $password = [string]$keyNode.InnerText
        }
    }
    catch {
        Write-Host "❌ Failed to read Wi-Fi profile: $($_.Exception.Message)" -ForegroundColor Red
        Pause-EtherShell
        return
    }
    finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($password)) {
        Write-Host "🔑 Password: $password" -ForegroundColor DarkGray
    }
    else {
        Write-Host '⚠️ No password found. The profile may be open or use enterprise authentication.' -ForegroundColor Yellow
    }

    Pause-EtherShell -Message 'Press any key to return...'
}

# ────────────────────────────────────────────────────────
# Miscellaneous views
# ────────────────────────────────────────────────────────
function Show-IPConfig {
    param (
        [string]$AdapterName = $script:AdapterName
    )

    Write-Host "`nCurrent IPv4 configuration for interface '$AdapterName':" -ForegroundColor DarkCyan

    try {
        $ipConfig = Get-NetIPConfiguration -InterfaceAlias $AdapterName -ErrorAction Stop
        $ipv4 = @($ipConfig.IPv4Address.IPAddress) -join ', '
        $gateway = @($ipConfig.IPv4DefaultGateway.NextHop) -join ', '
        $dnsServers = @($ipConfig.DnsServer.ServerAddresses | Where-Object { Test-IPv4Address -Address ([string]$_) }) -join ', '

        if (-not $ipv4) { $ipv4 = 'Not available' }
        if (-not $gateway) { $gateway = 'Not available' }
        if (-not $dnsServers) { $dnsServers = 'Not available' }

        Write-Host "  IPv4 Address    : $ipv4"
        Write-Host "  Default Gateway : $gateway"
        Write-Host "  DNS Server      : $dnsServers"
    }
    catch {
        Write-Host "❌ Adapter '$AdapterName' not found or configuration is unavailable." -ForegroundColor Red
    }

    Pause-EtherShell
}

function IPConfigAll {
    & ipconfig.exe /all
    Pause-EtherShell
}

function Show-ConnectivityStatus {
    Show-SectionHeader -Title 'Connectivity Status' -Subtitle "Selected adapter: $script:AdapterName"

    $internetInfo = Get-InternetStatus
    $vpnInfo = Get-VPNStatus

    Write-Host 'Internet : ' -NoNewline
    Write-Host $internetInfo.Status -ForegroundColor $internetInfo.Color
    Write-Host 'VPN      : ' -NoNewline
    Write-Host $vpnInfo.Status -ForegroundColor $vpnInfo.Color
    if ($vpnInfo.URL) {
        Write-Host "VPN Test : $($vpnInfo.URL)" -ForegroundColor DarkGray
    }
    if ($script:NetworkReconfigured -and $vpnInfo.Status -eq 'Connected / DNS unavailable') {
        Write-Host
        Write-VpnDnsReconnectHint -VpnInfo $vpnInfo
    }

    Pause-EtherShell
}

function Show-SavedWiFiProfiles {
    Show-SectionHeader -Title 'Known Wi-Fi Networks'
    $profiles = @(Get-SavedWiFiProfileDetails)

    if ($profiles.Count -eq 0) {
        Write-Host '⚠️ No known Wi-Fi networks found.' -ForegroundColor Yellow
        Pause-EtherShell
        return
    }

    Write-WiFiNetworkTable -Networks $profiles
    Pause-EtherShell
}


function Get-WiFiAdapters {
    try {
        return @(Get-NetAdapter -ErrorAction Stop | Where-Object {
                $_.NdisPhysicalMedium -eq 9 -or
                $_.InterfaceDescription -match '(?i)wireless|wi-?fi|wlan' -or
                $_.Name -match '(?i)wi-?fi|wlan|wireless'
            } | Sort-Object Name)
    }
    catch {
        return @()
    }
}

function Select-WiFiAdapter {
    $adapters = @(Get-WiFiAdapters)
    if ($adapters.Count -eq 0) {
        Write-Host '⚠️ No Wi-Fi adapter found.' -ForegroundColor Yellow
        return $null
    }

    $selected = $adapters | Where-Object { $_.Name -eq $script:AdapterName } | Select-Object -First 1
    if ($selected) { return $selected.Name }
    if ($adapters.Count -eq 1) { return $adapters[0].Name }

    Write-Host "`nAvailable Wi-Fi adapters:" -ForegroundColor DarkCyan
    for ($i = 0; $i -lt $adapters.Count; $i++) {
        Write-Host ("[{0}] {1} | {2}" -f ($i + 1), $adapters[$i].Name, $adapters[$i].Status)
    }

    do {
        $choice = Read-Host "`nSelect Wi-Fi adapter or Q to cancel"
        if ($choice -match '^[Qq]$') { return $null }
        $valid = $choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $adapters.Count
        if (-not $valid) { Write-Host '❌ Invalid selection.' -ForegroundColor Red }
    } until ($valid)

    return $adapters[[int]$choice - 1].Name
}

function Show-WiFiScanLocationHelp {
    Write-Host '⚠️ Windows blocked the Wi-Fi scan because WLAN location/privacy permission is not available.' -ForegroundColor Yellow
    Write-Host '   EtherShell only asks about Location settings after Windows actually blocks the scan.' -ForegroundColor DarkGray
    Write-Host
    Write-Host '[1] Open Location Settings'
    Write-Host '[Q] Cancel'

    $choice = (Read-Host "`nGo").Trim().ToLowerInvariant()
    if ($choice -eq '1') {
        try {
            Start-Process 'ms-settings:privacy-location'
        }
        catch {
            Write-Host "❌ Could not open Location settings: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

function Ensure-WiFiAdapterEnabled {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$InterfaceName
    )

    $adapter = Get-NetAdapter -Name $InterfaceName -ErrorAction SilentlyContinue
    if (-not $adapter) {
        Write-Host "❌ Wi-Fi adapter '$InterfaceName' was not found." -ForegroundColor Red
        return $false
    }

    if ($adapter.Status -ne 'Disabled') {
        return $true
    }

    Write-Host "⚠️ Wi-Fi adapter '$InterfaceName' is disabled." -ForegroundColor Yellow
    if (-not (Confirm-EtherShellAction -Prompt 'Enable it now?' -DefaultYes)) {
        return $false
    }

    try {
        Enable-NetAdapter -Name $InterfaceName -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 2

        $newStatus = (Get-NetAdapter -Name $InterfaceName -ErrorAction Stop).Status
        if ($newStatus -eq 'Disabled') {
            throw 'Adapter still reports Disabled after Enable-NetAdapter.'
        }

        Write-Host "✅ Wi-Fi adapter '$InterfaceName' enabled." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "❌ Failed to enable '$InterfaceName': $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Toggle-WiFiInterface {
    $wifiAdapter = Select-WiFiAdapter
    if (-not $wifiAdapter) {
        Pause-EtherShell
        return
    }

    $adapter = Get-NetAdapter -Name $wifiAdapter -ErrorAction SilentlyContinue
    if (-not $adapter) {
        Write-Host "❌ Wi-Fi adapter '$wifiAdapter' was not found." -ForegroundColor Red
        Pause-EtherShell
        return
    }

    try {
        if ($adapter.Status -eq 'Disabled') {
            Write-Host "`n📶 Enabling Wi-Fi interface '$wifiAdapter'..." -ForegroundColor DarkCyan
            Enable-NetAdapter -Name $wifiAdapter -Confirm:$false -ErrorAction Stop
            Start-Sleep -Seconds 2

            $newStatus = (Get-NetAdapter -Name $wifiAdapter -ErrorAction Stop).Status
            if ($newStatus -eq 'Disabled') {
                throw 'Adapter still reports Disabled after Enable-NetAdapter.'
            }

            $script:NetworkReconfigured = $true
            Write-Host "✅ Wi-Fi interface '$wifiAdapter' enabled." -ForegroundColor Green
        }
        else {
            Write-Host "`n📴 Disabling Wi-Fi interface '$wifiAdapter'..." -ForegroundColor DarkCyan
            Disable-NetAdapter -Name $wifiAdapter -Confirm:$false -ErrorAction Stop
            Start-Sleep -Milliseconds 700

            $newStatus = (Get-NetAdapter -Name $wifiAdapter -ErrorAction Stop).Status
            if ($newStatus -ne 'Disabled') {
                throw "Adapter status is '$newStatus' after Disable-NetAdapter."
            }

            $script:NetworkReconfigured = $true
            Write-Host "✅ Wi-Fi interface '$wifiAdapter' disabled." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "❌ Failed to toggle Wi-Fi interface '$wifiAdapter': $($_.Exception.Message)" -ForegroundColor Red
    }

    Pause-EtherShell
}

function Forget-SavedWiFiNetwork {
    $profileDetails = @(Get-SavedWiFiProfileDetails)

    Show-SectionHeader -Title 'Forget Known Wi-Fi Network'

    if ($profileDetails.Count -eq 0) {
        Write-Host '⚠️ No known Wi-Fi networks found.' -ForegroundColor Yellow
        Pause-EtherShell
        return
    }

    Write-WiFiNetworkTable -Networks $profileDetails

    do {
        $choice = (Read-Host "`nSelect network to forget or Q to cancel").Trim()
        if ($choice -match '^[Qq]$') { return }

        $valid = $choice -match '^\d+$' -and
            [int]$choice -ge 1 -and
            [int]$choice -le $profileDetails.Count

        if (-not $valid) {
            Write-Host "❌ Enter a number between 1 and $($profileDetails.Count), or Q." -ForegroundColor Red
        }
    } until ($valid)

    $ssid = [string]$profileDetails[[int]$choice - 1].SSID

    Write-Host "`nThis removes the saved Windows WLAN profile for '$ssid'." -ForegroundColor Yellow
    if (-not (Confirm-EtherShellAction -Prompt "Forget '$ssid'?")) {
        Write-Host '↩️ Operation cancelled.' -ForegroundColor DarkGray
        Pause-EtherShell
        return
    }

    & netsh.exe wlan delete profile "name=$ssid" | Out-Null
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        $remaining = @(Get-SavedWiFiProfiles)
        if ($remaining -contains $ssid) {
            Write-Host "⚠️ Windows reported success, but '$ssid' is still present on at least one Wi-Fi interface." -ForegroundColor Yellow
        }
        else {
            Write-Host "✅ Wi-Fi network '$ssid' forgotten successfully." -ForegroundColor Green
        }
    }
    else {
        Write-Host "❌ Failed to forget '$ssid'. netsh exit code: $exitCode" -ForegroundColor Red
    }

    Pause-EtherShell
}


function Read-WiFiPassword {
    Write-Host
    Write-Host 'Enter Wi-Fi password.' -ForegroundColor DarkCyan
    Write-Host 'Press ENTER with an empty password only for an open network.' -ForegroundColor DarkGray

    $securePassword = Read-Host 'Password' -AsSecureString
    return [System.Net.NetworkCredential]::new('', $securePassword).Password
}

function Test-WiFiPassword {
    param (
        [AllowEmptyString()]
        [string]$Password
    )

    if ([string]::IsNullOrEmpty($Password)) {
        return $true
    }

    if ($Password -match '^[0-9A-Fa-f]{64}$') {
        return $true
    }

    return $Password.Length -ge 8 -and $Password.Length -le 63
}

function Read-WiFiAutoConnectChoice {
    do {
        $choice = (Read-Host 'Connect automatically when this network is in range? (Y/N) [default: Y]').Trim().ToLowerInvariant()

        if ([string]::IsNullOrWhiteSpace($choice) -or $choice -eq 'y' -or $choice -eq 'yes') {
            return [pscustomobject]@{
                Cancelled = $false
                Value     = [bool]$true
            }
        }

        if ($choice -eq 'n' -or $choice -eq 'no') {
            return [pscustomobject]@{
                Cancelled = $false
                Value     = [bool]$false
            }
        }

        if ($choice -eq 'q') {
            return [pscustomobject]@{
                Cancelled = $true
                Value     = [bool]$false
            }
        }

        Write-Host '❌ Enter Y, N, Q, or press ENTER for Yes.' -ForegroundColor Red
    } while ($true)
}

function New-WiFiProfileXml {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$SSID,

        [AllowEmptyString()]
        [string]$Password,

        [Parameter(Mandatory)]
        [bool]$ConnectAutomatically,

        [Parameter(Mandatory)]
        [bool]$HiddenNetwork,

        [Parameter(Mandatory)]
        [ValidateSet('open', 'WPA2PSK', 'WPA3SAE')]
        [string]$Authentication
    )

    $ssidEscaped = [System.Security.SecurityElement]::Escape($SSID)
    $passwordEscaped = [System.Security.SecurityElement]::Escape($Password)
    $connectionMode = if ($ConnectAutomatically) { 'auto' } else { 'manual' }
    $nonBroadcast = if ($HiddenNetwork) { 'true' } else { 'false' }

    if ($Authentication -eq 'open') {
        $securityXml = @"
        <security>
            <authEncryption>
                <authentication>open</authentication>
                <encryption>none</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
        </security>
"@
    }
    else {
        $securityXml = @"
        <security>
            <authEncryption>
                <authentication>$Authentication</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$passwordEscaped</keyMaterial>
            </sharedKey>
        </security>
"@
    }

    return @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$ssidEscaped</name>
    <SSIDConfig>
        <SSID>
            <name>$ssidEscaped</name>
        </SSID>
        <nonBroadcast>$nonBroadcast</nonBroadcast>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>$connectionMode</connectionMode>
    <autoSwitch>false</autoSwitch>
    <MSM>
$securityXml
    </MSM>
</WLANProfile>
"@
}

function Wait-WiFiConnection {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$InterfaceName,

        [Parameter(Mandatory)]
        [string]$SSID,

        [int]$TimeoutSeconds = 15
    )

    for ($i = 0; $i -lt $TimeoutSeconds; $i++) {
        Start-Sleep -Seconds 1
        $state = Get-WiFiConnectionState -InterfaceName $InterfaceName

        if (-not $state.VerificationAvailable) {
            return [pscustomobject]@{
                VerificationAvailable      = $false
                Connected                  = $false
                LocationPermissionRequired = [bool]$state.LocationPermissionRequired
            }
        }

        if ($state.SSID -eq $SSID) {
            return [pscustomobject]@{
                VerificationAvailable      = $true
                Connected                  = $true
                LocationPermissionRequired = $false
            }
        }
    }

    return [pscustomobject]@{
        VerificationAvailable      = $true
        Connected                  = $false
        LocationPermissionRequired = $false
    }
}


function Install-WiFiProfileAndConnect {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$InterfaceName,

        [Parameter(Mandatory)]
        [string]$SSID,

        [AllowEmptyString()]
        [string]$Password,

        [Parameter(Mandatory)]
        [bool]$ConnectAutomatically,

        [Parameter(Mandatory)]
        [bool]$HiddenNetwork
    )

    $knownProfiles = @(Get-SavedWiFiProfiles)
    if ($knownProfiles -contains $SSID) {
        Write-Host "⚠️ '$SSID' already exists as a known Windows Wi-Fi network." -ForegroundColor Yellow
        Write-Host 'Use Wi-Fi -> Manage Known Networks to connect to or forget the existing profile first.' -ForegroundColor DarkGray
        return $false
    }

    if (-not (Test-WiFiPassword -Password $Password)) {
        Write-Host '❌ Wi-Fi password must be 8-63 characters, a 64-character hexadecimal key, or empty for an open network.' -ForegroundColor Red
        return $false
    }

    $authenticationModes = if ([string]::IsNullOrEmpty($Password)) {
        @([pscustomobject]@{ Value = 'open'; Label = 'Open' })
    }
    else {
        @(
            [pscustomobject]@{ Value = 'WPA2PSK'; Label = 'WPA2-Personal' },
            [pscustomobject]@{ Value = 'WPA3SAE'; Label = 'WPA3-Personal' }
        )
    }

    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ('EtherShell_WlanProfile_' + [guid]::NewGuid().ToString('N') + '.xml')
    $connected = $false
    $connectionRequestAccepted = $false
    $verificationUnavailable = $false
    $verificationLocationBlocked = $false

    try {
        for ($index = 0; $index -lt $authenticationModes.Count; $index++) {
            $auth = $authenticationModes[$index]

            $profileXml = New-WiFiProfileXml `
                -SSID $SSID `
                -Password $Password `
                -ConnectAutomatically $ConnectAutomatically `
                -HiddenNetwork $HiddenNetwork `
                -Authentication $auth.Value

            [System.IO.File]::WriteAllText(
                $tempFile,
                $profileXml,
                [System.Text.UTF8Encoding]::new($false)
            )

            & netsh.exe wlan add profile "filename=$tempFile" "interface=$InterfaceName" user=current | Out-Null
            $addExitCode = $LASTEXITCODE
            if ($addExitCode -ne 0) {
                continue
            }

            if ($index -eq 0) {
                Write-Host "`n🔌 Connecting '$InterfaceName' to '$SSID' using $($auth.Label)..." -ForegroundColor DarkCyan
            }
            else {
                Write-Host "`n🔌 Retrying '$SSID' using $($auth.Label)..." -ForegroundColor DarkCyan
            }

            & netsh.exe wlan connect "name=$SSID" "ssid=$SSID" "interface=$InterfaceName" | Out-Null
            $connectExitCode = $LASTEXITCODE

            if ($connectExitCode -ne 0) {
                continue
            }

            $connectionRequestAccepted = $true
            $verification = Wait-WiFiConnection `
                -InterfaceName $InterfaceName `
                -SSID $SSID `
                -TimeoutSeconds 15

            if (-not $verification.VerificationAvailable) {
                # Do not try another security mode just because Windows blocked
                # EtherShell from reading the current SSID.
                $verificationUnavailable = $true
                $verificationLocationBlocked = [bool]$verification.LocationPermissionRequired
                break
            }

            if ($verification.Connected) {
                $connected = $true
                break
            }

            # Verification was available and the requested SSID did not connect.
            # A password-protected network can now legitimately retry WPA3.
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    if ($connected) {
        Write-Host "✅ Successfully connected to '$SSID'." -ForegroundColor Green
        Write-Host "   Saved profile: Connect automatically = $ConnectAutomatically" -ForegroundColor DarkGray
        return $true
    }

    if ($connectionRequestAccepted -and $verificationUnavailable) {
        Write-Host "⚠️ Windows accepted the connection request for '$SSID', but EtherShell could not verify the connected SSID." -ForegroundColor Yellow

        if ($verificationLocationBlocked) {
            Write-Host '   Windows blocked WLAN status access because Location Services permission is unavailable.' -ForegroundColor DarkGray
            Write-Host '   Location permission is only needed for EtherShell to read WLAN scan/status information, not to submit the connection request.' -ForegroundColor DarkGray
        }
        else {
            Write-Host '   WLAN status information was unavailable, so the connection result could not be verified.' -ForegroundColor DarkGray
        }

        Write-Host "   The saved Wi-Fi profile was kept. Connect automatically = $ConnectAutomatically" -ForegroundColor DarkGray
        return $true
    }

    # Remove only a newly created profile whose connection request was rejected,
    # or whose failed connection could actually be verified.
    & netsh.exe wlan delete profile "name=$SSID" "interface=$InterfaceName" | Out-Null

    Write-Host "❌ Failed to connect to '$SSID'." -ForegroundColor Red
    Write-Host '   Check the SSID/password and make sure the network uses Open, WPA2-Personal, or WPA3-Personal security.' -ForegroundColor DarkGray
    return $false
}


function Connect-NewVisibleWiFiNetwork {
    $wifiAdapter = Select-WiFiAdapter
    if (-not $wifiAdapter) {
        Pause-EtherShell
        return
    }

    if (-not (Ensure-WiFiAdapterEnabled -InterfaceName $wifiAdapter)) {
        Pause-EtherShell
        return
    }

    Show-SectionHeader -Title 'Connect to New Wi-Fi' -Subtitle "Visible network scan on: $wifiAdapter"

    Write-Host '📶 Scanning for visible Wi-Fi networks...' -ForegroundColor DarkCyan
    $scan = Get-VisibleWiFiNetworks -InterfaceName $wifiAdapter

    if (-not $scan.Success) {
        if ($scan.LocationPermissionRequired) {
            Show-WiFiScanLocationHelp
        }
        else {
            Write-Host '❌ Wi-Fi scan failed.' -ForegroundColor Red
            if (@($scan.Output).Count -gt 0) {
                Write-Host 'Windows/netsh returned:' -ForegroundColor DarkGray
                foreach ($line in @($scan.Output)) {
                    Write-Host "   $line" -ForegroundColor DarkGray
                }
            }
        }

        Pause-EtherShell
        return
    }

    $networkDetails = @($scan.NetworkDetails)
    if ($networkDetails.Count -eq 0) {
        Write-Host 'ℹ️ The scan completed successfully, but no visible Wi-Fi networks were found.' -ForegroundColor DarkGray
        Pause-EtherShell
        return
    }

    Write-WiFiNetworkTable -Networks $networkDetails

    do {
        $choice = (Read-Host "`nSelect network or Q to cancel").Trim()
        if ($choice -match '^[Qq]$') { return }

        $valid = $choice -match '^\d+$' -and
            [int]$choice -ge 1 -and
            [int]$choice -le $networkDetails.Count

        if (-not $valid) {
            Write-Host "❌ Enter a number between 1 and $($networkDetails.Count), or Q." -ForegroundColor Red
        }
    } until ($valid)

    $ssid = [string]$networkDetails[[int]$choice - 1].SSID

    if (@(Get-SavedWiFiProfiles) -contains $ssid) {
        Write-Host "`n⚠️ '$ssid' is already a known Wi-Fi network." -ForegroundColor Yellow
        Write-Host 'Use Wi-Fi -> Manage Known Networks -> Connect to Known Network.' -ForegroundColor DarkGray
        Pause-EtherShell
        return
    }

    $password = Read-WiFiPassword
    if (-not (Test-WiFiPassword -Password $password)) {
        Write-Host '❌ Wi-Fi password must be 8-63 characters, a 64-character hexadecimal key, or empty for an open network.' -ForegroundColor Red
        Pause-EtherShell
        return
    }

    $autoChoice = Read-WiFiAutoConnectChoice
    if ($autoChoice.Cancelled) {
        Write-Host '↩️ Connection cancelled.' -ForegroundColor DarkGray
        Pause-EtherShell
        return
    }

    [bool]$connectAutomatically = $autoChoice.Value

    Install-WiFiProfileAndConnect `
        -InterfaceName $wifiAdapter `
        -SSID $ssid `
        -Password $password `
        -ConnectAutomatically $connectAutomatically `
        -HiddenNetwork $false | Out-Null

    Pause-EtherShell
}

function Connect-NewHiddenWiFiNetwork {
    $wifiAdapter = Select-WiFiAdapter
    if (-not $wifiAdapter) {
        Pause-EtherShell
        return
    }

    if (-not (Ensure-WiFiAdapterEnabled -InterfaceName $wifiAdapter)) {
        Pause-EtherShell
        return
    }

    Show-SectionHeader -Title 'Connect to New Wi-Fi' -Subtitle "Hidden / manually entered SSID on: $wifiAdapter"

    $ssid = (Read-Host 'Enter hidden / manual SSID (ENTER to cancel)').Trim()
    if ([string]::IsNullOrWhiteSpace($ssid)) {
        Write-Host '↩️ Connection cancelled.' -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 500
        return
    }

    if ($ssid.Length -gt 32) {
        Write-Host '❌ SSID must not exceed 32 characters.' -ForegroundColor Red
        Pause-EtherShell
        return
    }

    if (@(Get-SavedWiFiProfiles) -contains $ssid) {
        Write-Host "`n⚠️ '$ssid' is already a known Wi-Fi network." -ForegroundColor Yellow
        Write-Host 'Use Wi-Fi -> Manage Known Networks -> Connect to Known Network.' -ForegroundColor DarkGray
        Pause-EtherShell
        return
    }

    $password = Read-WiFiPassword
    if (-not (Test-WiFiPassword -Password $password)) {
        Write-Host '❌ Wi-Fi password must be 8-63 characters, a 64-character hexadecimal key, or empty for an open network.' -ForegroundColor Red
        Pause-EtherShell
        return
    }

    $autoChoice = Read-WiFiAutoConnectChoice
    if ($autoChoice.Cancelled) {
        Write-Host '↩️ Connection cancelled.' -ForegroundColor DarkGray
        Pause-EtherShell
        return
    }

    [bool]$connectAutomatically = $autoChoice.Value

    Install-WiFiProfileAndConnect `
        -InterfaceName $wifiAdapter `
        -SSID $ssid `
        -Password $password `
        -ConnectAutomatically $connectAutomatically `
        -HiddenNetwork $true | Out-Null

    Pause-EtherShell
}

function Show-ConnectNewWiFiMenu {
    do {
        Show-SectionHeader -Title 'Wi-Fi > Connect to New Network'
        Write-Host '┌' -ForegroundColor $script:BannerColor
        foreach ($entry in @(
                '[1] Search Visible Networks',
                '[2] Hidden / Manual SSID'
            )) {
            Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
            Write-Host " $entry"
        }
        Write-Host '├──────────────────────────────────────────────' -ForegroundColor $script:BannerColor
        Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
        Write-Host ' [Q] Back'
        Write-Host '└──────────────────────────────────────────────' -ForegroundColor $script:BannerColor

        $choice = (Read-Host "`nGo").Trim().ToLowerInvariant()
        switch ($choice) {
            '1' { Connect-NewVisibleWiFiNetwork }
            '2' { Connect-NewHiddenWiFiNetwork }
            'q' { }
            default { Start-Sleep -Milliseconds 500 }
        }
    } while ($choice -ne 'q')
}

function Show-ManageKnownNetworksMenu {
    do {
        Show-SectionHeader -Title 'Wi-Fi > Manage Known Networks'
        Write-Host '┌' -ForegroundColor $script:BannerColor
        foreach ($entry in @(
                '[1] List Known Networks',
                '[2] Show Network Credentials',
                '[3] Connect to Known Network',
                '[4] Forget Network'
            )) {
            Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
            Write-Host " $entry"
        }
        Write-Host '├──────────────────────────────────────────────' -ForegroundColor $script:BannerColor
        Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
        Write-Host ' [Q] Back'
        Write-Host '└──────────────────────────────────────────────' -ForegroundColor $script:BannerColor

        $choice = (Read-Host "`nGo").Trim().ToLowerInvariant()
        switch ($choice) {
            '1' { Show-SavedWiFiProfiles }
            '2' { Get-WiFiCredential }
            '3' { Connect-SavedWiFiNetwork }
            '4' { Forget-SavedWiFiNetwork }
            'q' { }
            default { Start-Sleep -Milliseconds 500 }
        }
    } while ($choice -ne 'q')
}

function Connect-SavedWiFiNetwork {
    $wifiAdapter = Select-WiFiAdapter
    if (-not $wifiAdapter) {
        Pause-EtherShell
        return
    }

    if (-not (Ensure-WiFiAdapterEnabled -InterfaceName $wifiAdapter)) {
        Pause-EtherShell
        return
    }

    $profileDetails = @(Get-SavedWiFiProfileDetails)
    if ($profileDetails.Count -eq 0) {
        Write-Host '⚠️ No known Wi-Fi networks found.' -ForegroundColor Yellow
        Pause-EtherShell
        return
    }

    Write-WiFiNetworkTable -Networks $profileDetails

    do {
        $choice = Read-Host "`nSelect profile to connect or Q to cancel"
        if ($choice -match '^[Qq]$') { return }

        $valid = $choice -match '^\d+$' -and
            [int]$choice -ge 1 -and
            [int]$choice -le $profileDetails.Count

        if (-not $valid) {
            Write-Host '❌ Invalid selection.' -ForegroundColor Red
        }
    } until ($valid)

    $ssid = [string]$profileDetails[[int]$choice - 1].SSID

    Write-Host "`n🔌 Connecting '$wifiAdapter' to known network '$ssid'..." -ForegroundColor DarkCyan
    & netsh.exe wlan connect "name=$ssid" "interface=$wifiAdapter" | Out-Null
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        Write-Host "❌ Windows rejected the connection request for '$ssid'. netsh exit code: $exitCode" -ForegroundColor Red
        Pause-EtherShell
        return
    }

    $verification = Wait-WiFiConnection `
        -InterfaceName $wifiAdapter `
        -SSID $ssid `
        -TimeoutSeconds 15

    if ($verification.VerificationAvailable -and $verification.Connected) {
        Write-Host "✅ Connected to '$ssid'." -ForegroundColor Green
    }
    elseif (-not $verification.VerificationAvailable) {
        Write-Host "⚠️ Windows accepted the connection request for '$ssid', but EtherShell could not verify the connected SSID." -ForegroundColor Yellow

        if ($verification.LocationPermissionRequired) {
            Write-Host '   WLAN status access is blocked by Windows Location Services/privacy permission.' -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "❌ The connection request was accepted, but '$ssid' was not connected within the verification timeout." -ForegroundColor Red
    }

    Pause-EtherShell
}


function Show-WiFiAdapterStatus {
    Show-SectionHeader -Title 'Wi-Fi Adapter Status'
    & netsh.exe wlan show interfaces
    Pause-EtherShell
}

function Get-AdapterIPv4DnsState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$AdapterName
    )

    $result = [ordered]@{
        AdapterExists  = $false
        AdapterEnabled = $false
        DhcpEnabled    = $false
        DnsServers     = @()
        DnsIsStatic    = $false
    }

    try {
        $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction Stop
        $result['AdapterExists'] = $true
        $result['AdapterEnabled'] = $adapter.Status -ne 'Disabled'

        $ipv4Interface = Get-NetIPInterface -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction Stop |
            Select-Object -First 1
        $result['DhcpEnabled'] = $ipv4Interface -and $ipv4Interface.Dhcp -eq 'Enabled'

        $result['DnsServers'] = @(Get-DnsClientServerAddress -InterfaceAlias $AdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            ForEach-Object { $_.ServerAddresses } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_) -and
                (Test-IPv4Address -Address ([string]$_))
            })

        try {
            $interfaceGuid = ([guid]$adapter.InterfaceGuid).ToString('B')
            $tcpipKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$interfaceGuid"
            $nameServer = Get-ItemPropertyValue -Path $tcpipKey -Name 'NameServer' -ErrorAction SilentlyContinue
            $result['DnsIsStatic'] = -not [string]::IsNullOrWhiteSpace([string]$nameServer)
        }
        catch {
            $result['DnsIsStatic'] = $false
        }
    }
    catch {
        # Settings management must remain usable even if the selected adapter
        # is temporarily unavailable.
    }

    return [pscustomobject]$result
}

function Apply-SavedDhcpDnsToSelectedAdapter {
    [CmdletBinding()]
    param (
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DnsServer,

        [switch]$ResetToDhcp
    )

    $adapterName = $script:AdapterName
    $state = Get-AdapterIPv4DnsState -AdapterName $adapterName

    if (-not $state.AdapterExists) {
        Write-Host "⚠️ DNS preference was saved, but selected adapter '$adapterName' was not found." -ForegroundColor Yellow
        return
    }

    if (-not $state.AdapterEnabled) {
        Write-Host "⚠️ DNS preference was saved, but '$adapterName' is disabled. No Windows DNS setting was changed." -ForegroundColor Yellow
        return
    }

    if (-not $state.DhcpEnabled) {
        Write-Host "⚠️ DNS preference was saved, but '$adapterName' is not using DHCP." -ForegroundColor Yellow
        Write-Host '   The current static network configuration was left unchanged.' -ForegroundColor DarkGray
        return
    }

    if ($ResetToDhcp) {
        $prompt = "Reset the active DNS configuration on '$adapterName' to DHCP-provided DNS now?"
    }
    else {
        $prompt = "Apply $DnsServer to the currently selected adapter '$adapterName' now?"
    }

    if (-not (Confirm-EtherShellAction -Prompt $prompt -DefaultYes)) {
        Write-Host 'ℹ️ Preference saved only. The active Windows DNS configuration was not changed.' -ForegroundColor DarkGray
        return
    }

    try {
        if ($ResetToDhcp) {
            Set-DnsClientServerAddress -InterfaceAlias $adapterName -ResetServerAddresses -ErrorAction Stop
        }
        else {
            Set-DnsClientServerAddress -InterfaceAlias $adapterName -ServerAddresses $DnsServer -ErrorAction Stop
        }

        Start-Sleep -Milliseconds 300

        $activeDns = @(Get-DnsClientServerAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            ForEach-Object { $_.ServerAddresses } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_) -and
                (Test-IPv4Address -Address ([string]$_))
            })

        $script:NetworkReconfigured = $true

        if ($ResetToDhcp) {
            if ($activeDns.Count -gt 0) {
                Write-Host "✅ Active DNS reset to DHCP-provided DNS: $($activeDns -join ', ')" -ForegroundColor Green
            }
            else {
                Write-Host '✅ Active DNS configuration reset to DHCP-provided DNS.' -ForegroundColor Green
            }
        }
        else {
            if ($activeDns -contains $DnsServer) {
                Write-Host "✅ Active DNS on '$adapterName' is now $DnsServer." -ForegroundColor Green
            }
            else {
                Write-Host "✅ DNS configuration was applied to '$adapterName'." -ForegroundColor Green
                if ($activeDns.Count -gt 0) {
                    Write-Host "   Windows currently reports: $($activeDns -join ', ')" -ForegroundColor DarkGray
                }
            }
        }
    }
    catch {
        Write-Host "❌ Failed to change the active DNS configuration: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Manage-DhcpDnsSetting {
    do {
        try {
            $settings = Get-EtherShellSettings -CreateIfMissing
            $currentDns = [string]$settings['ethershell']['network']['dhcpDns']
        }
        catch {
            Write-Host "❌ Unable to read settings.json: $($_.Exception.Message)" -ForegroundColor Red
            Pause-EtherShell
            return
        }

        $adapterState = Get-AdapterIPv4DnsState -AdapterName $script:AdapterName
        $displayDns = if ([string]::IsNullOrWhiteSpace($currentDns)) { 'DHCP default' } else { $currentDns }
        $activeDnsDisplay = if (@($adapterState.DnsServers).Count -gt 0) {
            @($adapterState.DnsServers) -join ', '
        }
        else {
            'Not available'
        }
        $modeDisplay = if (-not $adapterState.AdapterExists) {
            'Adapter not found'
        }
        elseif (-not $adapterState.AdapterEnabled) {
            'Disabled'
        }
        elseif ($adapterState.DhcpEnabled) {
            'DHCP'
        }
        else {
            'Static'
        }

        Show-SectionHeader -Title 'DHCP DNS' -Subtitle 'DNS preference used with DHCP mode'
        Write-Host "Saved preference : $displayDns"
        Write-Host "Selected adapter : $script:AdapterName"
        Write-Host "Adapter mode     : $modeDisplay"
        Write-Host "Active IPv4 DNS  : $activeDnsDisplay"
        Write-Host
        Write-Host '[1] Set / Change DNS'
        Write-Host '[2] Clear Custom DNS'
        Write-Host '[Q] Back'

        $choice = (Read-Host "`nGo").Trim().ToLowerInvariant()
        switch ($choice) {
            '1' {
                $newDns = (Read-Host 'Enter IPv4 DNS server').Trim()
                if (-not (Test-IPv4Address -Address $newDns)) {
                    Write-Host '❌ Invalid IPv4 DNS server.' -ForegroundColor Red
                    Start-Sleep -Milliseconds 900
                    continue
                }

                try {
                    Update-EtherShellSettings -UpdateAction {
                        param($latest)
                        $latest['ethershell']['network']['dhcpDns'] = $newDns
                        return $latest
                    } | Out-Null
                    Write-Host '✅ DHCP DNS preference saved.' -ForegroundColor Green
                }
                catch {
                    Write-Host "❌ Failed to save DHCP DNS: $($_.Exception.Message)" -ForegroundColor Red
                    Pause-EtherShell
                    continue
                }

                Apply-SavedDhcpDnsToSelectedAdapter -DnsServer $newDns
                Pause-EtherShell
            }
            '2' {
                try {
                    Update-EtherShellSettings -UpdateAction {
                        param($latest)
                        $latest['ethershell']['network']['dhcpDns'] = ''
                        return $latest
                    } | Out-Null
                    Write-Host '✅ Custom DHCP DNS preference cleared.' -ForegroundColor Green
                }
                catch {
                    Write-Host "❌ Failed to update settings: $($_.Exception.Message)" -ForegroundColor Red
                    Pause-EtherShell
                    continue
                }

                Apply-SavedDhcpDnsToSelectedAdapter -ResetToDhcp
                Pause-EtherShell
            }
            'q' { }
            default { Start-Sleep -Milliseconds 500 }
        }
    } while ($choice -ne 'q')
}


function Manage-VpnTestUrls {
    :vpnUrlMenu do {
        try {
            $settings = Get-EtherShellSettings -CreateIfMissing
            $urls = @($settings['ethershell']['network']['vpnTestURL'])
        }
        catch {
            Write-Host "❌ Unable to read settings.json: $($_.Exception.Message)" -ForegroundColor Red
            Pause-EtherShell
            return
        }

        while ($urls.Count -lt 2) { $urls += '' }
        Show-SectionHeader -Title 'VPN Test URLs' -Subtitle 'EtherShell reports VPN Online when one configured endpoint responds'
        $u1 = if ([string]::IsNullOrWhiteSpace([string]$urls[0])) { '(not configured)' } else { [string]$urls[0] }
        $u2 = if ([string]::IsNullOrWhiteSpace([string]$urls[1])) { '(not configured)' } else { [string]$urls[1] }
        Write-Host "URL 1: $u1"
        Write-Host "URL 2: $u2"
        Write-Host
        Write-Host '[1] Set URL 1'
        Write-Host '[2] Set URL 2'
        Write-Host '[3] Clear Both URLs'
        Write-Host '[Q] Back'

        $choice = (Read-Host "`nGo").Trim().ToLowerInvariant()
        switch ($choice) {
            '1' { $slot = 0 }
            '2' { $slot = 1 }
            '3' {
                try {
                    Update-EtherShellSettings -UpdateAction {
                        param($latest)
                        $latest['ethershell']['network']['vpnTestURL'] = @('', '')
                        return $latest
                    } | Out-Null
                    Write-Host '✅ VPN test URLs cleared.' -ForegroundColor Green
                    Start-Sleep -Milliseconds 800
                }
                catch {
                    Write-Host "❌ Failed to update settings: $($_.Exception.Message)" -ForegroundColor Red
                    Pause-EtherShell
                }
                continue vpnUrlMenu
            }
            'q' { return }
            default {
                Write-Host '❌ Please enter 1, 2, 3, or Q.' -ForegroundColor Red
                Start-Sleep -Milliseconds 700
                continue vpnUrlMenu
            }
        }

        $newUrl = (Read-Host "Enter URL or hostname for slot $($slot + 1); ENTER clears it").Trim()
        if ($newUrl -and $newUrl -match '\s') {
            Write-Host '❌ URL/hostname must not contain spaces.' -ForegroundColor Red
            Start-Sleep -Milliseconds 900
            continue vpnUrlMenu
        }

        try {
            $newUrls = @([string]$urls[0], [string]$urls[1])
            $newUrls[$slot] = $newUrl
            Update-EtherShellSettings -UpdateAction {
                param($latest)
                $latest['ethershell']['network']['vpnTestURL'] = $newUrls
                return $latest
            } | Out-Null
            Write-Host '✅ VPN test URL saved.' -ForegroundColor Green
            Start-Sleep -Milliseconds 800
        }
        catch {
            Write-Host "❌ Failed to save VPN test URL: $($_.Exception.Message)" -ForegroundColor Red
            Pause-EtherShell
        }
    } while ($true)
}

function Get-EtherShellWindowDimensions {
    try {
        return [pscustomobject]@{
            Width  = [int][Console]::WindowWidth
            Height = [int][Console]::WindowHeight
        }
    }
    catch {
        return $null
    }
}

function Restart-EtherShell {
    $dimensions = Get-EtherShellWindowDimensions

    try {
        $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
        if ($dimensions) {
            $env:ETHERSHELL_RESTART_WIDTH = [string]$dimensions.Width
            $env:ETHERSHELL_RESTART_HEIGHT = [string]$dimensions.Height
        }

        $arguments = @(
            '-NoLogo',
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', ('"{0}"' -f $PSCommandPath)
        )

        Write-Host "`nRestarting EtherShell..." -ForegroundColor DarkCyan
        Start-Process -FilePath $pwsh -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -ErrorAction Stop | Out-Null
        exit
    }
    catch {
        Write-Host "❌ Could not restart EtherShell: $($_.Exception.Message)" -ForegroundColor Red
        Pause-EtherShell
    }
    finally {
        Remove-Item Env:ETHERSHELL_RESTART_WIDTH -ErrorAction SilentlyContinue
        Remove-Item Env:ETHERSHELL_RESTART_HEIGHT -ErrorAction SilentlyContinue
    }
}


function Start-ManualWindow {
    try {
        $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
        $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ManualOnly"
        Start-Process -FilePath $pwsh -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -ErrorAction Stop
    }
    catch {
        Write-Host "❌ Could not open the EtherShell manual: $($_.Exception.Message)" -ForegroundColor Red
        Pause-EtherShell
    }
}

function Show-Manual {
    try {
        $rawUi = $Host.UI.RawUI
        $rawUi.WindowTitle = 'EtherShell - Manual'

        # Keep the Manual window aligned with EtherShell's 100-column layout.
        $targetWidth = 100
        $windowSize = $rawUi.WindowSize
        $bufferSize = $rawUi.BufferSize

        if ($bufferSize.Width -lt $targetWidth) {
            $bufferSize.Width = $targetWidth
            $rawUi.BufferSize = $bufferSize
        }

        $windowSize.Width = $targetWidth
        $rawUi.WindowSize = $windowSize

        $bufferSize = $rawUi.BufferSize
        if ($bufferSize.Width -ne $targetWidth) {
            $bufferSize.Width = $targetWidth
            $rawUi.BufferSize = $bufferSize
        }
    }
    catch {
        # Some terminal hosts do not allow programmatic resizing.
    }

    $manualBorderColor = $script:NormalTextColor

    Clear-Host
    Write-Host '┌ EtherShell > Manual' -ForegroundColor $manualBorderColor
    Write-Host '└──────────────────────────────────────────────────────────────────────────────' -ForegroundColor $manualBorderColor
    Write-Host
    Write-Host ("EtherShell Manual - Version {0}" -f $script:ToolVersion)
    Write-Host 'Use the console scroll bar or mouse wheel to read the full manual.' -ForegroundColor DarkGray
    Write-Host

    $manual = @'
OVERVIEW
--------
EtherShell is a PowerShell-based Windows network utility for managing network
adapters, IPv4 configuration, reusable presets, Wi-Fi profiles, connectivity
checks, PowerShell maintenance, and ping diagnostics from one terminal
interface.

The main network-management mode normally runs with Administrator privileges.
The Manual and Ping Diagnostics use separate windows and do not request another
UAC elevation.


MAIN STATUS
-----------
The main status area shows the selected adapter and its current Windows state:

  Adapter       Selected/default network adapter
  Status        Adapter state reported by Windows
  Media State   Physical/link connection state
  Mode          DHCP or Static
  Preset        Preset matching the current live configuration
  IPv4 Address  Current IPv4 address
  Gateway       Current IPv4 default gateway
  DNS           Current IPv4 DNS server(s)
  Internet      Internet connectivity result
  VPN           Configured VPN endpoint result

Status colors:

  Status
    Up           -> Green
    Disconnected -> DarkRed
    Disabled     -> DarkGray
    Unknown      -> DarkYellow

  Media State
    Connected    -> Green
    Disconnected -> DarkRed
    Unknown      -> DarkYellow

  Internet
    Online       -> Green
    Offline      -> DarkRed

  VPN
    Online                       -> Green
    Connected / DNS unavailable  -> Yellow
    Offline                      -> DarkRed
    Not Configured               -> DarkGray
    Settings Error               -> Yellow

Preset colors remain separate from health/status colors:

  Exact preset match -> Cyan
  None               -> DarkGray
  Multiple           -> Yellow

Preset detection uses the actual Windows configuration, not only the last
preset selected.


MAIN MENU
---------
  [1] Network Configuration
  [2] Network Information
  [3] Network Tools
  [4] Wi-Fi
  [5] Settings
  [P] Presets     [R] Restart     [Q] Quit
  [M] Manual      [A] About/Info

[P] clears the screen and opens the same preset listing as
Settings -> Network Presets -> List Presets.
[R] restarts EtherShell and carries the current console dimensions into the
new EtherShell process where the terminal host permits resizing.
[Q] exits EtherShell while preserving the current console dimensions where the
terminal host permits programmatic window sizing.

Inside submenus, [Q] is used for Back / Cancel navigation.

A preset can also be applied directly at the main Go prompt:

  Go: home
  Go: HOME
  Go: id1
  Go: ID1
  Go: dhcp-auto
  Go: id0

Preset names and IDs are case-insensitive.


NETWORK CONFIGURATION
---------------------
[1] Select Network Adapter
    Selects the adapter EtherShell operates on and stores it as the default.

[2] Enable DHCP / Reapply DHCP Configuration
    Enables or reapplies DHCP on the selected adapter.

[3] Configure Static IPv4
    Applies a one-time static IPv4 configuration with IPv4 address, subnet,
    prefix, gateway, and DNS validation. At the final Apply prompt, Y or ENTER
    applies the configuration; N cancels without changing network settings.

[4] Apply Preset
    Applies a stored system or user preset.

[5] Enable / Disable Network Adapter
    Toggles the selected adapter and verifies the resulting state.

[6] Clear IPv4 Configuration
    Clears the selected adapter's IPv4 configuration.


NETWORK PRESETS
---------------
Open:
  Settings -> Network Presets

Available actions:
  [1] List Presets
  [2] Create Preset
  [3] Apply Preset
  [4] Delete Preset
  [5] Delete All Presets
  [Q] Back

EtherShell supports static IPv4 presets and DHCP presets with custom DNS.

The protected system preset is always present:

  id0  dhcp-auto

Properties:
  Type      : DHCP
  DNS mode  : Automatic / DHCP-provided
  Scope     : System
  Protected : Yes

id0 and dhcp-auto cannot be deleted, renamed, overwritten, or replaced.
Applying dhcp-auto targets the currently selected adapter.

User preset IDs begin at id1 and are globally unique. Pressing ENTER during ID
selection uses the smallest currently free ID. A manually entered occupied user
ID can be replaced only after confirmation.

New preset names are stored in lowercase and are globally unique. Reserved main
menu commands and idN syntax cannot be used as normal preset names.


DHCP DNS
--------
Open:
  Settings -> DHCP DNS

This manages the general DHCP DNS preference separately from reusable DHCP
presets. A custom DNS preference can be saved, applied immediately while DHCP
is active, or cleared to return to DHCP-provided DNS.


NETWORK INFORMATION
-------------------
[1] Selected Adapter Details
[2] All Network Adapters
[3] Full IP Configuration (ipconfig /all)
[4] Internet / VPN Status
[Q] Back

If a likely active VPN adapter is present (or the DNS server explicitly refuses
an internal-name lookup) but the configured VPN test hostname cannot be
resolved, EtherShell reports `Connected / DNS unavailable` instead of plain
`Offline`. This distinguishes a connected tunnel with broken VPN DNS from a
fully unreachable VPN endpoint.

If this state appears after EtherShell changed network configuration during the
current session, EtherShell additionally displays:

  VPN DNS resolution failed after network reconfiguration.
  A manual VPN reconnect may be required.

The message is advisory. EtherShell does not automatically disconnect or
reconnect third-party VPN software.


NETWORK TOOLS
-------------
Ping Diagnostics opens in a separate PowerShell window using Test-Connection.
It provides repeated measurements, a visual RTT graph, recent replies, target
changes, exports, and export cleanup.


WI-FI
-----
Main Wi-Fi menu:

  [1] Manage Known Networks
  [2] Connect to New Wi-Fi Network
  [3] Wi-Fi Adapter Status
  [4] Toggle Wi-Fi Interface
  [Q] Back

Visible and known networks use a compact table:

  No.    SSID                                         Security
  ----   -------------------------------------------- ------------------------------------
  [1]    Example-WPA2                                 WPA2-Personal / AES/CCMP
  [2]    Example-WPA3                                 WPA3-Personal / AES/CCMP
  [3]    Guest                                        Open

The Security column combines authentication mode and cipher information when
Windows exposes both values. Unknown is shown when Windows does not provide
enough information.

Manage Known Networks:

  [1] List Known Networks
  [2] Show Network Credentials
  [3] Connect to Known Network
  [4] Forget Network
  [Q] Back

Forget Network lists saved profiles, allows numeric selection, asks for
confirmation, and removes the selected Windows WLAN profile.

Connect to New Wi-Fi Network:

  [1] Search Visible Networks
  [2] Hidden / Manual SSID
  [Q] Back

Visible network search scans first without proactively asking for Location
Services. If Windows blocks WLAN scan/status access because location/privacy
permission is unavailable, EtherShell offers to open Windows Location settings.

For a new network, EtherShell asks for the password and whether Windows should
connect automatically when the network is in range. The choice is stored as a
Boolean and written to the Windows WLAN profile as automatic or manual
connection mode.

An empty password is supported for an open network. Password-protected profile
creation supports WPA2-Personal and WPA3-Personal. Connection attempts identify
the security mode being attempted.

Hidden / Manual SSID lets you enter the SSID directly without first performing
a visible-network scan.

Toggle Wi-Fi Interface enables or disables a selected Wi-Fi adapter and verifies
the resulting Windows adapter state.


SETTINGS
--------
[1] Network Presets
[2] Select / Set Default Adapter
[3] DHCP DNS
[4] VPN Test URLs
[5] About / Version
[6] Check / Update PowerShell
[7] Reset EtherShell Settings
[8] Vibrant Mode: On/Off
[Q] Back

VPN Test URLs accepts only [1], [2], [3], or [Q] at its menu prompt. Pressing
ENTER without a selection does not choose URL 1; EtherShell asks for a valid
menu choice.


VIBRANT MODE
------------
Vibrant Mode controls the highlight color used for the EtherShell ASCII logo,
the Networkwizardry title frame, and menu/submenu border lines. The text inside
the Networkwizardry title frame remains in the normal console text color.

When Vibrant Mode is On:
  - a random highlight color is selected on every EtherShell start
  - the selected color is used throughout that program session

When Vibrant Mode is Off:
  - the logo and border lines use the normal console text color
  - no random highlight color is selected

The Manual intentionally does not use the random Vibrant Mode highlight color.
Its formatting remains neutral and consistent.


RELEASE CHECK
-------------
During normal startup EtherShell checks the latest stable release published at:

  https://github.com/Gittegatt/EtherShell/releases

The release check runs after normal initialization completes.

If a newer release exists, EtherShell reports the available version and offers:

  [1] Visit the repository website
  [2] Skip this version
  [Q] Continue without opening the website

Skip this version stores the release tag in settings.json. The startup message
continues to report that the newer release exists, but the interactive prompt
remains paused until an even newer release is published.


ABOUT / PROJECT
---------------
GitHub profile:
  https://github.com/Gittegatt/

Project website:
  https://github.com/Gittegatt/EtherShell

License:
  EtherShell Source Available License 1.0

The license permits personal, educational, internal business, professional, and
commercial service use of the unmodified software, plus free redistribution of
complete unmodified copies under the license terms. Modification, derivative
works, rebranding, and sale of the software itself are prohibited. Read the
LICENSE file for the complete terms.


SETTINGS FILE
-------------
Persistent configuration is stored in:

  settings.json

It includes, among other values:
  - default adapter
  - last ping target
  - Vibrant Mode state
  - skipped release version
  - DHCP DNS preference
  - VPN test URLs
  - system and user network presets

EtherShell uses centralized settings access, locking, validated temporary-file
writes, and backup handling.


POWERSHELL REQUIREMENT
----------------------
EtherShell requires PowerShell 7.5.1 or newer.

Settings -> Check / Update PowerShell can compare the local installation with
the current stable Microsoft.PowerShell package available through WinGet.


QUICK EXAMPLES
--------------
Apply automatic DHCP and DHCP-provided DNS:
  Go: id0

Apply a preset named home:
  Go: home

Apply preset ID 3:
  Go: id3

Open this manual:
  Go: m

Quit EtherShell:
  Go: q

'@

    Write-Host $manual
    Write-Host
    Write-Host '┌──────────────────────────────────────────────────────────────────────────────' -ForegroundColor $manualBorderColor
    Write-Host ' Press any key to close the manual...' -ForegroundColor DarkGray
    Write-Host '└──────────────────────────────────────────────────────────────────────────────' -ForegroundColor $manualBorderColor

    try {
        [Console]::ReadKey($true) | Out-Null
    }
    catch {
        Read-Host 'Press ENTER to close' | Out-Null
    }
}


function Start-PingWindow {
    try {
        $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
        $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -PingOnly"
        Start-Process -FilePath $pwsh -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -ErrorAction Stop
    }
    catch {
        Write-Host "❌ Could not start Ping diagnostics: $($_.Exception.Message)" -ForegroundColor Red
        Pause-EtherShell
    }
}

function Show-NetworkConfigurationMenu {
    do {
        $adapter = Get-NetAdapter -Name $script:AdapterName -ErrorAction SilentlyContinue
        $toggleText = if ($adapter -and $adapter.Status -eq 'Disabled') { 'Enable Network Adapter' } else { 'Disable Network Adapter' }

        $dhcpEnabled = $false
        if ($adapter) {
            try {
                $ipv4Interface = Get-NetIPInterface -InterfaceAlias $script:AdapterName -AddressFamily IPv4 -ErrorAction Stop |
                    Select-Object -First 1
                $dhcpEnabled = $ipv4Interface -and $ipv4Interface.Dhcp -eq 'Enabled'
            }
            catch {
                $dhcpEnabled = $false
            }
        }
        $dhcpText = if ($dhcpEnabled) { 'Reapply DHCP Configuration (active)' } else { 'Enable DHCP' }

        Show-SectionHeader -Title 'Network Configuration' -Subtitle "Selected adapter: $script:AdapterName"
        Write-Host '┌' -ForegroundColor $script:BannerColor
        foreach ($entry in @(
                '[1] Select Network Adapter',
                "[2] $dhcpText",
                '[3] Configure Static IPv4',
                '[4] Apply Preset',
                "[5] $toggleText",
                '[6] Clear IPv4 Configuration'
            )) {
            Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
            Write-Host " $entry"
        }
        Write-Host '├──────────────────────────────────────────────' -ForegroundColor $script:BannerColor
        Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
        Write-Host ' [Q] Back'
        Write-Host '└──────────────────────────────────────────────' -ForegroundColor $script:BannerColor

        $choice = (Read-Host "`nGo").Trim().ToLowerInvariant()
        switch ($choice) {
            '1' { Set-ActiveAdapter }
            '2' { Set-DHCP }
            '3' { Set-StaticIP }
            '4' { Apply-Settings -Adapter $script:AdapterName }
            '5' { Toggle-NetworkInterface -InterfaceName $script:AdapterName }
            '6' { Clear-IPConfig -AdapterName $script:AdapterName }
            'q' { }
            default { Start-Sleep -Milliseconds 500 }
        }
    } while ($choice -ne 'q')
}


function Show-NetworkInformationMenu {
    do {
        Show-SectionHeader -Title 'Network Information' -Subtitle "Selected adapter: $script:AdapterName"
        Write-Host '┌' -ForegroundColor $script:BannerColor
        foreach ($entry in @(
                '[1] Selected Adapter Details',
                '[2] All Network Adapters',
                '[3] Full IP Configuration (ipconfig /all)',
                '[4] Internet / VPN Status'
            )) {
            Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
            Write-Host " $entry"
        }
        Write-Host '├──────────────────────────────────────────────' -ForegroundColor $script:BannerColor
        Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
        Write-Host ' [Q] Back'
        Write-Host '└──────────────────────────────────────────────' -ForegroundColor $script:BannerColor

        $choice = (Read-Host "`nGo").Trim().ToLowerInvariant()
        switch ($choice) {
            '1' { Show-NetworkOverview -ActiveAdapter $script:AdapterName -HideIPv6DNS -OnlyActive }
            '2' { Show-NetworkOverview -ActiveAdapter $script:AdapterName }
            '3' { IPConfigAll }
            '4' { Show-ConnectivityStatus }
            'q' { }
            default { Start-Sleep -Milliseconds 500 }
        }
    } while ($choice -ne 'q')
}

function Show-NetworkToolsMenu {
    do {
        Show-SectionHeader -Title 'Network Tools'
        Write-Host '┌' -ForegroundColor $script:BannerColor
        Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
        Write-Host ' [1] Ping Diagnostics'
        Write-Host '├──────────────────────────────────────────────' -ForegroundColor $script:BannerColor
        Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
        Write-Host ' [Q] Back'
        Write-Host '└──────────────────────────────────────────────' -ForegroundColor $script:BannerColor

        $choice = (Read-Host "`nGo").Trim().ToLowerInvariant()
        switch ($choice) {
            '1' { Start-PingWindow }
            'q' { }
            default { Start-Sleep -Milliseconds 500 }
        }
    } while ($choice -ne 'q')
}

function Show-WiFiMenu {
    do {
        Show-SectionHeader -Title 'Wi-Fi'
        Write-Host '┌' -ForegroundColor $script:BannerColor
        foreach ($entry in @(
                '[1] Manage Known Networks',
                '[2] Connect to New Wi-Fi Network',
                '[3] Wi-Fi Adapter Status',
                '[4] Toggle Wi-Fi Interface'
            )) {
            Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
            Write-Host " $entry"
        }
        Write-Host '├──────────────────────────────────────────────' -ForegroundColor $script:BannerColor
        Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
        Write-Host ' [Q] Back'
        Write-Host '└──────────────────────────────────────────────' -ForegroundColor $script:BannerColor

        $choice = (Read-Host "`nGo").Trim().ToLowerInvariant()
        switch ($choice) {
            '1' { Show-ManageKnownNetworksMenu }
            '2' { Show-ConnectNewWiFiMenu }
            '3' { Show-WiFiAdapterStatus }
            '4' { Toggle-WiFiInterface }
            'q' { }
            default { Start-Sleep -Milliseconds 500 }
        }
    } while ($choice -ne 'q')
}


function Show-SettingsMenu {
    do {
        $vibrantState = if (Get-VibrantModeEnabled) { 'On' } else { 'Off' }

        Show-SectionHeader -Title 'Settings' -Subtitle "Default / selected adapter: $script:AdapterName"
        Write-Host '┌' -ForegroundColor $script:BannerColor
        foreach ($entry in @(
                '[1] Network Presets',
                '[2] Select / Set Default Adapter',
                '[3] DHCP DNS',
                '[4] VPN Test URLs',
                '[5] About / Version',
                '[6] Check / Update PowerShell',
                '[7] Reset EtherShell Settings',
                "[8] Vibrant Mode: $vibrantState"
            )) {
            Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
            Write-Host " $entry"
        }
        Write-Host '├──────────────────────────────────────────────' -ForegroundColor $script:BannerColor
        Write-Host '│' -NoNewline -ForegroundColor $script:BannerColor
        Write-Host ' [Q] Back'
        Write-Host '└──────────────────────────────────────────────' -ForegroundColor $script:BannerColor

        $choice = (Read-Host "`nGo").Trim().ToLowerInvariant()
        switch ($choice) {
            '1' { PersistentSettings }
            '2' { Set-ActiveAdapter }
            '3' { Manage-DhcpDnsSetting }
            '4' { Manage-VpnTestUrls }
            '5' { Show-About }
            '6' { CheckPS }
            '7' { Delete-PersistentSettingsFile }
            '8' { Toggle-VibrantMode }
            'q' { }
            default { Start-Sleep -Milliseconds 500 }
        }
    } while ($choice -ne 'q')
}


function Show-About {
    $about = @"

 EtherShell
 PowerShell Network Utility

 Version             : $script:ToolVersion
 Required PowerShell : $script:RequiredVersion or newer
 Current PowerShell  : $($PSVersionTable.PSVersion)
 GitHub Profile      : $script:ProjectProfileUrl
 Project Website     : $script:ProjectUrl
 License             : $script:LicenseName

 EtherShell is designed to simplify repetitive Windows network tasks with
 reusable presets, Wi-Fi management, VPN endpoint/DNS diagnostics, network
 tools, and a fast terminal workflow for IT users and power users.

"@

    Clear-Host
    Show-SectionHeader -Title 'About / Info'
    Write-Host $about
    Pause-EtherShell -Message 'Press any key to return to the main menu...'
}


function ConvertTo-ComparablePowerShellVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$VersionText
    )

    $match = [regex]::Match($VersionText, '(?<!\d)(\d+(?:\.\d+){1,3})(?!\d)')
    if (-not $match.Success) {
        return $null
    }

    try {
        $parts = @($match.Groups[1].Value.Split('.') | ForEach-Object { [int]$_ })
        while ($parts.Count -lt 4) {
            $parts += 0
        }

        return [version]::new($parts[0], $parts[1], $parts[2], $parts[3])
    }
    catch {
        return $null
    }
}

function Format-PowerShellVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [version]$Version
    )

    if ($Version.Revision -gt 0) {
        return $Version.ToString(4)
    }

    if ($Version.Build -ge 0) {
        return ('{0}.{1}.{2}' -f $Version.Major, $Version.Minor, $Version.Build)
    }

    return ('{0}.{1}' -f $Version.Major, $Version.Minor)
}

function Get-WingetPowerShellCatalogVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$WingetPath
    )

    $output = @(& $WingetPath search --id Microsoft.PowerShell --exact --source winget --accept-source-agreements --disable-interactivity 2>&1)
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        return [pscustomobject]@{
            Success  = $false
            Version  = $null
            ExitCode = $exitCode
            Output   = ($output -join [Environment]::NewLine)
        }
    }

    $text = $output -join [Environment]::NewLine
    $match = [regex]::Match(
        $text,
        'Microsoft\.PowerShell\s+([0-9]+(?:\.[0-9]+){1,3}(?:-[0-9A-Za-z.-]+)?)',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if (-not $match.Success) {
        return [pscustomobject]@{
            Success  = $false
            Version  = $null
            ExitCode = $exitCode
            Output   = $text
        }
    }

    $version = ConvertTo-ComparablePowerShellVersion -VersionText $match.Groups[1].Value
    if ($null -eq $version) {
        return [pscustomobject]@{
            Success  = $false
            Version  = $null
            ExitCode = $exitCode
            Output   = $text
        }
    }

    return [pscustomobject]@{
        Success  = $true
        Version  = $version
        ExitCode = $exitCode
        Output   = $text
    }
}

function Test-PowerShellManagedByWinget {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$WingetPath
    )

    $output = @(& $WingetPath list --id Microsoft.PowerShell --exact --source winget --accept-source-agreements --disable-interactivity 2>&1)
    $text = $output -join [Environment]::NewLine

    return [regex]::IsMatch(
        $text,
        'Microsoft\.PowerShell\s+[0-9]+(?:\.[0-9]+){1,3}',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
}

function Test-PowerShellWixInstallerAvailable {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$WingetPath
    )

    $null = & $WingetPath show --id Microsoft.PowerShell --exact --source winget --installer-type wix --accept-source-agreements --disable-interactivity 2>&1
    return $LASTEXITCODE -eq 0
}

function CheckPS {
    Clear-Host
    Write-Host '┌ EtherShell > PowerShell' -ForegroundColor $script:BannerColor
    Write-Host '└──────────────────────────────────────────────' -ForegroundColor $script:BannerColor
    Write-Host

    $currentVersion = ConvertTo-ComparablePowerShellVersion -VersionText $PSVersionTable.PSVersion.ToString()
    if ($null -eq $currentVersion) {
        Write-Host '❌ Could not determine the current PowerShell version.' -ForegroundColor Red
        Pause-EtherShell
        return
    }

    $pwshExecutable = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path -LiteralPath $pwshExecutable)) {
        $pwshExecutable = $PSHOME
    }

    $wingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $wingetCommand) {
        $wingetCommand = Get-Command winget -ErrorAction SilentlyContinue
    }

    Write-Host ('Installed version : {0}' -f (Format-PowerShellVersion -Version $currentVersion))
    Write-Host ('Executable        : {0}' -f $pwshExecutable)

    if (-not $wingetCommand) {
        Write-Host 'Latest version    : Unknown'
        Write-Host 'WinGet managed    : Unknown'
        Write-Host
        Write-Host "⚠️ 'winget' is not available. EtherShell cannot check the PowerShell catalog." -ForegroundColor Yellow
        Pause-EtherShell
        return
    }

    Write-Host 'Checking WinGet catalog...' -ForegroundColor DarkGray
    $catalog = Get-WingetPowerShellCatalogVersion -WingetPath $wingetCommand.Source

    if (-not $catalog.Success) {
        Write-Host 'Latest version    : Unknown'
        Write-Host 'WinGet managed    : Unknown'
        Write-Host
        Write-Host '❌ Could not determine the latest PowerShell version from WinGet.' -ForegroundColor Red
        if ($catalog.ExitCode -ne 0) {
            Write-Host "   WinGet exit code: $($catalog.ExitCode)" -ForegroundColor DarkGray
        }
        Pause-EtherShell
        return
    }

    $latestVersion = $catalog.Version
    $isWingetManaged = Test-PowerShellManagedByWinget -WingetPath $wingetCommand.Source

    # Redraw the compact status after the catalog checks so WinGet progress output
    # cannot leave the screen in an inconsistent state.
    Clear-Host
    Write-Host '┌ EtherShell > PowerShell' -ForegroundColor $script:BannerColor
    Write-Host '└──────────────────────────────────────────────' -ForegroundColor $script:BannerColor
    Write-Host
    Write-Host ('Installed version : {0}' -f (Format-PowerShellVersion -Version $currentVersion))
    Write-Host ('Latest version    : {0}' -f (Format-PowerShellVersion -Version $latestVersion))
    Write-Host ('Executable        : {0}' -f $pwshExecutable)
    Write-Host ('WinGet managed    : {0}' -f $(if ($isWingetManaged) { 'Yes' } else { 'No' }))
    Write-Host

    if ($currentVersion -eq $latestVersion) {
        Write-Host '✅ PowerShell is up to date.' -ForegroundColor Green
        if (-not $isWingetManaged) {
            Write-Host 'ℹ️ This PowerShell installation is not registered as Microsoft.PowerShell in WinGet.' -ForegroundColor DarkGray
            Write-Host '   No action is required while the installed version is current.' -ForegroundColor DarkGray
        }
        Pause-EtherShell
        return
    }

    if ($currentVersion -gt $latestVersion) {
        Write-Host 'ℹ️ The running PowerShell version is newer than the stable version in the WinGet catalog.' -ForegroundColor DarkCyan
        Write-Host '   No update is required.' -ForegroundColor DarkGray
        Pause-EtherShell
        return
    }

    Write-Host '⬆️ A newer PowerShell version is available.' -ForegroundColor Yellow
    Write-Host

    if ($isWingetManaged) {
        if (-not (Confirm-EtherShellAction -Prompt ('Update PowerShell to {0} using WinGet?' -f (Format-PowerShellVersion -Version $latestVersion)))) {
            Write-Host '↩️ Update cancelled.' -ForegroundColor Yellow
            Start-Sleep -Milliseconds 800
            return
        }

        & $wingetCommand.Source upgrade --id Microsoft.PowerShell --exact --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity
        $wingetExitCode = $LASTEXITCODE

        if ($wingetExitCode -eq 0) {
            Write-Host "`n✅ WinGet completed the PowerShell update command." -ForegroundColor Green
            Write-Host '   Restart EtherShell to use the updated PowerShell version.' -ForegroundColor DarkGray
        }
        else {
            Write-Host "`n❌ WinGet update failed with exit code $wingetExitCode." -ForegroundColor Red
        }

        Pause-EtherShell
        return
    }

    Write-Host 'ℹ️ The current PowerShell installation is not managed by WinGet.' -ForegroundColor DarkGray
    Write-Host '   EtherShell will not use a normal WinGet upgrade command for this installation.' -ForegroundColor DarkGray
    Write-Host

    $wixAvailable = Test-PowerShellWixInstallerAvailable -WingetPath $wingetCommand.Source
    if (-not $wixAvailable) {
        Write-Host '⚠️ No MSI/WiX installer is available for the latest catalog version.' -ForegroundColor Yellow
        Write-Host '   EtherShell will not fall back to MSIX automatically, to avoid creating a parallel installation.' -ForegroundColor DarkGray
        Pause-EtherShell
        return
    }

    Write-Host 'An MSI/WiX installer is available for the newer version.' -ForegroundColor DarkCyan
    Write-Host 'EtherShell can launch that installer explicitly instead of WinGet''s default MSIX package.' -ForegroundColor DarkGray
    Write-Host

    if (-not (Confirm-EtherShellAction -Prompt ('Install PowerShell {0} using WinGet MSI/WiX?' -f (Format-PowerShellVersion -Version $latestVersion)))) {
        Write-Host '↩️ Update cancelled.' -ForegroundColor Yellow
        Start-Sleep -Milliseconds 800
        return
    }

    & $wingetCommand.Source install --id Microsoft.PowerShell --exact --source winget --installer-type wix --accept-source-agreements --accept-package-agreements --disable-interactivity
    $wingetExitCode = $LASTEXITCODE

    if ($wingetExitCode -eq 0) {
        Write-Host "`n✅ WinGet completed the MSI/WiX installation command." -ForegroundColor Green
        Write-Host '   Restart EtherShell and run this check again to confirm the installed version.' -ForegroundColor DarkGray
    }
    else {
        Write-Host "`n❌ WinGet MSI/WiX installation failed with exit code $wingetExitCode." -ForegroundColor Red
    }

    Pause-EtherShell
}

function EndScript {
    $dimensions = Get-EtherShellWindowDimensions

    Clear-Host
    Write-Host "`n Exiting EtherShell" -ForegroundColor $script:BannerColor -NoNewline
    for ($i = 1; $i -le 3; $i++) {
        Start-Sleep -Milliseconds 250
        Write-Host '.' -ForegroundColor $script:BannerColor -NoNewline
    }
    Start-Sleep -Milliseconds 400
    Write-Host

    if ($dimensions) {
        try {
            [Console]::SetWindowSize($dimensions.Width, $dimensions.Height)
        }
        catch {
            # Some terminal hosts manage their own dimensions.
        }
    }

    exit
}

# ────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────
try {
    if ($ManualOnly) {
        Show-Manual
        return
    }

    if (-not (Initialize-EtherShellStartup)) {
        Pause-EtherShell -Message 'Press any key to exit...'
        return
    }

    if ($PingOnly) {
        Write-Host '▶️ Running in Ping-Only mode...' -ForegroundColor DarkCyan
        Start-Ping
        return
    }

    do {
        try { $Host.UI.RawUI.WindowTitle = 'EtherShell' } catch {}

        $choice = Show-Menu
        if ($null -eq $choice) { continue }
        $choice = $choice.Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($choice)) { continue }

        switch ($choice) {
            '1' { Show-NetworkConfigurationMenu }
            '2' { Show-NetworkInformationMenu }
            '3' { Show-NetworkToolsMenu }
            '4' { Show-WiFiMenu }
            '5' { Show-SettingsMenu }
            'a' { Show-About }
            'm' { Start-ManualWindow }
            'p' { Show-PresetsQuickView }
            'r' { Restart-EtherShell }
            'q' { EndScript }
            default { Invoke-MainMenuPreset -Name $choice }
        }
    } while ($true)
}
catch {
    $fatalMessage = $_.Exception.Message
    $fatalDetails = ($_ | Out-String).Trim()
    $logPath = Join-Path $PSScriptRoot 'EtherShell-startup-error.log'

    try {
        @(
            ('Timestamp: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
            ('PowerShell: {0} ({1})' -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition),
            ('Script: {0}' -f $PSCommandPath),
            '',
            $fatalDetails
        ) | Set-Content -LiteralPath $logPath -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch {}

    Write-Host
    Write-Host '❌ EtherShell encountered a fatal error.' -ForegroundColor Red
    Write-Host "   $fatalMessage" -ForegroundColor Yellow
    Write-Host "   Log: $logPath" -ForegroundColor DarkGray
    Write-Host

    try {
        [Console]::ReadKey($true) | Out-Null
    }
    catch {
        Read-Host 'Press ENTER to close' | Out-Null
    }
}
