<#
Claude Desktop 轻量汉化脚本
作者/开源地址:
  GitHub: https://github.com/GMYXDS/claude-desktop-zh-simple
  Gitee : https://gitee.com/GMYXDS/claude-desktop-zh-simple

本工具永久免费。请不要从任何倒卖、收费渠道购买。
#>

param(
    [ValidateSet("menu", "status", "backup", "patch", "restore", "missing", "update")]
    [string]$Action = "menu",

    [string]$ResourcesPath = "",

    [switch]$Yes,

    [switch]$NoElevate,

    [switch]$SkipUpdateCheck
)

$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
    $OutputEncoding = [Console]::OutputEncoding
} catch {
}

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ProjectRoot = Split-Path -Parent $ScriptDir
$TranslationMemoryPath = Join-Path $ProjectRoot "translation_memory.json"
$VersionPath = Join-Path $ProjectRoot "version.json"
$BackupRoot = Join-Path $ProjectRoot "backups"
$ReportRoot = Join-Path $ProjectRoot "reports"
$StateRoot = Join-Path $ProjectRoot "state"

$ProjectGithub = "https://github.com/GMYXDS/claude-desktop-zh-simple"
$ProjectGitee = "https://gitee.com/GMYXDS/claude-desktop-zh-simple"
$RemoteFileSources = @(
    [ordered]@{ Name = "GitHub main"; BaseUrl = "https://raw.githubusercontent.com/GMYXDS/claude-desktop-zh-simple/main" },
    [ordered]@{ Name = "Gitee main"; BaseUrl = "https://gitee.com/GMYXDS/claude-desktop-zh-simple/raw/main" },
    [ordered]@{ Name = "GitHub master"; BaseUrl = "https://raw.githubusercontent.com/GMYXDS/claude-desktop-zh-simple/master" },
    [ordered]@{ Name = "Gitee master"; BaseUrl = "https://gitee.com/GMYXDS/claude-desktop-zh-simple/raw/master" }
)

$ResourceFiles = @(
    "en-US.json",
    "ion-dist\i18n\en-US.json",
    "ion-dist\i18n\dynamic\en-US.json"
)

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "==== $Title ===="
}

function ConvertTo-CommandLineArgument {
    param([string]$Value)
    if ($null -eq $Value) {
        return '""'
    }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Elevated {
    $argsList = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        (ConvertTo-CommandLineArgument -Value $PSCommandPath),
        "-Action",
        $Action
    )

    if ($ResourcesPath) {
        $argsList += @("-ResourcesPath", (ConvertTo-CommandLineArgument -Value $ResourcesPath))
    }
    if ($Yes) {
        $argsList += "-Yes"
    }
    if ($SkipUpdateCheck) {
        $argsList += "-SkipUpdateCheck"
    }

    Write-Host "需要管理员权限来修改 WindowsApps 里的 Claude 资源文件。"
    Start-Process -FilePath "powershell.exe" -ArgumentList ($argsList -join " ") -WorkingDirectory $ProjectRoot -Verb RunAs
    exit 0
}

if (-not $NoElevate -and -not (Test-IsAdministrator)) {
    Restart-Elevated
}

function Get-SafeName {
    param([string]$Name)
    return ($Name -replace '[\\/:*?"<>|]', "_")
}

function Get-DictionaryCount {
    param([object]$Dictionary)
    if ($null -eq $Dictionary) {
        return 0
    }
    return [int]$Dictionary.psbase.Count
}

function New-StringDictionary {
    return New-Object 'System.Collections.Generic.Dictionary[string,string]'
}

function Test-DictionaryContainsKey {
    param(
        [object]$Dictionary,
        [string]$Key
    )

    if ($null -eq $Dictionary -or $Dictionary -isnot [System.Collections.IDictionary]) {
        return $false
    }

    if ($Dictionary.PSObject.Methods["ContainsKey"] -and $Dictionary.ContainsKey($Key)) {
        return $true
    }

    if ($Dictionary.PSObject.Methods["Contains"] -and $Dictionary.Contains($Key)) {
        return $true
    }

    foreach ($entry in $Dictionary.GetEnumerator()) {
        if ([string]$entry.Key -eq $Key) {
            return $true
        }
    }

    return $false
}

function Join-Under {
    param(
        [string]$Root,
        [string]$RelativePath
    )
    return Join-Path $Root $RelativePath
}

function Get-NormalizedFullPath {
    param([string]$Path)
    return [IO.Path]::GetFullPath($Path)
}

