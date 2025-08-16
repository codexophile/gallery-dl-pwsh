<#!
gallery-dl WPF GUI wrapper
Requirements: PowerShell 5+ (Windows), gallery-dl installed and on PATH (pip install gallery-dl) or detectable in typical Python Scripts folders.
#>

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
  Write-Host 'Re-launching script in STA mode for WPF...'
  $psExe = (Get-Process -Id $PID).Path
  $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"$PSCommandPath")
  Start-Process -FilePath $psExe -ArgumentList $args | Out-Null
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

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="gallery-dl Wrapper" Height="520" Width="860" WindowStartupLocation="CenterScreen" Background="#1e1e1e" Foreground="#e0e0e0">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Margin" Value="4"/>
      <Setter Property="Padding" Value="6,3"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Margin" Value="4"/>
    </Style>
    <Style TargetType="Label">
      <Setter Property="Margin" Value="4"/>
    </Style>
  </Window.Resources>
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="120"/>
    </Grid.RowDefinitions>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <!-- Destination Path -->
    <DockPanel Grid.Row="0" LastChildFill="True" Margin="6">
      <Label Content="Destination Path:" VerticalAlignment="Center"/>
      <TextBox Name="DestPathBox" MinWidth="400" ToolTip="Folder to save downloads"/>
      <Button Name="BrowseBtn" Content="Browse..." Width="90"/>
    </DockPanel>

    <!-- URL Controls -->
    <DockPanel Grid.Row="1" LastChildFill="True" Margin="6">
  <Label Content="URLs (drag &amp; drop links or paste multi-line):" VerticalAlignment="Center"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button Name="PasteBtn" Content="Paste"/>
        <Button Name="AddBtn" Content="Add"/>
        <Button Name="RemoveBtn" Content="Remove"/>
        <Button Name="ClearBtn" Content="Clear"/>
        <Button Name="DownloadBtn" Content="Download" Background="#007acc" Foreground="White"/>
      </StackPanel>
    </DockPanel>

    <!-- URLs List -->
    <Border Grid.Row="2" Margin="6" BorderBrush="#333" BorderThickness="1" CornerRadius="4" Background="#252526">
      <ListBox Name="UrlListBox" AllowDrop="True" Background="#252526" Foreground="#e0e0e0" BorderThickness="0"/>
    </Border>

  <!-- Progress and Status -->
    <Grid Grid.Row="3" Margin="6">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <ProgressBar Name="ProgressBar" Height="20" Margin="0,0,8,0" Grid.Column="0" Minimum="0" Maximum="100"/>
      <TextBlock Name="ProgressLabel" Grid.Column="1" VerticalAlignment="Center" Text="0/0"/>
    </Grid>

    <!-- Log -->
    <GroupBox Grid.Row="4" Header="Log" Margin="6" Foreground="#e0e0e0">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Grid.Row="0">
          <TextBox Name="LogBox" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" Background="#1e1e1e" Foreground="#c8c8c8" BorderThickness="0"/>
        </ScrollViewer>
        <Button Name="CopyLogBtn" Grid.Row="1" Content="Copy Log" HorizontalAlignment="Right" Margin="4" Width="90"/>
      </Grid>
    </GroupBox>
  </Grid>
 </Window>
'@

# Parse XAML directly (avoid XML DOM parsing issues with entity handling in comments)
$Window = [Windows.Markup.XamlReader]::Parse($xaml)

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

function Browse-Folder {
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
        $args = @('--ignore-config', '-d', $dest, $url) | ForEach-Object { '"' + $_.Replace('"','\"') + '"' }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $galleryDl
        $psi.Arguments = ($args -join ' ')
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
$controls['BrowseBtn'].Add_Click({ Browse-Folder })
$controls['AddBtn'].Add_Click({
    $input = [Microsoft.VisualBasic.Interaction]::InputBox('Enter URL(s) (one per line)', 'Add URLs')
    Add-UrlsFromText -Text $input
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
