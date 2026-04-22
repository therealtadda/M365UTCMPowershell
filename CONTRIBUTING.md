# Contributing to UTCM.Tools

Thanks for your interest in contributing! This project provides a PowerShell 7+ module to work with Microsoft Graph’s Unified Tenant Configuration Management (UTCM) APIs (public preview). The goal is reliable **snapshot**, **compare**, and **report** workflows with strong engineering practices.

---

## Table of Contents
- #code-of-conduct
- #getting-started
- #development-environment
- #branching--workflow
- #coding-standards
- #tests
- #commit-messages
- #versioning
- #pull-request-checklist
- #security
- #license

---

## Code of Conduct
By participating in this project, you agree to uphold a professional, inclusive, and respectful environment. Be kind, assume good intent, and collaborate constructively.

---

## Getting Started
1. **Fork** the repository and create a feature branch from `main`.
2. Ensure you have **PowerShell 7+** installed.
3. Clone your fork and open it in **VS Code** (recommended).
4. Install required modules (see below).

---

## Development Environment

### PowerShell
- PowerShell **7.0 or later** (`pwsh`)
- Recommended extensions: **PowerShell** (VS Code)

### Required PowerShell Modules
\`\`\`powershell
# For tests
Install-Module Pester -Scope CurrentUser

# For static analysis
Install-Module PSScriptAnalyzer -Scope CurrentUser

# For manual/real Graph testing (CI runs mocked tests)
Install-Module Microsoft.Graph -Scope CurrentUser
\`\`\`

### Local Module Import
From the repository root (where `UTCM.Tools.psd1` lives):
\`\`\`powershell
Import-Module .\UTCM.Tools.psd1 -Force
Get-Command -Module UTCM.Tools
\`\`\`

If you’re iterating often:
\`\`\`powershell
Remove-Module UTCM.Tools -Force -ErrorAction SilentlyContinue
Import-Module .\UTCM.Tools.psd1 -Force
\`\`\`

---

## Branching & Workflow
- Create feature branches as `feat/<short-description>` (e.g., `feat/add-drift-filters`)
- Bugfix branches as `fix/<short-description>`
- Keep PRs **small** and **focused**
- Target `main` for PRs
- Rebase or merge `main` regularly to minimize conflicts

---

## Coding Standards
- **PowerShell 7+**, **approved verbs** (`Get-`, `New-`, `Compare-`, `Export-`, etc.)
- Public vs Private separation:
  - `Public\*.ps1` → exported cmdlets
  - `Private\*.ps1` → internal helpers
- Use **Set-StrictMode -Version Latest** (already in `.psm1`)
- Validate inputs at **bind time** (e.g., `ValidateScript` for GUIDs, `ValidateRange` for numbers)
- Prefer **pure functions**, minimal side effects
- Provide **comment-based help** for new public commands
- Keep **retry logic** centralized (use `Invoke-GraphRequestWithRetry`)
- For file IO, use `-LiteralPath` and verify directories
- Avoid breaking changes to the public surface without a major version bump

---

## Tests
- The project uses **Pester 5** with **module-scoped mocks**.
- Tests live under `.\Tests\*.Tests.ps1`.
- CI runs:
  - **PSScriptAnalyzer** (lint)
  - **Pester** (unit tests with mocks)
  - Uploads test results as artifacts

### Run Tests Locally
\`\`\`powershell
Import-Module .\UTCM.Tools.psd1 -Force
Invoke-Pester -Path .\Tests -CI
\`\`\`

> Tests must **not** require real Graph connectivity. Mock `Invoke-GraphRequestWithRetry`, `Ensure-GraphConnection`, etc.

---

## Commit Messages
Use concise, descriptive messages:
- `feat: add dashboard sorting for ID column`
- `fix: guard against null configurationItems`
- `test: add Pester for Compare-UTCMConfiguration failures`
- `docs: update README examples`

---

## Versioning
- **Semantic Versioning (SemVer)**: `MAJOR.MINOR.PATCH`
- Update `ModuleVersion` in `UTCM.Tools.psd1` when:
  - **PATCH**: bug fixes, internal refactors, doc-only
  - **MINOR**: new non-breaking features
  - **MAJOR**: breaking changes (parameters/behavior)

---

## Pull Request Checklist
- [ ] Public/Private function split correctly
- [ ] Command uses approved verbs & comment-based help
- [ ] Parameter validation at bind-time (where applicable)
- [ ] Tests added/updated (Pester 5, module-scoped mocks)
- [ ] Lint clean (PSScriptAnalyzer or CI step)
- [ ] README/Docs updated (if new user-facing functionality)

---

## Security
Do **not** include secrets in code or tests. If you find a security issue, please report it privately to the maintainers.

---

## License
By contributing, you agree your code will be released under the project’s **BSD 3‑Clause License**.