function Get-ProjectRelativePath {
    param([string]$Path)

    $fullPath = Get-NormalizedFullPath -Path $Path
    $rootPath = (Get-NormalizedFullPath -Path $ProjectRoot).TrimEnd('\', '/')
    $prefix = $rootPath + [IO.Path]::DirectorySeparatorChar

    if ($fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($prefix.Length)
    }

    return $fullPath
}

function Resolve-ProjectRelativePath {
    param([string]$Path)

    if ([IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $ProjectRoot $Path
}

function Read-Utf8Text {
    param([string]$Path)
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
}

function Write-Utf8NoBomText {
    param(
        [string]$Path,
        [string]$Text
    )
    $encoding = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, ($Text.TrimEnd() + [Environment]::NewLine), $encoding)
}

function Test-ConvertFromJsonAsHashtable {
    $cmd = Get-Command ConvertFrom-Json -ErrorAction SilentlyContinue
    return ($cmd -and $cmd.Parameters.ContainsKey("AsHashtable"))
}

function Get-LegacyJsonSerializer {
    if ($script:JsonSerializer) {
        return $script:JsonSerializer
    }

    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = [int]::MaxValue
    $serializer.RecursionLimit = 200
    $script:JsonSerializer = $serializer
    return $script:JsonSerializer
}

function ConvertTo-JsonText {
    param([object]$Value)
    $json = $Value | ConvertTo-Json -Depth 100 -Compress
    return Restore-JsonReadableEscapes -Json $json
}

function Restore-JsonReadableEscapes {
    param([string]$Json)

    $escapeMap = @{
        "0026" = "&"
        "0027" = "'"
        "003c" = "<"
        "003d" = "="
        "003e" = ">"
    }

    return [regex]::Replace(
        $Json,
        "\\u(0026|0027|003[cCdDeE])",
        {
            param($match)

            $slashCount = 0
            for ($i = $match.Index - 1; $i -ge 0 -and $Json[$i] -eq "\"; $i--) {
                $slashCount++
            }

            if (($slashCount % 2) -ne 0) {
                return $match.Value
            }

            $code = $match.Groups[1].Value.ToLowerInvariant()
            if ($escapeMap.ContainsKey($code)) {
                return $escapeMap[$code]
            }

            return $match.Value
        }
    )
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )
    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $json = ConvertTo-JsonText -Value $Value
    Write-Utf8NoBomText -Path $Path -Text $json
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "文件不存在: $Path"
    }
    $text = Read-Utf8Text -Path $Path
    if (Test-ConvertFromJsonAsHashtable) {
        return ($text | ConvertFrom-Json -AsHashtable)
    }

    return (Get-LegacyJsonSerializer).DeserializeObject($text)
}

function Get-JsonValue {
    param(
        [object]$Object,
        [string]$Key,
        [string]$Default = ""
    )

    if ($null -eq $Object) {
        return $Default
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.ContainsKey($Key)) {
            return [string]$Object[$Key]
        }

        foreach ($entry in $Object.GetEnumerator()) {
            if ([string]$entry.Key -eq $Key) {
                return [string]$entry.Value
            }
        }
    }

    $prop = $Object.PSObject.Properties[$Key]
    if ($prop) {
        return [string]$prop.Value
    }

    return $Default
}

function Test-VersionString {
    param([string]$Value)
    return ($Value -match '^\d{14}$')
}

function Compare-VersionString {
    param(
        [string]$Left,
        [string]$Right
    )

    if (-not (Test-VersionString -Value $Left)) {
        $Left = "0"
    }
    if (-not (Test-VersionString -Value $Right)) {
        $Right = "0"
    }

    $leftNumber = [int64]$Left
    $rightNumber = [int64]$Right
    return $leftNumber.CompareTo($rightNumber)
}

function Read-LocalVersionInfo {
    if (-not (Test-Path -LiteralPath $VersionPath)) {
        return [ordered]@{
            windows_tool       = "0"
            translation_memory = "0"
        }
    }

    $obj = Read-JsonFile -Path $VersionPath
    return [ordered]@{
        windows_tool       = Get-JsonValue -Object $obj -Key "windows_tool" -Default "0"
        translation_memory = Get-JsonValue -Object $obj -Key "translation_memory" -Default "0"
    }
}

function Write-LocalVersionInfo {
    param([object]$VersionInfo)
    Write-JsonFile -Path $VersionPath -Value ([ordered]@{
        windows_tool       = Get-JsonValue -Object $VersionInfo -Key "windows_tool" -Default "0"
        translation_memory = Get-JsonValue -Object $VersionInfo -Key "translation_memory" -Default "0"
    })
}

function Get-InvokeWebRequestParameters {
    param(
        [string]$Url,
        [int]$TimeoutSec = 8
    )

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    } catch {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        } catch {
        }
    }

    $params = @{
        Uri        = $Url
        TimeoutSec = $TimeoutSec
        ErrorAction = "Stop"
    }

    $cmd = Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Parameters.ContainsKey("UseBasicParsing")) {
        $params["UseBasicParsing"] = $true
    }

    return $params
}

function Get-RemoteFileUrl {
    param(
        [object]$Source,
        [string]$RelativePath
    )
    return ($Source.BaseUrl.TrimEnd("/") + "/" + $RelativePath.TrimStart("/"))
}

function Get-RemoteVersionInfo {
    $lastError = $null

    foreach ($source in $RemoteFileSources) {
        $url = Get-RemoteFileUrl -Source $source -RelativePath "version.json"
        try {
            Write-Host "正在检查远程版本: $($source.Name)"
            $params = Get-InvokeWebRequestParameters -Url $url
            $response = Invoke-WebRequest @params
            $text = [string]$response.Content
            $obj = $text | ConvertFrom-Json

            $windowsTool = [string]$obj.windows_tool
            $translationMemory = [string]$obj.translation_memory
            if (-not (Test-VersionString -Value $windowsTool) -or -not (Test-VersionString -Value $translationMemory)) {
                throw "远程 version.json 格式不正确。"
            }

            return [pscustomobject]@{
                Source             = $source.Name
                VersionUrl         = $url
                WindowsTool        = $windowsTool
                TranslationMemory  = $translationMemory
            }
        } catch {
            $lastError = $_.Exception.Message
            Write-Host "远程版本检查失败: $($source.Name) ($lastError)"
        }
    }

    throw "无法从 GitHub/Gitee 获取远程 version.json。最后错误: $lastError"
}

