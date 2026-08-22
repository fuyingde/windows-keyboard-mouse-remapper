$ErrorActionPreference = 'Stop'

$sourceDir = $PSScriptRoot
$mainScripts = @(Get-ChildItem -LiteralPath $sourceDir -File -Filter '*.ahk')
if ($mainScripts.Count -ne 1) {
    throw "Expected exactly one main AHK file in $sourceDir, found $($mainScripts.Count)."
}
$mainScript = $mainScripts[0]

$iconFile = Get-Item -LiteralPath (Join-Path $sourceDir 'img\img.ico') -ErrorAction SilentlyContinue
if ($null -eq $iconFile) {
    throw "Required application icon was not found: $(Join-Path $sourceDir 'img\img.ico')"
}
$interfaceIconFile = Get-Item -LiteralPath (Join-Path $sourceDir 'img\img.svg') -ErrorAction SilentlyContinue
if ($null -eq $interfaceIconFile) {
    throw "Required interface icon was not found: $(Join-Path $sourceDir 'img\img.svg')"
}

$installDir = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\AutoHotkey').InstallDir
$compiler = Join-Path $installDir 'Compiler\Ahk2Exe.exe'
$baseExe = Join-Path $installDir 'v2\AutoHotkey64.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw "Ahk2Exe was not found: $compiler" }
if (-not (Test-Path -LiteralPath $baseExe)) { throw "AutoHotkey v2 64-bit base was not found: $baseExe" }

$sourceText = Get-Content -LiteralPath $mainScript.FullName -Raw -Encoding UTF8
$versionMatch = [regex]::Match($sourceText, 'Ahk2Exe-SetVersion\s+(\d+)\.(\d+)')
if (-not $versionMatch.Success) { throw 'Version directive was not found in the main AHK file.' }
$displayVersion = $versionMatch.Groups[1].Value + '.' + $versionMatch.Groups[2].Value

$compatibilityTest = Join-Path $sourceDir 'tests\ConfigCompatibility.Tests.ps1'
if (-not (Test-Path -LiteralPath $compatibilityTest)) { throw "Required compatibility test was not found: $compatibilityTest" }
& $compatibilityTest -ProjectRoot $sourceDir

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Required language file was not found: $Path" }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Invalid JSON in $Path`: $($_.Exception.Message)" }
}

function Convert-JsonStringsToMap {
    param([object]$Value, [string]$Path)
    $result = [ordered]@{}
    foreach ($property in $Value.PSObject.Properties) {
        if ($property.Value -isnot [string]) { throw "$Path contains a non-string value: $($property.Name)" }
        if ([string]::IsNullOrWhiteSpace($property.Name)) { throw "$Path contains an empty translation key." }
        $result[$property.Name] = [string]$property.Value
    }
    if ($result.Count -eq 0) { throw "$Path must contain at least one translation string." }
    return $result
}

