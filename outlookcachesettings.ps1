# Function to get the Outlook Cached Mode settings
function Get-OutlookCachedModeSettings {
    param (
        [string]$user
    )

    $outlookProfilesPath = "HKCU:\Software\Microsoft\Office"
    $versions = Get-ChildItem -Path $outlookProfilesPath -Name
    $results = @()

    foreach ($version in $versions) {
        $profilePath = Join-Path -Path $outlookProfilesPath -ChildPath "$version\Outlook\Profiles"
        Write-Host "Checking path: $profilePath"
        if (Test-Path -Path $profilePath) {
            $profiles = Get-ChildItem -Path $profilePath
            foreach ($profile in $profiles) {
                $profileKeyPath = Join-Path -Path $profilePath -ChildPath $profile
                Write-Host "Checking profile: $profileKeyPath"
                $cachedModeSetting = Get-ItemProperty -Path $profileKeyPath -Name "00036601" -ErrorAction SilentlyContinue
                if ($cachedModeSetting) {
                    $cachedModeEnabled = $cachedModeSetting.'00036601'
                    $results += [PSCustomObject]@{
                        UserProfile = $user
                        OutlookVersion = $version
                        ProfileName = $profile.PSChildName
                        CachedModeEnabled = $cachedModeEnabled
                    }
                } else {
                    Write-Host "Cached mode setting not found for profile: $profileKeyPath"
                }
            }
        } else {
            Write-Host "Path does not exist: $profilePath"
        }
    }
    return $results
}

# Get the current logged-in user
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# Get cached mode settings for the current user
$cachedModeSettings = Get-OutlookCachedModeSettings -user $currentUser

# Define the output file paths
$outputDirectory = "C:\outlookcache"
$outputCsvFilePath = Join-Path -Path $outputDirectory -ChildPath "OutputFile.csv"
$outputTxtFilePath = Join-Path -Path $outputDirectory -ChildPath "NoCachedSettings.txt"

# Create the output directory if it doesn't exist
if (-not (Test-Path -Path $outputDirectory)) { New-Item -ItemType Directory -Path $outputDirectory | Out-Null }

# Output the results to the appropriate file
if ($cachedModeSettings) {
    $cachedModeSettings | Export-Csv -Path $outputCsvFilePath -NoTypeInformation
} else {
    "No Outlook Cached Mode settings found for user $currentUser." | Out-File -FilePath $outputTxtFilePath
}
