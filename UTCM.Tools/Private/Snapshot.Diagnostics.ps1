function Get-UTCMSnapshotDiagnostic {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Snapshot)

    $status = [string](Get-UTCMObjectField $Snapshot @('status'))
    $errors = @(Get-UTCMObjectField $Snapshot @('errorDetails') | Where-Object { $null -ne $_ })
    $summary = ($errors | ForEach-Object {
        if ($_ -is [string]) { $_ } else { ConvertTo-Json -InputObject $_ -Depth 99 -Compress }
    }) -join '; '
    if ($status -ne 'succeeded' -and [string]::IsNullOrWhiteSpace($summary)) {
        $summary = 'The service returned no usable errorDetails; extraction failure reasons are unavailable.'
    }

    [pscustomobject]@{
        id           = [string](Get-UTCMObjectField $Snapshot @('id'))
        status       = $status
        resources    = @(Get-UTCMObjectField $Snapshot @('resources') | Where-Object { $null -ne $_ })
        errorDetails = $errors
        errorSummary = $summary
    }
}

function Assert-UTCMComparableSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Snapshot,
        [Parameter(Mandatory)][string] $Role,
        [switch] $AllowPartialComparison
    )

    $diagnostic = Get-UTCMSnapshotDiagnostic -Snapshot $Snapshot
    if ($diagnostic.status -eq 'succeeded' -or
        ($diagnostic.status -eq 'partiallySuccessful' -and $AllowPartialComparison)) {
        return
    }

    $message = ("{0} snapshot '{1}' has status '{2}'; comparison requires succeeded snapshots. " +
        "Only partiallySuccessful snapshots can be included with -AllowPartialComparison for investigation; " +
        "their differences cannot establish reliable drift or absence of drift. {3}") -f
        $Role, $diagnostic.id, $diagnostic.status, $diagnostic.errorSummary
    $record = [System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new($message),
        'UTCM.IncompleteSnapshotComparison',
        [System.Management.Automation.ErrorCategory]::InvalidData,
        $Snapshot
    )
    $PSCmdlet.ThrowTerminatingError($record)
}

function Get-UTCMComparisonResource {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Snapshot)

    $diagnostic = Get-UTCMSnapshotDiagnostic -Snapshot $Snapshot
    if ($diagnostic.resources.Count -eq 0) {
        throw (("Snapshot '{0}' does not expose its original requested resources. Refusing to infer a reduced " +
            "comparison scope from populated configurationItems. Use Get-UTCMTenantDriftReport with " +
            "-CompareResources or -ComparePreset to choose an explicit scope.") -f $diagnostic.id)
    }
    foreach ($resource in $diagnostic.resources) {
        if ($resource -isnot [string] -or [string]::IsNullOrWhiteSpace($resource)) {
            throw "Snapshot '$($diagnostic.id)' contains an invalid original requested resource identifier."
        }
    }
    $diagnostic.resources | Select-Object -Unique
}

function Export-UTCMSnapshotDiagnostic {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Diagnostic,
        [Parameter(Mandatory)][string] $Path,
        [switch] $Overwrite
    )

    if ((Test-Path -LiteralPath $Path) -and -not $Overwrite) {
        throw "Diagnostics file '$Path' already exists. Use -Overwrite to replace it."
    }
    $payload = [ordered]@{
        generatedUtc = [datetime]::UtcNow.ToString('o')
        snapshots    = @($Diagnostic)
    }
    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    [System.IO.File]::WriteAllText($fullPath, (ConvertTo-Json -InputObject $payload -Depth 99),
        [System.Text.UTF8Encoding]::new($false))
    return $Path
}