function Get-Placeholders {
    param([string]$Text)
    return @([regex]::Matches($Text, '\{([A-Za-z][A-Za-z0-9]*)\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}

function Assert-SameStringKeys {
    param([System.Collections.IDictionary]$Base, [System.Collections.IDictionary]$Candidate, [string]$Label)
    $missing = @($Base.Keys | Where-Object { -not $Candidate.Contains($_) })
    $extra = @($Candidate.Keys | Where-Object { -not $Base.Contains($_) })
    if ($missing.Count -or $extra.Count) {
        throw "$Label translation keys differ. Missing: $($missing -join ', '); extra: $($extra -join ', ')"
    }
    foreach ($key in $Base.Keys) {
        $left = @(Get-Placeholders ([string]$Base[$key]))
        $right = @(Get-Placeholders ([string]$Candidate[$key]))
        if (($left -join '|') -ne ($right -join '|')) {
            throw "$Label placeholder mismatch for '$key'. Expected {$($left -join ', ')}, found {$($right -join ', ')}."
        }
    }
}

function Convert-InlineMarkdown {
    param([string]$Text)
    $encoded = [System.Net.WebUtility]::HtmlEncode($Text)
    return [regex]::Replace($encoded, '\*\*(.+?)\*\*', '<strong>$1</strong>')
}

function Convert-MarkdownBody {
    param([string[]]$Lines)
    $html = [System.Text.StringBuilder]::new()
    $paragraph = [System.Collections.Generic.List[string]]::new()
    $listType = ''
    $notes = [System.Collections.Generic.List[string]]::new()

    foreach ($lineValue in @($Lines)) {
        $line = [string]$lineValue
        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($paragraph.Count) { [void]$html.Append('<p>' + (Convert-InlineMarkdown ($paragraph -join ' ')) + '</p>'); $paragraph.Clear() }
            if ($listType) { [void]$html.Append("</$listType>"); $listType = '' }
            if ($notes.Count) { [void]$html.Append('<div class="help-note"><div class="help-note-title"></div><p>' + (Convert-InlineMarkdown ($notes -join ' ')) + '</p></div>'); $notes.Clear() }
            continue
        }
        if ($line -match '^###\s+(.+)$') {
            if ($paragraph.Count) { [void]$html.Append('<p>' + (Convert-InlineMarkdown ($paragraph -join ' ')) + '</p>'); $paragraph.Clear() }
            if ($listType) { [void]$html.Append("</$listType>"); $listType = '' }
            if ($notes.Count) { [void]$html.Append('<div class="help-note"><div class="help-note-title"></div><p>' + (Convert-InlineMarkdown ($notes -join ' ')) + '</p></div>'); $notes.Clear() }
            [void]$html.Append('<h3>' + (Convert-InlineMarkdown $Matches[1]) + '</h3>')
            continue
        }
        if ($line -match '^>\s*(.*)$') {
            if ($paragraph.Count) { [void]$html.Append('<p>' + (Convert-InlineMarkdown ($paragraph -join ' ')) + '</p>'); $paragraph.Clear() }
            if ($listType) { [void]$html.Append("</$listType>"); $listType = '' }
            $notes.Add($Matches[1])
            continue
        }
        if ($line -match '^[-*]\s+(.+)$') {
            if ($paragraph.Count) { [void]$html.Append('<p>' + (Convert-InlineMarkdown ($paragraph -join ' ')) + '</p>'); $paragraph.Clear() }
            if ($notes.Count) { [void]$html.Append('<div class="help-note"><div class="help-note-title"></div><p>' + (Convert-InlineMarkdown ($notes -join ' ')) + '</p></div>'); $notes.Clear() }
            if ($listType -ne 'ul') { if ($listType) { [void]$html.Append("</$listType>") }; [void]$html.Append('<ul>'); $listType = 'ul' }
            [void]$html.Append('<li>' + (Convert-InlineMarkdown $Matches[1]) + '</li>')
            continue
        }
        if ($line -match '^\d+\.\s+(.+)$') {
            if ($paragraph.Count) { [void]$html.Append('<p>' + (Convert-InlineMarkdown ($paragraph -join ' ')) + '</p>'); $paragraph.Clear() }
            if ($notes.Count) { [void]$html.Append('<div class="help-note"><div class="help-note-title"></div><p>' + (Convert-InlineMarkdown ($notes -join ' ')) + '</p></div>'); $notes.Clear() }
            if ($listType -ne 'ol') { if ($listType) { [void]$html.Append("</$listType>") }; [void]$html.Append('<ol>'); $listType = 'ol' }
            [void]$html.Append('<li>' + (Convert-InlineMarkdown $Matches[1]) + '</li>')
            continue
        }
        if ($listType) { [void]$html.Append("</$listType>"); $listType = '' }
        if ($notes.Count) { [void]$html.Append('<div class="help-note"><div class="help-note-title"></div><p>' + (Convert-InlineMarkdown ($notes -join ' ')) + '</p></div>'); $notes.Clear() }
        $paragraph.Add($line)
    }
    if ($paragraph.Count) { [void]$html.Append('<p>' + (Convert-InlineMarkdown ($paragraph -join ' ')) + '</p>') }
    if ($listType) { [void]$html.Append("</$listType>") }
    if ($notes.Count) { [void]$html.Append('<div class="help-note"><div class="help-note-title"></div><p>' + (Convert-InlineMarkdown ($notes -join ' ')) + '</p></div>') }
    return $html.ToString()
}

function Read-HelpMarkdown {
    param([string]$Path)
    $groups = [System.Collections.ArrayList]::new()
    $currentGroup = $null
    $currentLeaf = $null
    foreach ($line in @(Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ($line -match '^#\s+(.+?)\s+\{#([a-z0-9-]+)\}\s*$') {
            $currentGroup = [pscustomobject]@{ id = $Matches[2]; title = $Matches[1]; children = [System.Collections.ArrayList]::new() }
            [void]$groups.Add($currentGroup)
            $currentLeaf = $null
            continue
        }
        if ($line -match '^##\s+(.+?)\s+\{#([a-z0-9-]+)\}\s*$') {
            if ($null -eq $currentGroup) { throw "$Path contains a help page before its group." }
            $currentLeaf = [pscustomobject]@{ id = $Matches[2]; title = $Matches[1]; body = [System.Collections.Generic.List[string]]::new() }
            [void]$currentGroup.children.Add($currentLeaf)
            continue
        }
        if ($null -ne $currentLeaf) { $currentLeaf.body.Add([string]$line) }
        elseif (-not [string]::IsNullOrWhiteSpace($line)) { throw "$Path contains content outside a help page: $line" }
    }
    if ($groups.Count -eq 0) { throw "$Path must contain at least one help group." }
    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $sections = @()
    foreach ($group in $groups) {
        if (-not $ids.Add($group.id)) { throw "$Path contains duplicate help id '$($group.id)'." }
        if ($group.children.Count -eq 0) { throw "$Path help group '$($group.id)' has no pages." }
        $children = @()
        foreach ($leaf in $group.children) {
            if (-not $ids.Add($leaf.id)) { throw "$Path contains duplicate help id '$($leaf.id)'." }
            $bodyHtml = Convert-MarkdownBody $leaf.body.ToArray()
            if ([string]::IsNullOrWhiteSpace($bodyHtml)) { throw "$Path help page '$($leaf.id)' is empty." }
            $children += [ordered]@{ id = $leaf.id; title = $leaf.title; html = $bodyHtml }
        }
        $sections += [ordered]@{ id = $group.id; title = $group.title; children = $children }
    }
    return [ordered]@{ sections = $sections; ids = @($ids | Sort-Object) }
}

function Read-ChangelogMarkdown {
    param([string]$Path)
    $entries = [System.Collections.ArrayList]::new()
    $current = $null
    foreach ($line in @(Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ($line -match '^##\s+([0-9]+\.[0-9]+)\s*$') {
            $current = [pscustomobject]@{ version = $Matches[1]; items = [System.Collections.ArrayList]::new() }
            [void]$entries.Add($current)
            continue
        }
        if ($line -match '^[-*]\s+(.+)$') {
            if ($null -eq $current) { throw "$Path contains a changelog item before a version." }
            [void]$current.items.Add($Matches[1])
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($line)) { throw "$Path contains unsupported changelog content: $line" }
    }
    if ($entries.Count -eq 0) { throw "$Path must contain at least one changelog version." }
    $versions = [System.Collections.Generic.HashSet[string]]::new()
    $result = @()
    foreach ($entry in $entries) {
        if (-not $versions.Add($entry.version)) { throw "$Path contains duplicate version '$($entry.version)'." }
        if ($entry.items.Count -eq 0) { throw "$Path version '$($entry.version)' has no items." }
        $result += [ordered]@{ version = $entry.version; items = @($entry.items) }
    }
    if (-not $versions.Contains($displayVersion)) { throw "$Path does not contain the current version $displayVersion." }
    return [ordered]@{ entries = $result; versions = @($versions | Sort-Object) }
}

$localesRoot = Join-Path $sourceDir 'locales'
$orderData = Read-JsonFile (Join-Path $localesRoot 'language-order.json')
$requestedOrder = @($orderData.order | ForEach-Object { [string]$_ })
if ($requestedOrder.Count -eq 0) { throw 'language-order.json must contain at least one locale code.' }
$localeDirectories = @(Get-ChildItem -LiteralPath $localesRoot -Directory | Sort-Object Name)
$availableCodes = @($localeDirectories | Select-Object -ExpandProperty Name)
$localeOrder = @($requestedOrder | Where-Object { $availableCodes -contains $_ })
$localeOrder += @($availableCodes | Where-Object { $localeOrder -notcontains $_ })
if ($localeOrder -notcontains 'zh-CN') { throw 'The required zh-CN base language pack is missing.' }

$categoryNames = @('ui', 'messages', 'keys', 'logs')
$baseCategories = $null
$baseHelpIds = $null
$baseVersions = $null
$packs = [ordered]@{}
$nativeNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($code in $localeOrder) {
    $directory = Join-Path $localesRoot $code
    $manifest = Read-JsonFile (Join-Path $directory 'manifest.json')
    if ([int]$manifest.schemaVersion -ne 1) { throw "$code manifest has an unsupported schemaVersion." }
    if ([string]$manifest.code -ne $code) { throw "$code manifest code does not match its directory name." }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.nativeName)) { throw "$code manifest nativeName is empty." }
    if (-not $nativeNames.Add([string]$manifest.nativeName)) { throw "Duplicate native language name: $($manifest.nativeName)" }
    if (@('ltr', 'rtl') -notcontains [string]$manifest.direction) { throw "$code manifest direction must be ltr or rtl." }

    $categories = [ordered]@{}
    $mergedStrings = [ordered]@{}
    foreach ($category in $categoryNames) {
        $path = Join-Path $directory ($category + '.json')
        $categories[$category] = Convert-JsonStringsToMap (Read-JsonFile $path) $path
        foreach ($key in $categories[$category].Keys) {
            if ($mergedStrings.Contains($key)) { throw "$code contains duplicate translation key '$key'." }
            $mergedStrings[$key] = $categories[$category][$key]
        }
    }
    $help = Read-HelpMarkdown (Join-Path $directory 'help.md')
    $aboutPath = Join-Path $directory 'about.md'
    if (-not (Test-Path -LiteralPath $aboutPath)) { throw "Required language file was not found: $aboutPath" }
    $aboutHtml = Convert-MarkdownBody @(Get-Content -LiteralPath $aboutPath -Encoding UTF8)
    if ([string]::IsNullOrWhiteSpace($aboutHtml)) { throw "$aboutPath is empty." }
    $changelog = Read-ChangelogMarkdown (Join-Path $directory 'changelog.md')

    if ($code -eq 'zh-CN') {
        $baseCategories = $categories
        $baseHelpIds = @($help.ids)
        $baseVersions = @($changelog.versions)
    } else {
        foreach ($category in $categoryNames) { Assert-SameStringKeys $baseCategories[$category] $categories[$category] "$code/$category.json" }
        if (($baseHelpIds -join '|') -ne (@($help.ids) -join '|')) { throw "$code help page ids do not match zh-CN." }
        if (($baseVersions -join '|') -ne (@($changelog.versions) -join '|')) { throw "$code changelog versions do not match zh-CN." }
    }

    $packs[$code] = [ordered]@{
        meta = [ordered]@{ code = $code; nativeName = [string]$manifest.nativeName; direction = [string]$manifest.direction }
        strings = $mergedStrings
        help = [ordered]@{ sections = $help.sections }
        aboutHtml = $aboutHtml
        changelog = [ordered]@{ entries = $changelog.entries }
    }
}

$compiledData = [ordered]@{ defaultLocale = 'zh-CN'; order = $localeOrder; packs = $packs }
$compiledJson = $compiledData | ConvertTo-Json -Depth 30 -Compress
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText((Join-Path $localesRoot 'compiled-locales.json'), $compiledJson, $utf8NoBom)

function Convert-ToAhkString {
    param([string]$Value)
    $escaped = $Value.Replace('`', '``').Replace('"', '""').Replace("`r", '').Replace("`n", '``n')
    return '"' + $escaped + '"'
}

$generated = [System.Text.StringBuilder]::new()
[void]$generated.AppendLine('; Generated by build.ps1 from locales/. Do not edit this file manually.')
[void]$generated.AppendLine('GeneratedLocaleCatalog() {')
[void]$generated.AppendLine('    packs := Map()')
foreach ($code in $localeOrder) {
    [void]$generated.AppendLine('    strings := Map()')
    foreach ($key in $packs[$code].strings.Keys) {
        [void]$generated.AppendLine('    strings[' + (Convert-ToAhkString $key) + '] := ' + (Convert-ToAhkString ([string]$packs[$code].strings[$key])))
    }
    [void]$generated.AppendLine('    packs[' + (Convert-ToAhkString $code) + '] := {nativeName: ' + (Convert-ToAhkString ([string]$packs[$code].meta.nativeName)) + ', direction: ' + (Convert-ToAhkString ([string]$packs[$code].meta.direction)) + ', strings: strings}')
}
$orderValues = @($localeOrder | ForEach-Object { Convert-ToAhkString $_ }) -join ', '
[void]$generated.AppendLine('    return {defaultLocale: "zh-CN", order: [' + $orderValues + '], packs: packs}')
[void]$generated.AppendLine('}')
[System.IO.File]::WriteAllText((Join-Path $sourceDir 'Core\GeneratedLocales.ahk'), $generated.ToString(), $utf8NoBom)

$releaseDirPath = Join-Path $sourceDir 'exe'
if (-not (Test-Path -LiteralPath $releaseDirPath)) { New-Item -ItemType Directory -Path $releaseDirPath | Out-Null }
$releaseDir = Get-Item -LiteralPath $releaseDirPath
$outputName = 'KeyMouseMapper-OpenSource-v' + $displayVersion + '.exe'
$temporaryOutput = Join-Path $releaseDir.FullName ([IO.Path]::GetFileNameWithoutExtension($outputName) + '.build.tmp.exe')
$finalOutput = Join-Path $releaseDir.FullName $outputName
if (Test-Path -LiteralPath $temporaryOutput) { Remove-Item -LiteralPath $temporaryOutput -Force }

& $compiler /in $mainScript.FullName /out $temporaryOutput /base $baseExe /icon $iconFile.FullName /silent verbose
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Ahk2Exe failed with exit code $LASTEXITCODE." }
for ($attempt = 0; $attempt -lt 120 -and -not (Test-Path -LiteralPath $temporaryOutput); $attempt++) { Start-Sleep -Milliseconds 250 }
if (-not (Test-Path -LiteralPath $temporaryOutput)) { throw 'Compiler reported success but the output file was not created.' }
Copy-Item -LiteralPath $temporaryOutput -Destination $finalOutput -Force
Remove-Item -LiteralPath $temporaryOutput -Force

$result = Get-Item -LiteralPath $finalOutput
$hash = (Get-FileHash -LiteralPath $finalOutput -Algorithm SHA256).Hash
Write-Host "Validated locales: $($localeOrder -join ', ')"
Write-Host "Build complete: $($result.FullName)"
Write-Host "Size: $($result.Length) bytes"
Write-Host "SHA256: $hash"
