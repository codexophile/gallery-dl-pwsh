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
    $LogBox.ScrollToEnd()
}

function Add-UrlsFromText {
  param([string]$Text)
  if (-not $Text) { return }
  $urls = $Text -split "`r?`n|," |
    Where-Object { $_ -match '\S' } |
      ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^https?://'} |
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