function Download-RemoteTranslationMemory {
    param([string]$ExpectedVersion)

    $lastError = $null
    foreach ($source in $RemoteFileSources) {
        $url = Get-RemoteFileUrl -Source $source -RelativePath "translation_memory.json"
        $tempFile = Join-Path ([IO.Path]::GetTempPath()) ("claude-desktop-zh-simple-memory-{0}.json" -f ([Guid]::NewGuid().ToString("N")))

        try {
            Write-Host "正在下载新版记忆库: $($source.Name)"
            $params = Get-InvokeWebRequestParameters -Url $url -TimeoutSec 30
            $params["OutFile"] = $tempFile
            Invoke-WebRequest @params

            [void](Read-TranslationMemoryFromPath -Path $tempFile)
            Copy-Item -LiteralPath $tempFile -Destination $TranslationMemoryPath -Force

            $localVersion = Read-LocalVersionInfo
            $localVersion["translation_memory"] = $ExpectedVersion
            Write-LocalVersionInfo -VersionInfo $localVersion

            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            Write-Host "记忆库已更新到版本: $ExpectedVersion"
            return [pscustomobject]@{
                Source = $source.Name
                Url    = $url
            }
        } catch {
            $lastError = $_.Exception.Message
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            Write-Host "下载记忆库失败: $($source.Name) ($lastError)"
        }
    }

    throw "无法从 GitHub/Gitee 下载 translation_memory.json。最后错误: $lastError"
}

function Get-FileSha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Read-TranslationMemoryFromPath {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "未找到 translation_memory.json: $Path"
    }

    $obj = Read-JsonFile -Path $Path
    $map = New-StringDictionary

    if ($obj -isnot [System.Collections.IDictionary]) {
        throw "translation_memory.json 必须是 JSON 对象。"
    }

    foreach ($entry in $obj.GetEnumerator()) {
        $key = [string]$entry.Key
        $value = $entry.Value
        if ($null -ne $value -and $value -is [string] -and -not [string]::IsNullOrWhiteSpace($value)) {
            $map[$key] = [string]$value
        }
    }

    if ((Get-DictionaryCount -Dictionary $map) -eq 0) {
        throw "translation_memory.json 没有可用的英文到中文映射。"
    }

    return $map
}

function Read-TranslationMemory {
    return Read-TranslationMemoryFromPath -Path $TranslationMemoryPath
}

function Get-VersionFromClaudePath {
    param([string]$InstallLocation)
    $leaf = Split-Path -Leaf $InstallLocation
    if ($leaf -match '^Claude_(?<version>[0-9]+(\.[0-9]+){1,3})_') {
        try {
            return [version]$Matches.version
        } catch {
            return $null
        }
    }
    if ($leaf -match '^(?<version>[0-9]+(\.[0-9]+){1,3})$') {
        try {
            return [version]$Matches.version
        } catch {
            return $null
        }
    }
    return $null
}

function New-ClaudeInfo {
    param(
        [string]$InstallLocation,
        [string]$Source,
        [object]$Package
    )

    $resources = Join-Path $InstallLocation "app\resources"
    $version = $null
    $packageName = Split-Path -Leaf $InstallLocation

    if ($Package -and $Package.Version) {
        try {
            $version = [version]$Package.Version
        } catch {
            $version = Get-VersionFromClaudePath -InstallLocation $InstallLocation
        }
        if ($Package.PackageFullName) {
            $packageName = $Package.PackageFullName
        }
    } else {
        $version = Get-VersionFromClaudePath -InstallLocation $InstallLocation
    }

    return [pscustomobject]@{
        InstallLocation = $InstallLocation
        ResourcesPath   = $resources
        PackageName     = $packageName
        Version         = $version
        Source          = $Source
    }
}

function Resolve-ManualClaudeInfo {
    param([string]$ManualResourcesPath)

    $resolved = (Resolve-Path -LiteralPath $ManualResourcesPath).ProviderPath
    $resources = $resolved
    $installLocation = $resolved

    if ((Split-Path -Leaf $resources) -ieq "resources") {
        $appDir = Split-Path -Parent $resources
        if ((Split-Path -Leaf $appDir) -ieq "app") {
            $installLocation = Split-Path -Parent $appDir
        }
    }

    $info = New-ClaudeInfo -InstallLocation $installLocation -Source "manual" -Package $null
    $info.ResourcesPath = $resources
    return $info
}

