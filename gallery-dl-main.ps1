[CmdletBinding()]
param(
  [string]$url,
  [string]$destination = 'X:\Pic\gallery-dl',
  [string]$ConfigPath = "$PSScriptRoot\gallery-dl.config.json",
  [string]$Browser,
  [string]$BrowserProfile,
  [ValidateRange(0, 100)]
  [double]$NotificationVolume = 10,
  [ValidateSet('auto-start', 'regular')]
  [string]$mode
)

Set-Location $PSScriptRoot
. ..\#lib\functions.ps1
. .\gallery-dl-functions.ps1

# Get FFmpeg location and add to base parameters
$ffmpegPath = . 'C:\mega\IDEs\powershell\ffmpeg\ffmpeg-find.ps1' -Variety yt-dlp
if ($ffmpegPath) {
  Write-Verbose "Using FFmpeg from: $ffmpegPath"
}
else {
  Write-Host $ffmpegPath
  Write-Warning 'FFmpeg not found.'
}

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
  Write-Host 'Re-launching script in STA mode for WPF...'
  $psExe = (Get-Process -Id $PID).Path
  $staArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$PSCommandPath")
  foreach ($parameter in @('url', 'destination', 'ConfigPath', 'Browser', 'BrowserProfile', 'NotificationVolume', 'mode')) {
    if ($PSBoundParameters.ContainsKey($parameter) -and $null -ne $PSBoundParameters[$parameter]) {
      $value = [string]$PSBoundParameters[$parameter]
      $value = $value -replace '(\\*)"', '$1$1\"'
      $value = $value -replace '(\\+)$', '$1$1'
      $staArgs += @("-$parameter", '"' + $value + '"')
    }
  }
  Start-Process -FilePath $psExe -ArgumentList $staArgs | Out-Null
  exit
}

Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic

