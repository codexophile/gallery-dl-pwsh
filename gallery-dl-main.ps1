<#!
gallery-dl WPF GUI wrapper
Requirements: PowerShell 5+ (Windows), gallery-dl installed and on PATH (pip install gallery-dl) or detectable in typical Python Scripts folders.
#>

. ..\#lib\functions.ps1

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
  Write-Host 'Re-launching script in STA mode for WPF...'
  $psExe = (Get-Process -Id $PID).Path
  $staArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"$PSCommandPath")
  Start-Process -FilePath $psExe -ArgumentList $staArgs | Out-Null
  exit
}

Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic

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

# Parse XAML directly (avoid XML DOM parsing issues with entity handling in comments)
$Window = GuiFromXaml ./main-ui.xaml

# Helper: walk logical tree to collect named elements
function Get-NamedElements {
  param([System.Windows.DependencyObject]$Root)
  $dict = @{}
  function _walk([System.Windows.DependencyObject]$node) {
    if (-not $node) { return }
    $nameProp = $node.GetType().GetProperty('Name')
    if ($nameProp) {
      $val = $nameProp.GetValue($node, $null)
      if ($val) { $dict[$val] = $node }
    }
    foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($node)) {
      if ($child -is [System.Windows.DependencyObject]) { _walk $child }
    }
  }
  _walk $Root
  return $dict
}

$controls = Get-NamedElements -Root $Window
Set-Variable -Name UrlListBox -Value $controls['UrlListBox'] -Scope Script
Set-Variable -Name DestPathBox -Value $controls['DestPathBox'] -Scope Script
Set-Variable -Name ProgressBar -Value $controls['ProgressBar'] -Scope Script
Set-Variable -Name ProgressLabel -Value $controls['ProgressLabel'] -Scope Script
Set-Variable -Name LogBox -Value $controls['LogBox'] -Scope Script

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
    $urls = $Text -split "`r?`n" | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^https?://'} | Select-Object -Unique
    foreach ($u in $urls) { if (-not $UrlListBox.Items.Contains($u)) { [void]$UrlListBox.Items.Add($u) } }
    if ($urls) { Add-Log "Added $($urls.Count) URL(s)." }
}

function Select-Folder {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($DestPathBox.Text -and (Test-Path $DestPathBox.Text)) { $dialog.SelectedPath = $DestPathBox.Text }
    if ($dialog.ShowDialog() -eq 'OK') { $DestPathBox.Text = $dialog.SelectedPath }
}

function Test-GalleryDlInstalled {
    try { [void](Get-GalleryDlExecutable); return $true } catch { Add-Log $_.Exception.Message 'ERROR'; return $false }
}

function Invoke-Downloads {
    if (-not (Test-GalleryDlInstalled)) { return }
    $dest = $DestPathBox.Text.Trim()
    if (-not $dest) { Add-Log 'Destination path is empty.' 'WARN'; return }
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
    $urls = @($UrlListBox.Items | ForEach-Object { $_ })
    if (-not $urls) { Add-Log 'No URLs to download.' 'WARN'; return }
    $galleryDl = Get-GalleryDlExecutable
    Add-Log "Using: $galleryDl"
    $total = $urls.Count
    $ProgressBar.Minimum = 0; $ProgressBar.Maximum = $total; $ProgressBar.Value = 0
    $ProgressLabel.Text = "0/$total"
    $controls['DownloadBtn'].IsEnabled = $false
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $i = 0
    foreach ($url in $urls) {
        $i++
        Add-Log "[$i/$total] Downloading $url" 'INFO'
        $dlArgs = @('--ignore-config', '-d', $dest, $url) | ForEach-Object { '"' + $_.Replace('"','\"') + '"' }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $galleryDl
        $psi.Arguments = ($dlArgs -join ' ')
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdOut = $proc.StandardOutput.ReadToEnd()
        $stdErr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        if ($stdOut) { Add-Log $stdOut.TrimEnd() 'OUT' }
        if ($stdErr) { Add-Log $stdErr.TrimEnd() 'ERR' }
        if ($proc.ExitCode -eq 0) { Add-Log "Completed: $url" 'OK' } else { Add-Log "Failed (code $($proc.ExitCode)): $url" 'ERROR' }
        $ProgressBar.Value = $i
        $ProgressLabel.Text = "$i/$total"
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    }
    $sw.Stop()
    Add-Log "All done in $([math]::Round($sw.Elapsed.TotalSeconds,2))s" 'DONE'
    $controls['DownloadBtn'].IsEnabled = $true
}

# Event wiring
$controls['BrowseBtn'].Add_Click({ Select-Folder })
$controls['AddBtn'].Add_Click({
    $userInput = [Microsoft.VisualBasic.Interaction]::InputBox('Enter URL(s) (one per line)', 'Add URLs')
    Add-UrlsFromText -Text $userInput
})
$controls['PasteBtn'].Add_Click({
    if ([System.Windows.Clipboard]::ContainsText()) {
        Add-UrlsFromText -Text ([System.Windows.Clipboard]::GetText())
    }
})
$controls['RemoveBtn'].Add_Click({
    $sel = @($UrlListBox.SelectedItems | ForEach-Object { $_ })
    foreach ($s in $sel) { $UrlListBox.Items.Remove($s) }
    if ($sel) { Add-Log "Removed $($sel.Count) item(s)." }
})
$controls['ClearBtn'].Add_Click({ $UrlListBox.Items.Clear(); Add-Log 'Cleared URL list.' })
$controls['DownloadBtn'].Add_Click({ Invoke-Downloads })
$controls['CopyLogBtn'].Add_Click({ [System.Windows.Clipboard]::SetText($LogBox.Text); Add-Log 'Log copied to clipboard.' })

# Drag & Drop support
$UrlListBox.Add_PreviewDragOver({
    if ($_.Data.GetDataPresent([Windows.DataFormats]::Text)) { $_.Effects = 'Copy' }
    $_.Handled = $true
})
$UrlListBox.Add_Drop({
    if ($_.Data.GetDataPresent([Windows.DataFormats]::Text)) {
        $data = $_.Data.GetData([Windows.DataFormats]::Text)
        Add-UrlsFromText -Text $data
    }
})

Add-Log 'Ready.'

$Window.ShowDialog() | Out-Null