function Resolve-ClaudeInstall {
    if ($ResourcesPath) {
        return Resolve-ManualClaudeInfo -ManualResourcesPath $ResourcesPath
    }

    $candidates = @()
    $seen = @{}

    $packageQueries = @(
        { Get-AppxPackage -Name "Claude" -ErrorAction SilentlyContinue },
        { Get-AppxPackage -AllUsers -Name "Claude" -ErrorAction SilentlyContinue }
    )

    foreach ($query in $packageQueries) {
        try {
            foreach ($pkg in & $query) {
                if ($pkg.InstallLocation -and -not $seen.ContainsKey($pkg.InstallLocation)) {
                    $seen[$pkg.InstallLocation] = $true
                    $info = New-ClaudeInfo -InstallLocation $pkg.InstallLocation -Source "Get-AppxPackage" -Package $pkg
                    if (Test-Path -LiteralPath $info.ResourcesPath) {
                        $candidates += $info
                    }
                }
            }
        } catch {
            # Some systems restrict -AllUsers. Fall back to scanning WindowsApps.
        }
    }

    $windowsApps = Join-Path $env:ProgramFiles "WindowsApps"
    if (Test-Path -LiteralPath $windowsApps) {
        try {
            foreach ($dir in Get-ChildItem -LiteralPath $windowsApps -Directory -Filter "Claude_*__pzs8sxrjxfjjc" -ErrorAction SilentlyContinue) {
                if (-not $seen.ContainsKey($dir.FullName)) {
                    $seen[$dir.FullName] = $true
                    $info = New-ClaudeInfo -InstallLocation $dir.FullName -Source "WindowsApps scan" -Package $null
                    if (Test-Path -LiteralPath $info.ResourcesPath) {
                        $candidates += $info
                    }
                }
            }
        } catch {
            # If WindowsApps enumeration fails, the error below will explain it.
        }
    }

    if ($candidates.Count -eq 0) {
        throw "未找到 WindowsApps 版 Claude Desktop。请确认已安装 Claude，或用 -ResourcesPath 指定 app\resources 目录。"
    }

    $selected = $candidates |
        Sort-Object @{ Expression = { if ($_.Version) { $_.Version } else { [version]"0.0.0.0" } }; Descending = $true },
                    @{ Expression = { $_.InstallLocation }; Descending = $true } |
        Select-Object -First 1

    return $selected
}

function Assert-ResourceFilesExist {
    param([object]$Info)

    $missing = @()
    foreach ($rel in $ResourceFiles) {
        $path = Join-Under -Root $Info.ResourcesPath -RelativePath $rel
        if (-not (Test-Path -LiteralPath $path)) {
            $missing += $rel
        }
    }

    if ($missing.Count -gt 0) {
        throw "Claude 资源结构和预期不一致，缺少文件: $($missing -join ', ')"
    }
}

function Test-CanOpenForWrite {
    param([string]$Path)
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
        $stream.Close()
        return $true
    } catch {
        return $false
    }
}

function Grant-ResourceWriteAccess {
    param([string]$Path)

    if (Test-CanOpenForWrite -Path $Path) {
        return
    }

    if (-not (Test-IsAdministrator)) {
        throw "没有写入权限: $Path。请以管理员身份运行。"
    }

    Write-Host "正在处理权限: $Path"
    & takeown.exe /F $Path /A | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "takeown 失败: $Path"
    }

    & icacls.exe $Path /grant "*S-1-5-32-544:(F)" /C | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "icacls 授权失败: $Path"
    }

    & attrib.exe -R $Path | Out-Null

    if (-not (Test-CanOpenForWrite -Path $Path)) {
        throw "权限处理后仍无法写入: $Path。请确认 Claude 已退出。"
    }
}

function Confirm-YesNo {
    param(
        [string]$Message,
        [bool]$DefaultNo = $true
    )

    if ($Yes) {
        return $true
    }

    $suffix = if ($DefaultNo) { "[y/N，默认否]" } else { "[Y/n，默认是]" }
    $answer = Read-Host "$Message $suffix"

    if ([string]::IsNullOrWhiteSpace($answer)) {
        return (-not $DefaultNo)
    }

    return ($answer -match '^(y|yes|是|好|确认|继续|1)$')
}

function Invoke-UpdateCheck {
    param([switch]$Force)

    if ($SkipUpdateCheck -and -not $Force) {
        return
    }

    Write-Section "检查更新"
    $localVersion = Read-LocalVersionInfo
    Write-Host "本地工具版本: $($localVersion["windows_tool"])"
    Write-Host "本地记忆库版本: $($localVersion["translation_memory"])"

    try {
        $remoteVersion = Get-RemoteVersionInfo
    } catch {
        Write-Host "无法检查远程版本: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "将继续使用本地记忆库，可能会有部分新文本无法汉化。"
        return
    }

    Write-Host "远程来源: $($remoteVersion.Source)"
    Write-Host "远程工具版本: $($remoteVersion.WindowsTool)"
    Write-Host "远程记忆库版本: $($remoteVersion.TranslationMemory)"

    if ((Compare-VersionString -Left $remoteVersion.WindowsTool -Right $localVersion["windows_tool"]) -gt 0) {
        Write-Host ""
        Write-Host "发现工具新版本。建议下载最新版后再使用。" -ForegroundColor Yellow
        Write-Host "GitHub: $ProjectGithub"
        Write-Host "Gitee : $ProjectGitee"
        Write-Host "如果继续使用旧工具，可能会缺少新功能或兼容性修复。"

        if (-not $Yes) {
            $continueOldTool = Confirm-YesNo -Message "是否继续使用当前旧工具？" -DefaultNo $false
            if (-not $continueOldTool) {
                throw "已取消。请下载新版工具后再运行。"
            }
        }
    } else {
        Write-Host "工具已是最新版本。"
    }

    if ((Compare-VersionString -Left $remoteVersion.TranslationMemory -Right $localVersion["translation_memory"]) -gt 0) {
        Write-Host "发现新版翻译记忆库，准备自动更新。"
        try {
            [void](Download-RemoteTranslationMemory -ExpectedVersion $remoteVersion.TranslationMemory)
        } catch {
            Write-Host "记忆库更新失败: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "将继续使用本地记忆库，可能会有部分新文本无法汉化。"
        }
    } else {
        Write-Host "记忆库已是最新版本。"
    }
}

