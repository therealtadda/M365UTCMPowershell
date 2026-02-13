function Invoke-GraphRequestWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','PATCH','DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        $Body = $null,
        [int]$MaxRetries = 5
    )

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try {
            $attempt++
            if ($null -ne $Body) {
                return Invoke-MgGraphRequest -Method $Method -Uri $Uri -Body ($Body | ConvertTo-Json -Depth 50)
            } else {
                return Invoke-MgGraphRequest -Method $Method -Uri $Uri
            }
        } catch {
            $ex = $_.Exception
            $message = $ex.Message

            # Check for throttling/temporary issues (429/503)
            if ($_.Exception.Response -and ($_.Exception.Response.StatusCode.Value__ -in  @([int]429,[int]503))) {
                $retryAfter = 0
                try {
                    $retryAfter = [int]$_.Exception.Response.Headers['Retry-After']
                } catch { $retryAfter = 0 }

                if ($retryAfter -le 0) {
                    $retryAfter = [math]::Min(60, [math]::Pow(2, $attempt))  # exponential backoff cap 60s
                }

                Write-Log -Message "Graph throttled/temporarily unavailable (attempt $attempt). Retrying in $retryAfter sec..." -Color Yellow
                Start-Sleep -Seconds $retryAfter
                continue
            }

            if ($attempt -ge $MaxRetries) {
                throw "Graph request failed after $MaxRetries attempts. Method=$Method Uri=$Uri Error: $message"
            }

            # Unknown transient error—retry with backoff
            $delay = [math]::Min(30, [math]::Pow(2,$attempt))
            Write-Log -Message "Transient error (attempt $attempt): $message. Retrying in $delay sec..." -Color Yellow
            Start-Sleep -Seconds $delay
        }
    }
}