# gallery-dl PowerShell WPF Wrapper

Simple Windows PowerShell GUI front-end for [gallery-dl](https://github.com/mikf/gallery-dl).

## Features

- Destination folder picker
- List of URLs (add, paste, drag & drop, remove, clear)
- Progress bar and log output (stdout / stderr separated by tag)
- Copy log to clipboard

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- gallery-dl installed (e.g. `pip install gallery-dl`) and on PATH, or in a typical Python Scripts folder.

## Run

Right-click `GalleryDlGui.ps1` and choose "Run with PowerShell" or from a PowerShell terminal:

```powershell
pwsh -File .\GalleryDlGui.ps1
```

## Roadmap / Ideas

- Non-blocking async downloads (current version blocks UI while fetching each URL)
- Parallel downloads with a configurable concurrency limit
- Per-item status & retry
- Settings persistence (last destination path, window size)
- Dark / light theme toggle
- Drag in text files containing URLs

## License

MIT (add a LICENSE file if distributing)