function Stop-ClaudeIfRunning {
    $processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "Claude*" })
    if ($processes.Count -eq 0) {
        return
    }

    Write-Host "检测到 Claude 正在运行: $($processes.ProcessName -join ', ')"
    if (-not (Confirm-YesNo -Message "是否关闭 Claude 后继续？" -DefaultNo $true)) {
        throw "请先退出 Claude Desktop 后再继续。"
    }

    foreach ($proc in $processes) {
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
        } catch {
            Write-Warning "无法结束进程 $($proc.ProcessName)($($proc.Id)): $($_.Exception.Message)"
        }
    }

    Start-Sleep -Seconds 1
}

function Get-VersionKey {
    param([object]$Info)
    if ($Info.Version) {
        return (Get-SafeName -Name $Info.Version.ToString())
    }
    return (Get-SafeName -Name $Info.PackageName)
}

function Get-VersionStatePath {
    param([object]$Info)
    return Join-Path $StateRoot ((Get-VersionKey -Info $Info) + ".json")
}

function Read-VersionState {
    param([object]$Info)

    $statePath = Get-VersionStatePath -Info $Info
    $versionKey = Get-VersionKey -Info $Info

    $state = [ordered]@{
        schema             = 1
        claudeVersion      = $versionKey
        packageName        = $Info.PackageName
        currentState       = "unknown"
        backupRelativePath = ""
        backupCreatedAt    = ""
        lastBackupAt       = ""
        lastPatchedAt      = ""
        lastRestoredAt     = ""
        lastAction         = ""
        lastMemorySha256   = ""
    }

    if (-not (Test-Path -LiteralPath $statePath)) {
        return $state
    }

    $raw = Read-JsonFile -Path $statePath
    foreach ($key in @($state.Keys)) {
        $value = Get-JsonValue -Object $raw -Key $key -Default $state[$key]
        $state[$key] = $value
    }

    return $state
}

function Write-VersionState {
    param(
        [object]$Info,
        [object]$State
    )

    $statePath = Get-VersionStatePath -Info $Info
    New-Item -ItemType Directory -Path (Split-Path -Parent $statePath) -Force | Out-Null
    Write-JsonFile -Path $statePath -Value $State
}

function Update-VersionState {
    param(
        [object]$Info,
        [hashtable]$Updates
    )

    $state = Read-VersionState -Info $Info
    foreach ($key in $Updates.Keys) {
        $state[$key] = $Updates[$key]
    }
    $state["schema"] = 1
    $state["claudeVersion"] = Get-VersionKey -Info $Info
    $state["packageName"] = $Info.PackageName
    Write-VersionState -Info $Info -State $state
    return $state
}

function Get-PackageBackupRoot {
    param([object]$Info)
    return Join-Path $BackupRoot (Get-VersionKey -Info $Info)
}

function Get-PackageReportRoot {
    param([object]$Info)
    return Join-Path $ReportRoot (Get-VersionKey -Info $Info)
}

function Get-OriginalBackupRoot {
    param([object]$Info)
    return Join-Path (Get-PackageBackupRoot -Info $Info) "original"
}

function Get-Backups {
    param([object]$Info)
    $original = Get-OriginalBackupRoot -Info $Info
    if (Test-Path -LiteralPath $original) {
        return @(Get-Item -LiteralPath $original)
    }

    return @()
}

function Get-PreferredBackup {
    param([object]$Info)
    $backups = Get-Backups -Info $Info
    if ($backups.Count -eq 0) {
        return $null
    }
    return $backups[0]
}

function Backup-Resources {
    param([object]$Info)

    Assert-ResourceFilesExist -Info $Info

    $backupDir = Get-OriginalBackupRoot -Info $Info
    if (Test-Path -LiteralPath $backupDir) {
        Write-Host "当前 Claude 版本已经有原始英文备份，不会覆盖: $backupDir"
        [void](Update-VersionState -Info $Info -Updates @{
            currentState       = (Read-VersionState -Info $Info)["currentState"]
            backupRelativePath = Get-ProjectRelativePath -Path $backupDir
            lastAction         = "backup-exists"
        })
        return Get-Item -LiteralPath $backupDir
    }

    $state = Read-VersionState -Info $Info
    if ($state["currentState"] -eq "patched") {
        throw "状态记录显示当前 Claude 版本已经汉化，但原始英文备份不存在。为避免把中文资源备份成原始文件，已取消备份。"
    }

    $map = Read-TranslationMemory
    $preview = Get-ReplacementPreview -SourceRoot $Info.ResourcesPath -Map $map
    $replaceableTotal = 0
    foreach ($item in $preview) {
        $replaceableTotal += [int]$item["replaceable"]
    }
    if ($replaceableTotal -eq 0) {
        throw "当前资源没有命中记忆库，疑似已经汉化。为避免误备份中文资源，已取消备份。"
    }

    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    $files = @()
    foreach ($rel in $ResourceFiles) {
        $source = Join-Under -Root $Info.ResourcesPath -RelativePath $rel
        $target = Join-Under -Root $backupDir -RelativePath $rel
        $targetParent = Split-Path -Parent $target
        New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force

        $files += [ordered]@{
            relativePath       = $rel
            backupRelativePath = Get-ProjectRelativePath -Path $target
            sha256             = Get-FileSha256 -Path $target
            bytes              = (Get-Item -LiteralPath $target).Length
        }
    }

    $createdAt = (Get-Date).ToString("o")
    $manifest = [ordered]@{
        schema             = 1
        type               = "original-resource-backup"
        createdAt          = $createdAt
        packageName        = $Info.PackageName
        claudeVersion      = Get-VersionKey -Info $Info
        backupRelativePath = Get-ProjectRelativePath -Path $backupDir
        files              = $files
        memorySha256       = Get-FileSha256 -Path $TranslationMemoryPath
    }

    Write-JsonFile -Path (Join-Path $backupDir "manifest.json") -Value $manifest
    Write-Host "备份完成: $backupDir"
    [void](Update-VersionState -Info $Info -Updates @{
        currentState       = "original"
        backupRelativePath = Get-ProjectRelativePath -Path $backupDir
        backupCreatedAt    = $createdAt
        lastBackupAt       = $createdAt
        lastAction         = "backup"
        lastMemorySha256   = Get-FileSha256 -Path $TranslationMemoryPath
    })
    return Get-Item -LiteralPath $backupDir
}

