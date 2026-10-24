# Windows Installation Guide

sejong-slide prepares Python and its packages on first use. You do not need to install Python or configure PATH beforehand. Use Windows 10/11 with PowerShell 5.1 or newer and an internet connection for the initial download.

## 1. Download the repository

Clone the public repository:

```powershell
git clone https://github.com/yaco9304-sketch/sejong-slide.git
cd sejong-slide
```

Without Git, use **Code → Download ZIP** on [GitHub](https://github.com/yaco9304-sketch/sejong-slide), then extract the entire archive. Keep the hidden `.claude` and `.codex` directories.

## 2. Open the folder in your AI editor

Open the downloaded `sejong-slide` folder in Codex, Claude Code, or another supported AI editor, then ask it to create a presentation. The repository instructions use the launcher for Python tools. It prepares Python and packages automatically when the agent first runs a tool; no separate setup step is needed.

The AI editor itself is a separate prerequisite.

## Optional: prepare the runtime yourself

Double-click **`sejong-slide.cmd`**, or run it in PowerShell:

```powershell
.\sejong-slide.cmd
```

The launcher:

1. Finds an existing Python 3.10+ installation, or downloads managed Python 3.12 when none is available.
2. Creates a local `.venv` and installs `requirements.txt` using uv.
3. Checks the core imports, dependency compatibility, and repository skill connections.
4. Reuses the prepared environment on later runs.

The bootstrap tool, managed Python, and download cache live in `.sejong-tools`. Packages live in `.venv`. Neither directory is committed. The installer does not require administrator privileges, edit the persistent PATH, or change the system Python. Its PowerShell execution-policy option applies only to the launched process.

The bootstrap downloads come from [Astral's official installer](https://docs.astral.sh/uv/reference/installer/) and its [managed Python distribution](https://docs.astral.sh/uv/guides/install-python/); Python packages come from the configured package index (PyPI by default).

## Slide fonts

For consistent slide appearance, install the bundled Pretendard `.otf` files from `.claude\skills\ppt-master\assets\fonts\Pretendard` in Windows Fonts settings. Generated PPTX files do not embed fonts.

## Direct commands

Pass a script and its arguments to the launcher:

```powershell
.\sejong-slide.cmd .claude/skills/ppt-master/scripts/project_manager.py --help
.\sejong-slide.cmd --check
.\sejong-slide.cmd --setup
```

`--check` performs an offline installation check without downloading anything. `--setup` reruns setup to refresh dependencies or recover from an interrupted download. Use one of these options alone. Ordinary Python arguments, including `-c` and `-m`, are also supported.

## Troubleshooting

### Downloads fail

Check the internet connection and any organization proxy settings, then rerun `sejong-slide.cmd --setup`. Allow HTTPS access to `astral.sh`, GitHub releases, and the Python package index. Do not disable TLS certificate checks.

### Existing `.venv` is unusable

This can happen after moving the repository or removing its original Python installation. Close processes using this project, rename `.venv`, then run `sejong-slide.cmd --setup`. The installer leaves the old directory in place for you to inspect; it does not delete it automatically.

### PowerShell is blocked by organization policy

The launcher uses the built-in Windows PowerShell. Organization-enforced policies may still prevent script execution. Ask your administrator to permit the local launcher; it does not change those policies.

### `python` still opens Microsoft Store

Use `sejong-slide.cmd` instead of the global `python` command. Managed Python is intentionally local to this repository and is not added to the persistent PATH.

### Need help

Open an issue at [sejong-slide/issues](https://github.com/yaco9304-sketch/sejong-slide/issues) with the Windows version and the complete error message. Do not include API keys or private material.
