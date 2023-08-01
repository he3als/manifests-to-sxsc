<# : batch portion
@echo off
powershell -nop Get-Content "%~f0" -Raw ^| iex & exit
: end batch / begin PowerShell #>

$version = "38655.38527.65535.65535"
$sxsexpPath = "$PWD\sxsexp.exe"

if (!(Test-Path $sxsexpPath)) {
    Write-Host "sxsexp not found! edit the variable"
    pause
    exit 1
}

$inputFilePaths = Get-ChildItem -Path "$PWD\*.manifest" -File | ForEach-Object { $_.FullName }

function Process-Manifest {
    param (
        [string]$filePath
    )

    New-Item -Path "$PWD" -Name "decompressed" -ItemType "directory" -EA SilentlyContinue | Out-Null
    $outputPath = "$PWD\decompressed\$([System.IO.Path]::GetFileNameWithoutExtension($filePath)).xml"
    
    $name = Split-Path -Leaf $filePath
    $result = & $sxsexpPath "$filePath" "$outputPath"
    if ($lastexitcode -ne 0) {
        Write-Host "`nFailed processing`n-------------------------------- " -ForegroundColor Red
        Write-Host "$name"
        Add-content "error.log" -value $result
    } else {
        Write-Host "`nSuccessfully processed`n-------------------------------- " -ForegroundColor Green
        Write-Host "$name"
    }
}

foreach ($inputFilePath in $inputFilePaths) {
    if (Test-Path $inputFilePath -PathType Leaf) {Process-Manifest $inputFilePath} else {
        # if it's a directory, get all files recursively and process each file
        Get-ChildItem -Path $inputFilePath -Recurse -File | ForEach-Object {
            Process-Manifest $_.FullName
        }
    }
}

$rootDirectory = "$PWD\decompressed"
$processedEntries = @{}

# get the assemblyIdentity name and processorArchitecture from an XML
function Get-AssemblyIdentityInfo($filePath) {
    try {
        $xmlContent = [xml](Get-Content $filePath)
        $xmlNamespaceManager = New-Object System.Xml.XmlNamespaceManager($xmlContent.NameTable)
        $xmlNamespaceManager.AddNamespace("ns", "urn:schemas-microsoft-com:asm.v3")
        $assemblyIdentity = $xmlContent.SelectSingleNode("//ns:assemblyIdentity", $xmlNamespaceManager)
        if ($assemblyIdentity) {
            $assemblyName = $assemblyIdentity.GetAttribute("name")
            $processorArchitecture = $assemblyIdentity.GetAttribute("processorArchitecture")
            $entryKey = "  - target_component: $assemblyName
    target_arch: $processorArchitecture
    version: $version"
            if (-not $processedEntries.ContainsKey($entryKey)) {
                $processedEntries[$entryKey] = $true
                return $entryKey
            }
        }
    } catch {
        Write-Host "Error processing: $filePath"
    }
    return $null
}

function Process-DecompressedManifests($directoryPath) {
    $xmlFiles = Get-ChildItem -Path $directoryPath -Filter "*.xml" -File -Recurse

    $sortedEntries = @()

    foreach ($xmlFile in $xmlFiles) {
        $assemblyIdentityInfo = Get-AssemblyIdentityInfo $xmlFile.FullName
        if ($assemblyIdentityInfo) {
            $sortedEntries += $assemblyIdentityInfo
        }
    }

    $sortedEntries | Sort-Object | ForEach-Object {
        Write-Output $_
    }
}

Process-DecompressedManifests $rootDirectory | Out-File "$PWD\! components.txt"

Write-Host "`n`nCompleted. " -ForegroundColor Yellow -NoNewLine
Start-Sleep 1.5