function Add-MissingTranslation {
    param(
        [hashtable]$Stats,
        [string]$Value
    )

    if ($Value -match '[A-Za-z]' -and $Value -notmatch '[\u4e00-\u9fff]') {
        $Stats["Missing"][$Value] = ""
    }
}

function Convert-JsonStringsInPlace {
    param(
        [object]$Node,
        [object]$Map,
        [hashtable]$Stats
    )

    if ($null -eq $Node) {
        return $null
    }

    if ($Node -is [string]) {
        $Stats["TotalStrings"]++
        if ($Map.ContainsKey($Node)) {
            $Stats["Replaced"]++
            return [string]$Map[$Node]
        }

        $Stats["Unmatched"]++
        Add-MissingTranslation -Stats $Stats -Value $Node
        return $Node
    }

    if ($Node -is [System.Collections.IDictionary]) {
        $keys = @()
        foreach ($entry in $Node.GetEnumerator()) {
            $keys += $entry.Key
        }
        foreach ($key in $keys) {
            $Node[$key] = Convert-JsonStringsInPlace -Node $Node[$key] -Map $Map -Stats $Stats
        }
        return $Node
    }

    if ($Node -is [System.Array]) {
        for ($i = 0; $i -lt $Node.Length; $i++) {
            $Node[$i] = Convert-JsonStringsInPlace -Node $Node[$i] -Map $Map -Stats $Stats
        }
        return $Node
    }

    if ($Node -is [pscustomobject]) {
        foreach ($prop in $Node.PSObject.Properties) {
            $prop.Value = Convert-JsonStringsInPlace -Node $prop.Value -Map $Map -Stats $Stats
        }
        return $Node
    }

    return $Node
}

function New-Stats {
    return @{
        TotalStrings = 0
        Replaced     = 0
        Unmatched    = 0
        Missing      = New-StringDictionary
    }
}

function Get-ReplacementPreview {
    param(
        [string]$SourceRoot,
        [object]$Map
    )

    $result = @()
    foreach ($rel in $ResourceFiles) {
        $source = Join-Under -Root $SourceRoot -RelativePath $rel
        if (-not (Test-Path -LiteralPath $source)) {
            $result += [ordered]@{
                relativePath = $rel
                exists       = $false
                totalStrings = 0
                replaceable  = 0
                unmatched    = 0
            }
            continue
        }

        $obj = Read-JsonFile -Path $source
        $stats = New-Stats
        [void](Convert-JsonStringsInPlace -Node $obj -Map $Map -Stats $stats)

        $result += [ordered]@{
            relativePath = $rel
            exists       = $true
            totalStrings = $stats["TotalStrings"]
            replaceable  = $stats["Replaced"]
            unmatched    = $stats["Unmatched"]
        }
    }
    return $result
}

function Select-BackupForRestore {
    param([object]$Info)

    $backups = Get-Backups -Info $Info
    if ($backups.Count -eq 0) {
        throw "当前 Claude 版本没有备份，无法还原。"
    }

    if ($Yes) {
        return $backups[0]
    }

    Write-Host ""
    Write-Host "可用备份:"
    for ($i = 0; $i -lt $backups.Count; $i++) {
        $label = if ($i -eq 0) { "推荐原始备份" } else { "" }
        Write-Host ("  {0}. {1} {2}" -f ($i + 1), $backups[$i].Name, $label)
    }

    $choice = Read-Host "请选择要还原的备份编号"
    $index = 0
    if (-not [int]::TryParse($choice, [ref]$index) -or $index -lt 1 -or $index -gt $backups.Count) {
        throw "无效的备份编号。"
    }

    return $backups[$index - 1]
}

function Restore-Resources {
    param([object]$Info)

    Assert-ResourceFilesExist -Info $Info
    Stop-ClaudeIfRunning

    $backup = Select-BackupForRestore -Info $Info
    Write-Host "准备从备份还原: $($backup.FullName)"

    foreach ($rel in $ResourceFiles) {
        $source = Join-Under -Root $backup.FullName -RelativePath $rel
        $target = Join-Under -Root $Info.ResourcesPath -RelativePath $rel
        if (-not (Test-Path -LiteralPath $source)) {
            throw "备份缺少文件: $source"
        }
        Grant-ResourceWriteAccess -Path $target
        Copy-Item -LiteralPath $source -Destination $target -Force
        Write-Host "已还原: $rel"
    }

    [void](Update-VersionState -Info $Info -Updates @{
        currentState       = "restored"
        backupRelativePath = Get-ProjectRelativePath -Path $backup.FullName
        lastRestoredAt     = (Get-Date).ToString("o")
        lastAction         = "restore"
    })
    Write-Host "还原完成。"
}

