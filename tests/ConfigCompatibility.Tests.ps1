param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'

function Assert-ContainsText {
    param([string]$Text, [string]$Expected, [string]$Description)
    if (-not $Text.Contains($Expected)) {
        throw "Configuration compatibility check failed: $Description"
    }
}

function Assert-NotContainsText {
    param([string]$Text, [string]$Unexpected, [string]$Description)
    if ($Text.Contains($Unexpected)) {
        throw "Open-source feature boundary check failed: $Description"
    }
}

$mainPath = Join-Path $ProjectRoot 'KeyMouseMapper.ahk'
$settingsPath = Join-Path $ProjectRoot 'Core\SettingsCore.ahk'
$mappingPath = Join-Path $ProjectRoot 'Core\MappingCore.ahk'
$bridgePath = Join-Path $ProjectRoot 'bridge.js'

$main = Get-Content -LiteralPath $mainPath -Raw -Encoding UTF8
$settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8
$mapping = Get-Content -LiteralPath $mappingPath -Raw -Encoding UTF8
$bridge = Get-Content -LiteralPath $bridgePath -Raw -Encoding UTF8

foreach ($field in @('SchemaVersion', 'AutoStart', 'TrayIcon', 'Mode', 'PressDurationMin', 'PressDurationMax', 'ExecutionMode')) {
    Assert-ContainsText $settings ('"' + $field + '"') "settings.ini field '$field' is missing"
}
Assert-ContainsText $settings 'IniWrite(App.settings.storedMode' 'the full-version Mode value is no longer preserved'
Assert-ContainsText $settings 'IniWrite(App.settings.pressDurationMin' 'PressDurationMin is no longer preserved'
Assert-ContainsText $settings 'IniWrite(App.settings.pressDurationMax' 'PressDurationMax is no longer preserved'
Assert-ContainsText $settings 'IniWrite(App.settings.executionMode' 'ExecutionMode is no longer preserved'

foreach ($field in @('SchemaVersion', 'Count', 'Source', 'Target', 'Enabled', 'Global')) {
    Assert-ContainsText $mapping ('"' + $field + '"') "mappings.ini field '$field' is missing"
}
Assert-ContainsText $main 'autoPressFile: A_AppData "\FuYingKeyMouseTools\auto-press.ini"' 'the compatible auto-press.ini location changed'
Assert-NotContainsText ($main + $settings + $mapping) 'App.autoPressFile' 'the open-source build reads or writes auto-press.ini'
Assert-NotContainsText $bridge 'SetExecutionMode' 'Global activation is exposed by the interface'
Assert-NotContainsText $bridge 'SetPressDuration' 'press-duration editing is exposed by the interface'
Assert-NotContainsText $bridge 'ExportPreset' 'preset export is exposed by the interface'
Assert-NotContainsText $bridge 'ImportPreset' 'preset import is exposed by the interface'

if (Test-Path -LiteralPath (Join-Path $ProjectRoot 'Core\AutoPressCore.ahk')) {
    throw 'Open-source feature boundary check failed: AutoPressCore.ahk is still present'
}
if (Test-Path -LiteralPath (Join-Path $ProjectRoot 'Core\PresetCore.ahk')) {
    throw 'Open-source feature boundary check failed: PresetCore.ahk is still present'
}

Write-Output 'Validated configuration compatibility and open-source feature boundaries'
