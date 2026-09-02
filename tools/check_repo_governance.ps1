[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:failures = New-Object "System.Collections.Generic.List[string]"

function Add-Failure {
    param([string]$Message)
    $script:failures.Add($Message)
}

$requiredPaths = @(
    "README.md",
    "AGENTS.md",
    "docs/README.md",
    "docs/DEVELOPMENT_STATUS.md",
    "docs/PROJECT_EXECUTION_ROADMAP.md",
    "docs/architecture/01_problem_definition.md",
    "docs/architecture/04_interface_dictionary.md",
    "docs/evidence/README.md",
    "docs/archive/README.md",
    "modules/README.md"
)

foreach ($relativePath in $requiredPaths) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath))) {
        Add-Failure "Missing required path: $relativePath"
    }
}

$moduleRoot = Join-Path $repoRoot "modules"
$moduleCatalogPath = Join-Path $moduleRoot "README.md"
if ((Test-Path -LiteralPath $moduleRoot) -and (Test-Path -LiteralPath $moduleCatalogPath)) {
    $moduleCatalog = Get-Content -LiteralPath $moduleCatalogPath -Raw -Encoding UTF8
    $moduleDirs = @(Get-ChildItem -LiteralPath $moduleRoot -Directory | Sort-Object Name)
    foreach ($moduleDir in $moduleDirs) {
        $expectedLink = "(" + $moduleDir.Name + "/)"
        if (-not $moduleCatalog.Contains($expectedLink)) {
            Add-Failure "Module is not registered in modules/README.md: $($moduleDir.Name)"
        }
    }
}

$activeRelativeFiles = @(
    "README.md",
    "AGENTS.md",
    "docs/README.md",
    "docs/DEVELOPMENT_STATUS.md",
    "docs/PROJECT_EXECUTION_ROADMAP.md",
    "docs/COLLABORATION.md",
    "docs/TASKS_1_5_ROUTE.md",
    "docs/ARCHITECTURE_MOP_MOE.md",
    "modules/README.md"
)

foreach ($folder in @("docs/architecture", "docs/decisions", "docs/interfaces")) {
    $folderPath = Join-Path $repoRoot $folder
    if (Test-Path -LiteralPath $folderPath) {
        $activeRelativeFiles += Get-ChildItem -LiteralPath $folderPath -Filter "*.md" -File | ForEach-Object {
            $_.FullName.Substring($repoRoot.Length + 1)
        }
    }
}

$activeRelativeFiles = $activeRelativeFiles | Sort-Object -Unique
$linkPattern = "(?<!!)\[[^\]]+\]\((?<target>[^)]+)\)"
foreach ($relativeFile in $activeRelativeFiles) {
    $filePath = Join-Path $repoRoot $relativeFile
    if (-not (Test-Path -LiteralPath $filePath)) {
        continue
    }

    $content = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
    foreach ($match in [regex]::Matches($content, $linkPattern)) {
        $target = $match.Groups["target"].Value.Trim()
        if ($target.StartsWith("<") -and $target.EndsWith(">")) {
            $target = $target.Substring(1, $target.Length - 2)
        }
        $target = ($target -split "#", 2)[0]
        if ([string]::IsNullOrWhiteSpace($target) -or $target -match "^[a-zA-Z][a-zA-Z0-9+.-]*:") {
            continue
        }

        $target = [System.Uri]::UnescapeDataString($target)
        if ($target.StartsWith("/")) {
            $resolvedTarget = Join-Path $repoRoot $target.TrimStart("/")
        } else {
            $resolvedTarget = Join-Path (Split-Path -Parent $filePath) $target
        }

        if (-not (Test-Path -LiteralPath $resolvedTarget)) {
            Add-Failure "Broken Markdown link: $relativeFile -> $target"
        }
    }
}

$staleChecks = @(
    @{ Pattern = "task1_search/"; Message = "retired task1_search path" },
    @{ Pattern = "task2_rugged/"; Message = "retired task2_rugged path" },
    @{ Pattern = "task3_wind_circle/"; Message = "retired task3_wind_circle path" },
    @{ Pattern = "speed_esc_matlab/harness/"; Message = "retired speed_esc_matlab path" },
    @{ Pattern = "当前有四个并行模块"; Message = "stale four-module count" },
    @{ Pattern = "十一个可运行模块"; Message = "stale eleven-module count" },
    @{ Pattern = "顶层Harness仍未实现"; Message = "stale Harness status" }
)

$staleFiles = @(
    "README.md",
    "AGENTS.md",
    "docs/README.md",
    "docs/DEVELOPMENT_STATUS.md",
    "docs/PROJECT_EXECUTION_ROADMAP.md",
    "docs/COLLABORATION.md",
    "docs/TASKS_1_5_ROUTE.md",
    "docs/ARCHITECTURE_MOP_MOE.md",
    "docs/architecture/01_problem_definition.md",
    "docs/architecture/03_wind_plane_control.md",
    "docs/architecture/04_interface_dictionary.md"
)

foreach ($relativeFile in $staleFiles) {
    $filePath = Join-Path $repoRoot $relativeFile
    if (-not (Test-Path -LiteralPath $filePath)) {
        continue
    }
    $content = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
    foreach ($check in $staleChecks) {
        if ($content.Contains($check.Pattern)) {
            Add-Failure "Stale wording in $relativeFile ($($check.Message)): $($check.Pattern)"
        }
    }
}

$authorshipFiles = @(
    "docs/README.md",
    "modules/README.md",
    "docs/COLLABORATION.md",
    "docs/PROJECT_EXECUTION_ROADMAP.md",
    "docs/architecture/01_problem_definition.md",
    "docs/architecture/03_wind_plane_control.md",
    "docs/architecture/04_interface_dictionary.md",
    "docs/evidence/README.md",
    "docs/archive/README.md"
)

foreach ($relativeFile in $authorshipFiles) {
    $filePath = Join-Path $repoRoot $relativeFile
    if (-not (Test-Path -LiteralPath $filePath)) {
        continue
    }
    $content = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
    foreach ($field in @("项目组", "文件负责人", "审核", "AI协助")) {
        if (-not $content.Contains($field)) {
            Add-Failure "Missing authorship field in $relativeFile : $field"
        }
    }
}

$roadmapRedirect = Join-Path $repoRoot "docs/interfaces/PROJECT_EXECUTION_ROADMAP.md"
if (Test-Path -LiteralPath $roadmapRedirect) {
    $redirectContent = Get-Content -LiteralPath $roadmapRedirect -Raw -Encoding UTF8
    if (-not $redirectContent.Contains("[已废弃路径]") -or -not $redirectContent.Contains("不再维护路线正文")) {
        Add-Failure "Roadmap compatibility page is not clearly marked as deprecated"
    }
}

$inventoryRedirect = Join-Path $repoRoot "docs/interfaces/WORKSPACE_INVENTORY_20260831.md"
if (Test-Path -LiteralPath $inventoryRedirect) {
    $inventoryContent = Get-Content -LiteralPath $inventoryRedirect -Raw -Encoding UTF8
    if (-not $inventoryContent.Contains("[已归档]")) {
        Add-Failure "Workspace inventory compatibility page is not clearly marked as archived"
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "Repository governance check: FAIL" -ForegroundColor Red
    foreach ($failure in $script:failures) {
        Write-Host " - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Repository governance check: PASS" -ForegroundColor Green
Write-Host "Registered modules: $($moduleDirs.Count)"
Write-Host "Active Markdown files checked: $($activeRelativeFiles.Count)"