function Patch-Resources {
    param([object]$Info)

    Assert-ResourceFilesExist -Info $Info
    Stop-ClaudeIfRunning

    $map = Read-TranslationMemory
    $backup = Get-PreferredBackup -Info $Info

    if ($null -eq $backup) {
        Write-Host "当前 Claude 版本还没有备份，先备份原始资源。"
        $preview = Get-ReplacementPreview -SourceRoot $Info.ResourcesPath -Map $map
        $replaceableTotal = 0
        foreach ($item in $preview) {
            $replaceableTotal += [int]$item["replaceable"]
        }
        if ($replaceableTotal -eq 0 -and -not (Confirm-YesNo -Message "当前资源没有命中记忆库，可能已经被汉化。仍然备份并继续？" -DefaultNo $true)) {
            throw "已取消。"
        }
        $backup = Backup-Resources -Info $Info
    } else {
        Write-Host "使用英文源备份: $($backup.FullName)"
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $patchedAt = (Get-Date).ToString("o")
    $packageReportDir = Get-PackageReportRoot -Info $Info
    New-Item -ItemType Directory -Path $packageReportDir -Force | Out-Null

    $fileReports = @()
    $allMissing = New-StringDictionary

    foreach ($rel in $ResourceFiles) {
        $source = Join-Under -Root $backup.FullName -RelativePath $rel
        $target = Join-Under -Root $Info.ResourcesPath -RelativePath $rel

        if (-not (Test-Path -LiteralPath $source)) {
            throw "备份缺少文件: $source"
        }

        $obj = Read-JsonFile -Path $source
        $stats = New-Stats
        [void](Convert-JsonStringsInPlace -Node $obj -Map $map -Stats $stats)

        foreach ($entry in $stats["Missing"].GetEnumerator()) {
            $allMissing[[string]$entry.Key] = ""
        }

        $json = ConvertTo-JsonText -Value $obj
        $tempFile = Join-Path ([IO.Path]::GetTempPath()) ("claude-zh-{0}-{1}.json" -f $timestamp, ([IO.Path]::GetFileName($rel)))
        Write-Utf8NoBomText -Path $tempFile -Text $json

        Grant-ResourceWriteAccess -Path $target
        Copy-Item -LiteralPath $tempFile -Destination $target -Force
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue

        $fileReports += [ordered]@{
            relativePath = $rel
            totalStrings = $stats["TotalStrings"]
            replaced     = $stats["Replaced"]
            unmatched    = $stats["Unmatched"]
            targetSha256 = Get-FileSha256 -Path $target
        }

        Write-Host ("已汉化: {0}  命中 {1}/{2}" -f $rel, $stats["Replaced"], $stats["TotalStrings"])
    }

    $report = [ordered]@{
        createdAt        = (Get-Date).ToString("o")
        packageName      = $Info.PackageName
        version          = if ($Info.Version) { $Info.Version.ToString() } else { $null }
        installLocation  = $Info.InstallLocation
        resourcesPath    = $Info.ResourcesPath
        sourceBackup     = Get-ProjectRelativePath -Path $backup.FullName
        memoryPath       = Get-ProjectRelativePath -Path $TranslationMemoryPath
        memorySha256     = Get-FileSha256 -Path $TranslationMemoryPath
        files            = $fileReports
        missingCount     = Get-DictionaryCount -Dictionary $allMissing
    }

    $reportPath = Join-Path $packageReportDir ("patch-$timestamp.json")
    Write-JsonFile -Path $reportPath -Value $report

    if ((Get-DictionaryCount -Dictionary $allMissing) -gt 0) {
        $missingPath = Join-Path $packageReportDir ("missing-$timestamp.json")
        Write-JsonFile -Path $missingPath -Value $allMissing
        Write-Host "缺失翻译清单: $missingPath"
    }

    [void](Update-VersionState -Info $Info -Updates @{
        currentState       = "patched"
        backupRelativePath = Get-ProjectRelativePath -Path $backup.FullName
        lastPatchedAt      = $patchedAt
        lastAction         = "patch"
        lastMemorySha256   = Get-FileSha256 -Path $TranslationMemoryPath
    })
    Write-Host "汉化完成。报告: $reportPath"
}

function Export-MissingTranslations {
    param([object]$Info)

    Assert-ResourceFilesExist -Info $Info
    $map = Read-TranslationMemory
    $backup = Get-PreferredBackup -Info $Info
    $sourceRoot = if ($backup) { $backup.FullName } else { $Info.ResourcesPath }

    if ($backup) {
        Write-Host "从英文源备份扫描: $($backup.FullName)"
    } else {
        Write-Host "没有备份，从当前资源扫描。"
    }

    $allMissing = New-StringDictionary
    foreach ($rel in $ResourceFiles) {
        $source = Join-Under -Root $sourceRoot -RelativePath $rel
        $obj = Read-JsonFile -Path $source
        $stats = New-Stats
        [void](Convert-JsonStringsInPlace -Node $obj -Map $map -Stats $stats)
        foreach ($entry in $stats["Missing"].GetEnumerator()) {
            $allMissing[[string]$entry.Key] = ""
        }
        Write-Host ("扫描: {0}  缺失 {1}" -f $rel, (Get-DictionaryCount -Dictionary $stats["Missing"]))
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $packageReportDir = Get-PackageReportRoot -Info $Info
    $missingPath = Join-Path $packageReportDir ("missing-only-$timestamp.json")
    Write-JsonFile -Path $missingPath -Value $allMissing
    Write-Host "已导出缺失翻译清单: $missingPath"
}

function Show-Status {
    param([object]$Info)

    Assert-ResourceFilesExist -Info $Info

    Write-Section "Claude Desktop"
    Write-Host "来源: $($Info.Source)"
    Write-Host "版本: $(if ($Info.Version) { $Info.Version.ToString() } else { '未知' })"
    Write-Host "包名: $($Info.PackageName)"
    Write-Host "安装目录: $($Info.InstallLocation)"
    Write-Host "资源目录: $($Info.ResourcesPath)"

    Write-Section "目标文件"
    foreach ($rel in $ResourceFiles) {
        $path = Join-Under -Root $Info.ResourcesPath -RelativePath $rel
        $item = Get-Item -LiteralPath $path
        Write-Host ("{0}  {1:N0} 字节  sha256={2}" -f $rel, $item.Length, (Get-FileSha256 -Path $path).Substring(0, 12))
    }

    Write-Section "备份"
    $backups = Get-Backups -Info $Info
    if ($backups.Count -eq 0) {
        Write-Host "当前版本还没有备份。"
    } else {
        Write-Host "备份数量: $($backups.Count)"
        Write-Host "推荐英文源: $($backups[0].FullName)"
    }

    Write-Section "状态"
    $state = Read-VersionState -Info $Info
    Write-Host "状态文件: $(Get-ProjectRelativePath -Path (Get-VersionStatePath -Info $Info))"
    Write-Host "当前状态: $($state["currentState"])"
    Write-Host "备份相对路径: $($state["backupRelativePath"])"
    Write-Host "最后操作: $($state["lastAction"])"

    Write-Section "翻译记忆库"
    $map = Read-TranslationMemory
    Write-Host "路径: $TranslationMemoryPath"
    Write-Host "条目数: $(Get-DictionaryCount -Dictionary $map)"
    Write-Host "sha256: $(Get-FileSha256 -Path $TranslationMemoryPath)"

    $sourceRoot = if ($backups.Count -gt 0) { $backups[0].FullName } else { $Info.ResourcesPath }
    $preview = Get-ReplacementPreview -SourceRoot $sourceRoot -Map $map
    $totalStrings = 0
    $replaceable = 0
    foreach ($item in $preview) {
        $totalStrings += [int]$item["totalStrings"]
        $replaceable += [int]$item["replaceable"]
    }
    Write-Host "按当前英文源预计可替换: $replaceable / $totalStrings"
}

function Invoke-SelectedAction {
    param([string]$SelectedAction)

    if ($SelectedAction -eq "update") {
        Invoke-UpdateCheck -Force
        return
    }

    $info = Resolve-ClaudeInstall

    switch ($SelectedAction) {
        "status"  { Show-Status -Info $info }
        "backup"  { [void](Backup-Resources -Info $info) }
        "patch"   { Patch-Resources -Info $info }
        "restore" { Restore-Resources -Info $info }
        "missing" { Export-MissingTranslations -Info $info }
        default   { throw "未知操作: $SelectedAction" }
    }
}

function Show-Menu {
    while ($true) {
        Clear-Host
        Write-Host "Claude Desktop 轻量汉化脚本"
        Write-Host ""
        Write-Host "项目目录: $ProjectRoot"
        Write-Host "记忆库: $TranslationMemoryPath"
        Write-Host "开源地址: $ProjectGithub"
        Write-Host "备用地址: $ProjectGitee"
        Write-Host "声明: 本工具永久免费，请勿从收费渠道购买。"
        Write-Host ""
        Write-Host "1. 查看状态"
        Write-Host "2. 备份当前 Claude 资源"
        Write-Host "3. 使用记忆库汉化"
        Write-Host "4. 从备份还原"
        Write-Host "5. 导出缺失翻译清单"
        Write-Host "6. 检查更新/更新记忆库"
        Write-Host "0. 退出"
        Write-Host ""

        $choice = Read-Host "请选择"
        try {
            switch ($choice) {
                "1" { Invoke-SelectedAction -SelectedAction "status" }
                "2" { Invoke-SelectedAction -SelectedAction "backup" }
                "3" { Invoke-SelectedAction -SelectedAction "patch" }
                "4" { Invoke-SelectedAction -SelectedAction "restore" }
                "5" { Invoke-SelectedAction -SelectedAction "missing" }
                "6" { Invoke-SelectedAction -SelectedAction "update" }
                "0" { return }
                default { Write-Host "无效选择。" }
            }
        } catch {
            Write-Host ""
            Write-Host "操作失败: $($_.Exception.Message)" -ForegroundColor Red
        }

        Write-Host ""
        Read-Host "按 Enter 返回菜单" | Out-Null
    }
}

try {
    if ($Action -ne "update") {
        Invoke-UpdateCheck
    }

    if ($Action -eq "menu") {
        Show-Menu
    } else {
        Invoke-SelectedAction -SelectedAction $Action
    }
} catch {
    Write-Host ""
    Write-Host "失败: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
