function Get-GalleryDlExecutable {
  $candidates = @()
  $cmd = Get-Command gallery-dl -ErrorAction SilentlyContinue
  if ($cmd) { $candidates += $cmd.Source }
  $candidates += @(
    "$env:APPDATA\Python\Scripts\gallery-dl.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python*\Scripts\gallery-dl.exe"
  ) | ForEach-Object { Get-Item -Path $_ -ErrorAction SilentlyContinue } | ForEach-Object FullName
  $exe = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  if (-not $exe) { throw 'gallery-dl executable not found. Install with: pip install gallery-dl' }
  return $exe
}

function Add-Log {
  param([string]$Message, [string]$Level = 'INFO')
  $ts = (Get-Date).ToString('HH:mm:ss')
  $line = "[$ts][$Level] $Message"
  $LogBox.AppendText("$line`r`n")
  $LogBox.UpdateLayout()
  $LogBox.ScrollToEnd()
}

function Add-UrlsFromText {
  param([string]$Text)
  if (-not $Text) { return }
  $urls = $Text -split "`r?`n|," |
  Where-Object { $_ -match '\S' } |
  ForEach-Object { $_.Trim() } |
  Where-Object { $_ -match '^https?://' } |
  Select-Object -Unique
  foreach ($u in $urls) {
    if (-not $UrlListBox.Items.Contains($u)) {
      [void]$UrlListBox.Items.Add($u)
    }
  }
  if ($urls) { Add-Log "Added $($urls.Count) URL(s)." }
}

function Test-GalleryDlInstalled {
  try { [void](Get-GalleryDlExecutable); return $true } catch { Add-Log $_.Exception.Message 'ERROR'; return $false }
}

function Get-BrowserProfiles {
  $browsers = @{}

  function Get-ChromiumProfiles {
    param([string]$Path)
    if (-not (Test-Path $Path -PathType Container)) { return @() }
    $profiles = @(
      Get-ChildItem -Path $Path -Directory -Filter 'Profile *' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name
    )
    if (Test-Path (Join-Path $Path 'Default') -PathType Container) {
      $profiles = @('Default') + $profiles
    }
    return $profiles
  }

  $firefoxProfilesPath = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
  if (Test-Path $firefoxProfilesPath -PathType Container) {
    $profiles = @(
      Get-ChildItem -Path $firefoxProfilesPath -Directory -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name
    )
    if ($profiles) { $browsers['firefox'] = $profiles }
  }

  $browserPaths = [ordered]@{
    brave   = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'
    chrome  = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
    edge    = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'
    vivaldi = Join-Path $env:LOCALAPPDATA 'Vivaldi\User Data'
    opera   = Join-Path $env:APPDATA 'Opera Software\Opera Stable'
  }

  foreach ($browser in $browserPaths.GetEnumerator()) {
    $profiles = @(Get-ChromiumProfiles -Path $browser.Value)
    if ($profiles) { $browsers[$browser.Name] = $profiles }
  }

  if ((Test-Path $browserPaths.opera -PathType Container) -and
      -not $browsers.ContainsKey('opera')) {
    $browsers['opera'] = @('Default')
  }

  return $browsers
}