if (-not ('GalleryDlOutputCapture' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Diagnostics;

public sealed class GalleryDlOutputCapture
{
  public readonly ConcurrentQueue<string> Output = new ConcurrentQueue<string>();
  public readonly ConcurrentQueue<string> Error = new ConcurrentQueue<string>();
  private readonly Process process;

  public GalleryDlOutputCapture(Process process)
  {
    this.process = process;
    process.OutputDataReceived += OnOutput;
    process.ErrorDataReceived += OnError;
  }

  public void Begin()
  {
    process.BeginOutputReadLine();
    process.BeginErrorReadLine();
  }

  private void OnOutput(object sender, DataReceivedEventArgs args)
  {
    if (args.Data != null) Output.Enqueue(args.Data);
  }

  private void OnError(object sender, DataReceivedEventArgs args)
  {
    if (args.Data != null) Error.Enqueue(args.Data);
  }
}
'@
}

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
Set-Variable -Name TotalItemsBox -Value $controls['TotalItemsBox'] -Scope Script
Set-Variable -Name ProgressBar -Value $controls['ProgressBar'] -Scope Script
Set-Variable -Name ProgressLabel -Value $controls['ProgressLabel'] -Scope Script
Set-Variable -Name LogBox -Value $controls['LogBox'] -Scope Script
Set-Variable -Name CookiesFromBrowserCheckBox -Value $controls['CookiesFromBrowserCheckBox'] -Scope Script
Set-Variable -Name BrowserComboBox -Value $controls['BrowserComboBox'] -Scope Script
Set-Variable -Name BrowserProfileComboBox -Value $controls['BrowserProfileComboBox'] -Scope Script

$browserProfiles = Get-BrowserProfiles
foreach ($browser in ($browserProfiles.Keys | Sort-Object)) {
  [void]$BrowserComboBox.Items.Add($browser)
}
if ($Browser -and -not $BrowserComboBox.Items.Contains($Browser)) {
  [void]$BrowserComboBox.Items.Add($Browser)
}
if ($BrowserComboBox.Items.Count -gt 0) {
  $BrowserComboBox.SelectedIndex = 0
}

function Update-BrowserProfiles {
  $BrowserProfileComboBox.Items.Clear()
  $browser = [string]$BrowserComboBox.SelectedItem
  if (-not $browser -or -not $browserProfiles.ContainsKey($browser)) { return }
  foreach ($DetectedBrowserProfile in $browserProfiles[$browser]) {
    [void]$BrowserProfileComboBox.Items.Add($DetectedBrowserProfile)
  }
  if ($BrowserProfileComboBox.Items.Count -gt 0) {
    $BrowserProfileComboBox.SelectedIndex = 0
  }
}

function Set-ConfiguredBrowser {
  if (-not $Browser -and -not $BrowserProfile) { return }

  if ($Browser -and -not $BrowserProfile) {
    $browserIndex = $BrowserComboBox.Items.IndexOf($Browser)
    if ($browserIndex -lt 0) {
      Add-Log "Browser is not available: $Browser" 'WARN'
      return
    }

    $BrowserComboBox.SelectedIndex = $browserIndex
    Update-BrowserProfiles
    if ($BrowserProfileComboBox.Items.Count -eq 0) {
      Add-Log "No profiles found for browser: $Browser" 'WARN'
      return
    }

    $CookiesFromBrowserCheckBox.IsChecked = $true
    return
  }

  if (-not $Browser -and $BrowserProfile) {
    $matchingBrowsers = @(
      $browserProfiles.GetEnumerator() |
        Where-Object { $_.Value -contains $BrowserProfile } |
        Select-Object -ExpandProperty Name
    )
    if ($matchingBrowsers.Count -ne 1) {
      Add-Log "Could not uniquely identify a browser for profile: $BrowserProfile" 'WARN'
      return
    }

    $Browser = $matchingBrowsers[0]
  }

  $browserIndex = $BrowserComboBox.Items.IndexOf($Browser)
  if ($browserIndex -lt 0) {
    Add-Log "Browser is not available: $Browser" 'ERROR'
    return
  }

  $BrowserComboBox.SelectedIndex = $browserIndex
  Update-BrowserProfiles
  if (-not $BrowserProfileComboBox.Items.Contains($BrowserProfile)) {
    [void]$BrowserProfileComboBox.Items.Add($BrowserProfile)
  }
  $BrowserProfileComboBox.SelectedItem = $BrowserProfile
  $CookiesFromBrowserCheckBox.IsChecked = $true
}

function Update-BrowserControls {
  $enabled = [bool]$CookiesFromBrowserCheckBox.IsChecked
  $BrowserComboBox.IsEnabled = $enabled
  $BrowserProfileComboBox.IsEnabled = $enabled
}


function Select-Folder {
  $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
  if ($DestPathBox.Text -and (Test-Path $DestPathBox.Text)) { $dialog.SelectedPath = $DestPathBox.Text }
  if ($dialog.ShowDialog() -eq 'OK') { $DestPathBox.Text = $dialog.SelectedPath }
}

function Play-NotificationSound {
  param(
    [Parameter(Mandatory)]
    [string]$Path,
    [ValidateRange(0, 100)]
    [double]$Volume = 100
  )

  if (-not (Test-Path $Path -PathType Leaf)) {
    Add-Log "Notification sound not found: $Path" 'WARN'
    return
  }

  try {
    if ($script:NotificationPlayer) {
      $script:NotificationPlayer.Close()
    }
    $script:NotificationPlayer = [System.Windows.Media.MediaPlayer]::new()
    $script:NotificationPlayer.Volume = $Volume / 100
    $script:NotificationPlayer.Open([System.Uri]::new($Path, [System.UriKind]::Absolute))
    $script:NotificationPlayer.Play()
  }
  catch [System.IO.FileNotFoundException] {
    Add-Log "Notification sound could not be loaded: $Path" 'WARN'
  }
  catch [System.InvalidOperationException] {
    Add-Log "Notification sound could not be played: $Path" 'WARN'
  }
  catch [System.ArgumentException] {
    Add-Log "Notification sound path is invalid: $Path" 'WARN'
  }
}

function ConvertTo-ProcessArgument {
  param([AllowNull()][object]$Value)
  $text = [string]$Value
  $text = $text -replace '(\\*)"', '$1$1\"'
  $text = $text -replace '(\\+)$', '$1$1'
  return '"' + $text + '"'
}

function Update-ProgressDisplay {
  param([pscustomobject]$State)
  $displayTotal = @(
    $State.EstimatedTotal
    $State.Discovered
    $State.Completed
  ) | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
  $ProgressBar.Maximum = [math]::Max(1, $displayTotal)
  $ProgressBar.Value = [math]::Min($State.Completed, $ProgressBar.Maximum)
  $ProgressLabel.Text = "$($State.Completed)/$displayTotal items"
}

function Update-ItemProgress {
  param(
    [pscustomobject]$State,
    [string]$Event,
    [string]$Path
  )
  if ($Event -eq 'prepare') {
    $State.Discovered++
    Update-ProgressDisplay -State $State
    Add-Log "Queued item: $Path" 'OUT'
  }
  elseif ($Event -eq 'download') {
    $State.Completed++
    Update-ProgressDisplay -State $State
    Add-Log "Downloaded item: $Path" 'OUT'
  }
}

function Clear-DownloadOutput {
  param(
    [GalleryDlOutputCapture]$Capture,
    [pscustomobject]$State
  )
  $line = $null
  while ($Capture.Output.TryDequeue([ref]$line)) {
    if ($line.StartsWith('__GDL_PREPARE__')) {
      Update-ItemProgress -State $State -Event 'prepare' -Path $line.Substring('__GDL_PREPARE__'.Length)
    }
    elseif ($line.StartsWith('__GDL_DOWNLOAD__')) {
      Update-ItemProgress -State $State -Event 'download' -Path $line.Substring('__GDL_DOWNLOAD__'.Length)
    }
    else {
      Add-Log $line 'OUT'
    }
  }
  while ($Capture.Error.TryDequeue([ref]$line)) {
    Add-Log $line 'ERR'
  }
}

function Invoke-Downloads {
  if (-not (Test-GalleryDlInstalled)) { return }
  $dest = $DestPathBox.Text.Trim()
  if (-not $dest) { Add-Log 'Destination path is empty.' 'WARN'; return }
  if (-not (Test-Path $ConfigPath -PathType Leaf)) {
    Add-Log "Configuration file not found: $ConfigPath" 'ERROR'
    return
  }
  try {
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force -ErrorAction Stop | Out-Null }
  }
  catch {
    Add-Log "Cannot access destination path '$dest': $($_.Exception.Message)" 'ERROR'
    return
  }
  $urls = @($UrlListBox.Items | ForEach-Object { $_ })
  if (-not $urls) { Add-Log 'No URLs to download.' 'WARN'; return }
  $estimatedTotal = $urls.Count
  if ($TotalItemsBox.Text.Trim()) {
    if (-not [int]::TryParse($TotalItemsBox.Text.Trim(), [ref]$estimatedTotal) -or
      $estimatedTotal -le 0) {
      Add-Log 'Total media items must be a positive whole number, or left blank.' 'WARN'
      return
    }
  }
  $galleryDl = Get-GalleryDlExecutable
  Add-Log "Using: $galleryDl"
  Add-Log "Output root: $dest (gallery-dl may create subfolders from the configuration)"
  $total = $urls.Count
  $ProgressBar.Minimum = 0; $ProgressBar.Maximum = 1; $ProgressBar.Value = 0
  $ProgressLabel.Text = '0/0 items'
  $controls['DownloadBtn'].IsEnabled = $false
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $progressState = [pscustomobject]@{
    EstimatedTotal = $estimatedTotal
    Discovered     = 0
    Completed      = 0
  }
  Update-ProgressDisplay -State $progressState
  $i = 0
  $ErroredCount = 0
  foreach ($url in $urls) {
    $i++
    Add-Log "[$i/$total] Downloading $url" 'INFO'
    $completedBeforeUrl = $progressState.Completed
    $dlArgs = @('--config', $ConfigPath)
    if ($ffmpegPath) {
      $ytdlArguments = @('--ffmpeg-location', $ffmpegPath) | ConvertTo-Json -Compress
      $dlArgs += @(
        '--option',
        "downloader.ytdl.cmdline-args=$ytdlArguments"
      )
    }
    if ($CookiesFromBrowserCheckBox.IsChecked) {
      $browser = [string]$BrowserComboBox.SelectedItem
      $DetectedBrowserProfile = [string]$BrowserProfileComboBox.SelectedItem
      if (-not $browser -or -not $DetectedBrowserProfile) {
        Add-Log 'Select a browser and profile, or disable browser cookies.' 'WARN'
        $controls['DownloadBtn'].IsEnabled = $true
        return
      }
      $dlArgs += @('--cookies-from-browser', "$browser`:$DetectedBrowserProfile")
    }
    $dlArgs += @(
      '-d', $dest,
      '--Print', 'prepare:__GDL_PREPARE__{_path}',
      '--Print', 'after:__GDL_DOWNLOAD__{_path}',
      $url
    )
    $dlArgs = @($dlArgs | ForEach-Object { ConvertTo-ProcessArgument $_ })
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $galleryDl
    $psi.Arguments = ($dlArgs -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $capture = [GalleryDlOutputCapture]::new($proc)
    $capture.Begin()
    while (-not $proc.WaitForExit(100)) {
      Clear-DownloadOutput -Capture $capture -State $progressState
      $Window.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
    }
    $proc.WaitForExit()
    Clear-DownloadOutput -Capture $capture -State $progressState
    $downloadedForUrl = $progressState.Completed - $completedBeforeUrl
    if ($proc.ExitCode -eq 0 -and $downloadedForUrl -gt 0) {
      Add-Log "Completed: $url ($downloadedForUrl file(s))" 'OK'
    }
    elseif ($proc.ExitCode -eq 0) {
      Add-Log "No files downloaded for: $url. The URL may contain no accessible media or all files may already exist." 'WARN'
    }
    else {
      Add-Log "Failed (code $($proc.ExitCode)): $url" 'ERROR'
      $ErroredCount++
    }
  }
  $sw.Stop()
  Add-Log "All done in $([math]::Round($sw.Elapsed.TotalSeconds,2))s" 'DONE'
  $controls['DownloadBtn'].IsEnabled = $true
  if ($ErroredCount -eq 0) {
    $notificationPath = Join-Path $PSScriptRoot 'notification.wav'
    Play-NotificationSound -Path $notificationPath -Volume $NotificationVolume
    CountDown 15
    exitAndCloseTerminal
  }
}

# Event wiring
$controls['BrowseBtn'].Add_Click({ Select-Folder })
$BrowserComboBox.Add_SelectionChanged({ Update-BrowserProfiles })
$CookiesFromBrowserCheckBox.Add_Click({ Update-BrowserControls })
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

if ($destination) { $DestPathBox.Text = $destination }
if ($url) { Add-UrlsFromText -Text $url }
Update-BrowserProfiles
Set-ConfiguredBrowser
Update-BrowserControls

$Window.add_Closing({
    if ($script:NotificationPlayer) {
      $script:NotificationPlayer.Close()
    }
    [Environment]::Exit(0)
  })

Add-Log 'Ready.'

$null = Show-WpfFormOnMonitor $Window 0 $true
