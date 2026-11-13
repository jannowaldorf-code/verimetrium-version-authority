# GVA-K03 PRIVATE RELEASE DELIVERY AUTHORITY
# Compatible with Windows PowerShell 5.1+; no third-party PowerShell module required.
# This tool does not issue global GVA version numbers and never uploads to a public repository.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Setup','Publish','Fetch','SelfTest')]
    [string]$Action,
    [string]$Repo = 'jannowaldorf-code/verimetrium-deliveries',
    [string]$AssetPath,
    [string]$WorkId,
    [ValidateSet('PROOF','OFFICIAL')]
    [string]$Channel = 'PROOF',
    [string]$AuthorityVersion,
    [string]$SourceSetSha256,
    [string]$Tag,
    [string]$Destination = 'D:\DADA\VERIMETRIUM_RELEASES'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ManifestName = 'GVA_K03_DELIVERY_MANIFEST.json'
$AuthorityRepo = 'jannowaldorf-code/verimetrium-version-authority'

function Require([bool]$OK, [string]$Message) {
    if (-not $OK) { throw $Message }
}
function Valid-Hash([string]$Value) { return ($null -ne $Value -and $Value -cmatch '^[0-9a-fA-F]{64}$') }
function Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Invoke-Gh([string[]]$ArgsList) {
    $lines = @(& gh @ArgsList 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        # Avoid leaking authentication output or URLs containing credentials.
        throw ('GitHub CLI command failed: ' + $ArgsList[0] + ' (exit ' + $exitCode + ')')
    }
    return ($lines -join "`n")
}
function Assert-Authentication {
    Require ($null -ne (Get-Command gh -ErrorAction SilentlyContinue)) 'GitHub CLI missing. Install: https://cli.github.com/ and sign in with: gh auth login -h github.com -p https -w'
    $null = Invoke-Gh -ArgsList @('auth','status','--hostname','github.com')
}
function Repo-Metadata([bool]$AllowAbsent=$false) {
    Require ($Repo -cmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') 'Invalid GitHub repository name.'
    $out = @(& gh repo view $Repo --json nameWithOwner,visibility,isArchived 2>$null)
    if ($LASTEXITCODE -ne 0) {
        if ($AllowAbsent) { return $null }
        throw ('Cannot access release repository: ' + $Repo)
    }
    return (($out -join "`n") | ConvertFrom-Json)
}
function Assert-Private {
    $m = Repo-Metadata
    Require ([string]$m.visibility -ceq 'PRIVATE') ('SECURITY BLOCK: repository ' + $Repo + ' is not PRIVATE. Upload refused.')
    Require (-not [bool]$m.isArchived) 'Repository is archived.'
}
function Assert-ImmutableReleases {
    $info = Invoke-Gh -ArgsList @('api',('repos/' + $Repo + '/immutable-releases'))
    $setting = ($info | ConvertFrom-Json)
    Require ([bool]$setting.enabled) 'SECURITY BLOCK: GitHub release immutability is not enabled.'
}
function Manifest-For([string]$File, [string]$Work, [string]$ReleaseTag) {
    $info = Get-Item -LiteralPath $File
    return [ordered]@{
        schema = 'GVA-K03-PRIVATE-DELIVERY-v1'
        repository = $Repo
        release_tag = $ReleaseTag
        work_id = $Work
        channel = $Channel
        asset_name = $info.Name
        asset_size_bytes = [long]$info.Length
        asset_sha256 = Sha256 $File
        authority_repo = $AuthorityRepo
        authority_version = $(if ($Channel -eq 'OFFICIAL') { $AuthorityVersion } else { $null })
        source_set_sha256 = $(if ($Channel -eq 'OFFICIAL') { $SourceSetSha256.ToLowerInvariant() } else { $null })
        official_version_issued_by_delivery = $false
        provenance = 'Local file hash and optional independently issued public GVA registry record; not broker-trade proof.'
    }
}
function Check-Manifest($M, [string]$File, [string]$ExpectedTag) {
    Require ([string]$M.schema -ceq 'GVA-K03-PRIVATE-DELIVERY-v1') 'Unknown manifest schema.'
    Require ([string]$M.repository -ceq $Repo) 'Manifest repository mismatch.'
    Require ([string]$M.release_tag -ceq $ExpectedTag) 'Manifest tag mismatch.'
    Require ([string]$M.asset_name -cmatch '^[A-Za-z0-9_ .()-]+\.zip$') 'Unsafe asset filename.'
    Require ([string]$M.work_id -cmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{2,80}$') 'Unsafe work id.'
    Require (Valid-Hash ([string]$M.asset_sha256)) 'Invalid expected SHA-256.'
    Require ([string]$M.channel -in @('PROOF','OFFICIAL')) 'Invalid release classification.'
    $requiredProofTag = 'proof-' + ([string]$M.work_id).ToLowerInvariant() + '-' + ([string]$M.asset_sha256).Substring(0,16)
    if (([string]$M.channel -ceq 'PROOF') -and ([string]$M.release_tag -cne $requiredProofTag)) {
        # Offline selftest uses a short synthetic tag; all real releases require their hash in the tag.
        Require ([string]$M.release_tag -ceq 'proof-selftest') 'Proof tag does not match work ID and SHA256.'
    }
    if ([string]$M.channel -ceq 'OFFICIAL') {
        $requiredOfficialTag = 'gva-' + ([string]$M.authority_version).ToLowerInvariant()
        Require ([string]$M.release_tag -ceq $requiredOfficialTag) 'Official tag/version mismatch.'
        Require (Valid-Hash ([string]$M.source_set_sha256)) 'Official source-set hash missing.'
    }
    $f = Get-Item -LiteralPath $File
    Require ($f.Name -ceq [string]$M.asset_name) 'Asset name mismatch.'
    Require ([long]$f.Length -eq [long]$M.asset_size_bytes) 'Asset size mismatch.'
    Require ((Sha256 $f.FullName) -ceq [string]$M.asset_sha256) 'SHA-256 MISMATCH. Asset rejected.'
    Require (-not [bool]$M.official_version_issued_by_delivery) 'Manifest unlawfully claims version issuance.'
}
function Validate-GVA-OfficialRecord {
    Require ([string]$AuthorityVersion -cmatch '^V[0-9]+\.[0-9]{2}$') 'An issued global Vxxxx.xx number is required.'
    Require (Valid-Hash $SourceSetSha256) 'Exact source-set SHA-256 is required.'
    $raw = Invoke-Gh -ArgsList @('api',('repos/' + $AuthorityRepo + '/contents/gva/registry.json'))
    $blob = $raw | ConvertFrom-Json
    $bytes = [Convert]::FromBase64String(([string]$blob.content -replace '\s',''))
    $ledger = ([Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json)
    Require ([string]$ledger.authority -ceq $AuthorityRepo) 'Global version authority mismatch.'
    $entries = @($ledger.releases | Where-Object { $_.version -ceq $AuthorityVersion })
    Require ($entries.Count -eq 1) 'Global version not issued exactly once in GVA registry.'
    Require ([string]$entries[0].work -ceq $WorkId) 'Global GVA work identity does not match.'
    Require ([string]$entries[0].source_set_sha256 -ceq $SourceSetSha256.ToLowerInvariant()) 'Global source-set digest does not match.'
}
function Stage-Release([string]$ReleaseTag, [string]$File, $M) {
    $location = Join-Path (Join-Path $Destination $ReleaseTag) 'verified'
    [IO.Directory]::CreateDirectory($location) | Out-Null
    $target = Join-Path $location ([string]$M.asset_name)
    if (Test-Path -LiteralPath $target) {
        Check-Manifest $M $target $ReleaseTag
    } else {
        Copy-Item -LiteralPath $File -Destination $target
        Check-Manifest $M $target $ReleaseTag
    }
    $json = ($M | ConvertTo-Json -Depth 6)
    [IO.File]::WriteAllText((Join-Path $location $ManifestName),$json,[Text.UTF8Encoding]::new($false))
    return $target
}
function Read-RemoteRelease([string]$ReleaseTag) {
    Assert-Private
    Assert-ImmutableReleases
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('gva_k03_' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($tmp) | Out-Null
    try {
        $null = Invoke-Gh -ArgsList @('release','download',$ReleaseTag,'--repo',$Repo,'--dir',$tmp,'--pattern',$ManifestName)
        $mfPath = Join-Path $tmp $ManifestName
        Require (Test-Path -LiteralPath $mfPath) 'Release manifest missing.'
        $mf = Get-Content -LiteralPath $mfPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Require ([string]$mf.asset_name -cmatch '^[A-Za-z0-9_ .()-]+\.zip$') 'Unsafe manifest filename.'
        $null = Invoke-Gh -ArgsList @('release','download',$ReleaseTag,'--repo',$Repo,'--dir',$tmp,'--pattern',([string]$mf.asset_name))
        $assetFile = Join-Path $tmp ([string]$mf.asset_name)
        Require (Test-Path -LiteralPath $assetFile) 'Release asset is missing.'
        Check-Manifest $mf $assetFile $ReleaseTag
        $local = Stage-Release $ReleaseTag $assetFile $mf
        Write-Host ('PASS RELEASE ROUND-TRIP SHA256: ' + [string]$mf.asset_sha256) -ForegroundColor Green
        Write-Host ('Verified file: ' + $local) -ForegroundColor Green
        return $mf
    } finally {
        Remove-Item -LiteralPath $tmp -Force -Recurse -ErrorAction SilentlyContinue
    }
}

switch ($Action) {
    'SelfTest' {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('gva_k03_test_' + [guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($tmp) | Out-Null
        try {
            $f = Join-Path $tmp 'gva-k03-selftest.zip'
            [IO.File]::WriteAllText($f,'GVA-K03-TEST',[Text.UTF8Encoding]::new($false))
            $oldRepo = $Repo
            $Repo = 'example/private-test'
            $Channel = 'PROOF'
            $m = Manifest-For $f 'GVA-K03-SELFTEST' 'proof-selftest'
            Check-Manifest $m $f 'proof-selftest'
            [IO.File]::AppendAllText($f,'tampered')
            $wasRejected = $false
            try { Check-Manifest $m $f 'proof-selftest' } catch { $wasRejected = $true }
            Require $wasRejected 'Negative tamper test incorrectly accepted altered file.'
            $Repo = $oldRepo
            Write-Host 'PASS GVA-K03 SELFTEST (positive+tamper rejection; no network)' -ForegroundColor Green
        } finally { Remove-Item -LiteralPath $tmp -Force -Recurse -ErrorAction SilentlyContinue }
        break
    }
    'Setup' {
        Assert-Authentication
        $existing = Repo-Metadata $true
        if ($null -eq $existing) {
            Write-Host ('Creating PRIVATE delivery repo: ' + $Repo)
            $null = Invoke-Gh -ArgsList @('repo','create',$Repo,'--private','--add-readme','--description','Private VERIMETRIUM immutable SHA-256 checked release assets. No global version issuance.')
        }
        Assert-Private
        # GET returns HTTP 200 when enabled and 404 when disabled. Do not PUT again
        # when the setting is already enabled (including owner-enforced policy).
        $immutable = @(& gh api ('repos/' + $Repo + '/immutable-releases') 2>$null)
        if ($LASTEXITCODE -ne 0) {
            $null = Invoke-Gh -ArgsList @('api','--method','PUT',('repos/' + $Repo + '/immutable-releases'))
        }
        Assert-ImmutableReleases
        Write-Host ('PASS PRIVATE RELEASE REPOSITORY: ' + $Repo) -ForegroundColor Green
        Write-Host 'No global GVA version number was issued or modified.'
        break
    }
    'Publish' {
        Assert-Authentication
        Assert-Private
        Assert-ImmutableReleases
        Require (Test-Path -LiteralPath $AssetPath -PathType Leaf) 'Asset ZIP not found at the supplied path.'
        $asset = (Resolve-Path -LiteralPath $AssetPath).Path
        Require ([IO.Path]::GetExtension($asset) -ceq '.zip') 'Only ZIP assets are accepted.'
        Require ($WorkId -cmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{2,80}$') 'WorkId required; use e.g. W0438154.'
        $fileInfo = Get-Item -LiteralPath $asset
        Require ([long]$fileInfo.Length -gt 0 -and [long]$fileInfo.Length -lt 2147483648L) 'File must be non-empty and less than 2 GiB.'
        if ($Channel -eq 'OFFICIAL') { Validate-GVA-OfficialRecord }
        $hash = Sha256 $asset
        if ($Channel -eq 'PROOF') {
            $releaseTag = 'proof-' + $WorkId.ToLowerInvariant() + '-' + $hash.Substring(0,16)
        } else {
            $releaseTag = 'gva-' + $AuthorityVersion.ToLowerInvariant()
        }
        $mf = Manifest-For $asset $WorkId $releaseTag
        $existing = @(& gh release view $releaseTag --repo $Repo --json tagName 2>$null)
        if ($LASTEXITCODE -eq 0) {
            Write-Host 'Release tag already exists. Checking immutable equality ...'
            $remoteManifest = Read-RemoteRelease $releaseTag
            Require ([string]$remoteManifest.asset_sha256 -ceq $hash) 'Existing tag has a different asset SHA256: do NOT overwrite.'
            Require ([string]$remoteManifest.work_id -ceq $WorkId) 'Existing tag work ID mismatch.'
            Write-Host 'PASS IDEMPOTENT EXISTING RELEASE' -ForegroundColor Green
            break
        }
        $temp = Join-Path ([IO.Path]::GetTempPath()) ('gva_k03_pub_' + [guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($temp) | Out-Null
        try {
            $manifestFile = Join-Path $temp $ManifestName
            [IO.File]::WriteAllText($manifestFile,($mf | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
            $notes = 'GVA-K03 ' + $Channel + ' | ' + $WorkId + ' | SHA256 ' + $hash + '. Research proof: no actual broker fill claim. Delivery does NOT issue global GVA versions.'
            $argsList = @('release','create',$releaseTag,$asset,$manifestFile,'--repo',$Repo,'--title',('GVA-K03 ' + $WorkId),'--notes',$notes,'--latest=false')
            if ($Channel -eq 'PROOF') { $argsList += '--prerelease' }
            $result = Invoke-Gh $argsList
            Write-Host ('Uploaded release: ' + $result)
        } finally { Remove-Item -LiteralPath $temp -Force -Recurse -ErrorAction SilentlyContinue }
        $downloadedManifest = Read-RemoteRelease $releaseTag
        Require ([string]$downloadedManifest.asset_sha256 -ceq $hash) 'Remote readback mismatch.'
        Write-Host ('PASS PRIVATE RELEASE PUBLISHED: ' + $releaseTag) -ForegroundColor Green
        break
    }
    'Fetch' {
        Assert-Authentication
        Require ($Tag -cmatch '^(proof-[a-z0-9_.-]+-[0-9a-f]{16}|gva-v[0-9]+\.[0-9]{2})$') 'Explicit safe release tag required.'
        $null = Read-RemoteRelease $Tag
        break
    }
}
