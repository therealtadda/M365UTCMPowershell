function New-UTCMMonitor {
    <#
    .SYNOPSIS
        Creates a new UTCM configuration monitor for automated drift detection.

    .DESCRIPTION
        Creates a configurationMonitor via
        POST /beta/admin/configurationManagement/configurationMonitors.
        Monitors run periodically (every 6 hours at fixed GMT times: 6 AM, 12 PM, 6 PM, 12 AM)
        and compare the current tenant configuration against the specified baseline.

        The baseline defines which resources and property values to monitor. When a property
        drifts from its desired value, the API records a configurationDrift that can be
        queried via Get-UTCMDrift.

    .PARAMETER DisplayName
        Friendly name for the monitor. Required.

    .PARAMETER Description
        Optional description.

    .PARAMETER BaselineDisplayName
        Friendly name for the baseline attached to the monitor. Default: same as monitor DisplayName.

    .PARAMETER BaselineDescription
        Optional description for the baseline.

    .PARAMETER BaselineResources
        Array of hashtables defining resources to monitor. Each hashtable must have:
          - displayName (string): friendly name for this resource instance
          - resourceType (string): UTCM resource type (e.g., microsoft.exchange.sharedmailbox)
          - properties (hashtable): key-value pairs of the desired configuration state

    .PARAMETER SnapshotId
        Alternative to -BaselineResources. GUID of an existing UTCM snapshot whose
        captured configuration items will be converted into the baseline. Internally
        fetches the snapshot via Get-UTCMSnapshot -IncludeItems and pipes its items
        through ConvertTo-UTCMMonitorResource, applying any of the filtering
        parameters below.

    .PARAMETER ResourceType
        When sourcing from -SnapshotId: optional resource-type allow-list used to
        narrow the snapshot down to just the types you want to monitor.

    .PARAMETER Identity
        When sourcing from -SnapshotId: optional id allow-list (matched against the
        normalized item id).

    .PARAMETER IncludeProperty
        When sourcing from -SnapshotId: optional property allow-list. Only these
        property names are carried into each resource's baseline properties.

    .PARAMETER ExcludeProperty
        When sourcing from -SnapshotId: optional property deny-list, applied after
        IncludeProperty.

    .PARAMETER Parameters
        Optional hashtable of key-value pairs that can be referenced in the baseline.

    .OUTPUTS
        PSObject representing the created configurationMonitor.

    .EXAMPLE
        $resources = @(
            @{
                displayName  = 'TestSharedMailbox Resource'
                resourceType = 'microsoft.exchange.sharedmailbox'
                properties   = @{
                    DisplayName      = 'TestSharedMailbox'
                    Alias            = 'testSharedMailbox'
                    Identity         = 'TestSharedMailbox'
                    Ensure           = 'Present'
                    PrimarySmtpAddress = 'testSharedMailbox@contoso.onmicrosoft.com'
                }
            }
        )
        New-UTCMMonitor -DisplayName 'Exchange Monitor' -BaselineResources $resources

    .EXAMPLE
        # Monitor an accepted domain stays present
        $resources = @(
            @{
                displayName  = 'Accepted Domain'
                resourceType = 'microsoft.exchange.accepteddomain'
                properties   = @{
                    Identity   = 'contoso.onmicrosoft.com'
                    DomainType = 'InternalRelay'
                    Ensure     = 'Present'
                }
            }
        )
        New-UTCMMonitor -DisplayName 'Domain Monitor' -Description 'Ensure domain stays present' -BaselineResources $resources

    .EXAMPLE
        # Build a monitor from an existing snapshot, filtered to a single resource type
        New-UTCMMonitor -DisplayName 'Shared Mailbox Monitor' `
            -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' `
            -ResourceType microsoft.exchange.sharedmailbox

    .EXAMPLE
        # Build a monitor from a snapshot, keeping only specific properties
        New-UTCMMonitor -DisplayName 'Domain Monitor' `
            -SnapshotId $snapshotId `
            -ResourceType microsoft.exchange.accepteddomain `
            -IncludeProperty Identity,DomainType,Ensure
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'FromResources')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $DisplayName,

        [string] $Description,

        [string] $BaselineDisplayName,

        [string] $BaselineDescription,

        [Parameter(Mandatory, ParameterSetName = 'FromResources')]
        [ValidateNotNullOrEmpty()]
        [hashtable[]] $BaselineResources,

        [Parameter(Mandatory, ParameterSetName = 'FromSnapshot')]
        [ValidateScript({
            if (-not (Validate-Guid $_)) { throw "SnapshotId '$_' is not a valid GUID." }
            $true
        })]
        [string] $SnapshotId,

        [Parameter(ParameterSetName = 'FromSnapshot')]
        [string[]] $ResourceType,

        [Parameter(ParameterSetName = 'FromSnapshot')]
        [string[]] $Identity,

        [Parameter(ParameterSetName = 'FromSnapshot')]
        [string[]] $IncludeProperty,

        [Parameter(ParameterSetName = 'FromSnapshot')]
        [string[]] $ExcludeProperty,

        [hashtable] $Parameters
    )

    if (Get-Command -Name Ensure-GraphConnection -ErrorAction SilentlyContinue) {
        Ensure-GraphConnection
    }

    if (-not $BaselineDisplayName) {
        $BaselineDisplayName = "$DisplayName Baseline"
    }

    # If sourcing from a snapshot, materialize BaselineResources via the converter.
    if ($PSCmdlet.ParameterSetName -eq 'FromSnapshot') {
        if (-not (Get-Command -Name ConvertTo-UTCMMonitorResource -ErrorAction SilentlyContinue)) {
            throw "ConvertTo-UTCMMonitorResource is not available; cannot build baseline from snapshot."
        }

        $convertParams = @{ SnapshotId = $SnapshotId }
        if ($ResourceType)    { $convertParams['ResourceType']    = $ResourceType }
        if ($Identity)        { $convertParams['Identity']        = $Identity }
        if ($IncludeProperty) { $convertParams['IncludeProperty'] = $IncludeProperty }
        if ($ExcludeProperty) { $convertParams['ExcludeProperty'] = $ExcludeProperty }

        $BaselineResources = @(ConvertTo-UTCMMonitorResource @convertParams)

        if (-not $BaselineResources -or $BaselineResources.Count -eq 0) {
            throw ("Snapshot '{0}' produced no resources for the supplied filters; nothing to monitor." -f $SnapshotId)
        }
    }

    # Build baseline resource objects
    $resourceObjects = foreach ($res in $BaselineResources) {
        if (-not $res.displayName -or -not $res.resourceType -or -not $res.properties) {
            throw "Each BaselineResources entry must have 'displayName', 'resourceType', and 'properties' keys."
        }
        @{
            displayName  = $res.displayName
            resourceType = $res.resourceType
            properties   = $res.properties
        }
    }

    $body = @{
        displayName = $DisplayName
        baseline    = @{
            displayName = $BaselineDisplayName
            resources   = @($resourceObjects)
        }
    }

    if ($Description) {
        $body['description'] = $Description
    }
    if ($BaselineDescription) {
        $body['baseline']['description'] = $BaselineDescription
    }
    if ($Parameters) {
        $body['parameters'] = $Parameters
    }

    if (-not $PSCmdlet.ShouldProcess($DisplayName, "Create UTCM configuration monitor")) {
        return
    }

    if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Message ("Creating UTCM monitor: {0} (resources={1})" -f $DisplayName, ($resourceObjects.Count)) -Color Cyan
    }

    $result = Invoke-GraphRequestWithRetry -Method 'POST' -Uri $script:ConfigurationMonitorsUri -Body $body

    if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Message ("Monitor created: {0} (id={1}, status={2})" -f $result.displayName, $result.id, $result.status) -Color Green
    }

    return $result
}
