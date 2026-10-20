$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$workflow = [IO.File]::ReadAllText((Join-Path $root '.github/workflows/build.yml'))
$match = [regex]::Match($workflow, '(?ms)^    - name: Replace\r?\n.*?      run: \|\r?\n(?<code>.*?)(?=^    - name:)')
if (-not $match.Success) { throw 'Replace step not found.' }
$code = [regex]::Replace($match.Groups['code'].Value, '(?m)^        ', '')
$replace = [scriptblock]::Create($code)
$secret = [IO.File]::ReadAllText((Join-Path $root 'Plain Craft Launcher 2/Modules/ModSecret.vb'))
$base = [IO.File]::ReadAllText((Join-Path $root 'Plain Craft Launcher 2/Modules/Base/ModBase.vb'))

# Exercise the actual workflow script in memory without modifying source files.
function Get-Content ($LiteralPath, [switch]$Raw) {
    if ($LiteralPath.EndsWith('ModSecret.vb')) { return $secret }
    return $base
}
function Set-Content ($LiteralPath, $Value, $Encoding, [switch]$NoNewline) {
    $written[$LiteralPath] = $Value
}

$env:GITHUB_SHA = '0123456789abcdef'
foreach ($value in @('', 'test-client-id', '$2a$10$test\key"quoted')) {
    $env:CLIENT_ID = $value
    $env:CF_KEY = $value
    $written = @{}
    & $replace
    $output = $written['Plain Craft Launcher 2\Modules\ModSecret.vb']
    foreach ($variable in @('PCL_MS_CLIENT_ID', 'PCL_CURSEFORGE_API_KEY')) {
        $expected = 'Environment.GetEnvironmentVariable("' + $variable + '"), "' + $value.Replace('"', '""') + '"'
        if (-not $output.Contains($expected)) { throw "Incorrect substitution: $variable" }
    }
    if (-not $written['Plain Craft Launcher 2\Modules\Base\ModBase.vb'].Contains('Public Const CommitHash As String = "0123456789abcdef"')) {
        throw 'Commit hash not injected.'
    }
}
$env:CF_KEY = "invalid`nkey"
$rejected = $false
try { & $replace } catch { $rejected = $_.Exception.Message -eq 'Build credentials must be single-line values.' }
if (-not $rejected) { throw 'Multiline credential was not rejected.' }
'Build credential checks passed (empty, normal, special characters, multiline rejection, commit hash).'
