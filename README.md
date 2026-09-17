# gallery-dl PowerShell WPF Wrapper

Simple Windows PowerShell GUI front-end for [gallery-dl](https://github.com/mikf/gallery-dl).

## Features

- Destination folder picker
- List of URLs (add, paste, drag & drop, remove, clear)
- Per-media-item progress bar and log output (stdout / stderr separated by tag)
- Copy log to clipboard

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- gallery-dl installed (e.g. `pip install gallery-dl`) and on PATH, or in a typical Python Scripts folder.

## Run

Right-click `GalleryDlGui.ps1` and choose "Run with PowerShell" or from a PowerShell terminal:

```powershell
pwsh -File .\GalleryDlGui.ps1
```

The progress bar counts completed media items, not source URLs. gallery-dl discovers
the total while processing each URL, so the label starts at `0/0 items` and updates
as items are queued and downloaded. Output and errors are appended to the log as
gallery-dl emits them.

The destination is the output root. The included configuration organizes Facebook
sets below that root as `facebook\<username>\set_<id>`, so files may not appear
directly in the selected folder. A successful process with no downloaded items is
reported as a warning, rather than as a completed download.

The wrapper also handles Windows paths ending in a backslash when launching
gallery-dl, so a selected folder such as `C:\Users\you\Downloads\` is valid.

## Roadmap / Ideas

- Parallel downloads with a configurable concurrency limit
- Per-item status & retry
- Settings persistence (last destination path, window size)
- Dark / light theme toggle
- Drag in text files containing URLs

## License

MIT (add a LICENSE file if distributing)
