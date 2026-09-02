# Environment

- Development environment: Windows. Your shell tool is PowerShell (pwsh if installed, otherwise Windows PowerShell 5.1).
- Use Windows-compatible commands and paths. Prefer relative paths from the working directory; when a path must be absolute, use the Windows form (`C:\Users\...` or `C:/Users/...`).
- Prefer PowerShell cmdlets and `.ps1` scripts for anything new. Do not assume Bash, Linux or macOS tools (`grep`, `sed`, `ls -la`, `chmod`, `/tmp`) are available. Use `Select-String`, `Get-ChildItem`, `Get-Content`, `$env:TEMP` instead.
- Git Bash is installed and `bash` normally resolves to it. If `bash` fails with "No such file or directory" on a `C:/...` path, WSL's `bash.exe` in System32 is shadowing it; then invoke Git Bash explicitly: `& "C:\Program Files\Git\bin\bash.exe" script.sh`.
- Native commands (git, bun, node) write progress to stderr. That is not an error; judge them by `$LASTEXITCODE`.
- Do not deliberately introduce CRLF; keep the existing line-ending style of each file.
- The shell tool exposes the current session as environment variables: read `$env:PI_PROVIDER` and `$env:PI_MODEL` instead of guessing which model is running.
