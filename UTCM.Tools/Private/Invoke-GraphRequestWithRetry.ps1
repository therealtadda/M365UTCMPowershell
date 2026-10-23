function Invoke-GraphRequestWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','PATCH','DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        $Body = $null,
        [hashtable]$Headers = @{},
        [ValidateRange(1,2147483647)][int]$MaxRetries = 5,
        [string]$OutputFilePath
    )

    $requestUri = Resolve-UTCMGraphUri -Uri $Uri
    $logUri = ([uri]$requestUri).GetLeftPart([UriPartial]::Path)
    $request = @{ Method = $Method; Uri = $requestUri; ErrorAction = 'Stop' }
    if ($null -ne $Body) {
        $request.Body = $Body
        $request.ContentType = 'application/json'
    }
    if ($Headers.Count -gt 0) { $request.Headers = $Headers }
    if ($PSBoundParameters.ContainsKey('OutputFilePath')) { $request.OutputFilePath = $OutputFilePath }

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try {
            $attempt++
            return Invoke-MgGraphRequest @request
        } catch {
            $ex = $_.Exception
            $message = $ex.Message

            # ── Try to extract the Graph API error detail ──
            # Invoke-MgGraphRequest puts the response body in multiple places
            # depending on SDK version. We check them all.
            $graphErrorDetail = $null
            try {
                # 1. PowerShell ErrorRecord.ErrorDetails.Message (most reliable)
                if (-not $graphErrorDetail -and $_.ErrorDetails -and $_.ErrorDetails.Message) {
                    $graphErrorDetail = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
                }
                # 2. Exception.Response (HttpResponseMessage) — read body stream
                if (-not $graphErrorDetail -and $ex.Response) {
                    $httpResp = $ex.Response
                    if ($httpResp.Content) {
                        $bodyText = $httpResp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                        if ($bodyText) {
                            $graphErrorDetail = $bodyText | ConvertFrom-Json -ErrorAction SilentlyContinue
                        }
                    }
                }
                # 3. SDK v2+ may expose .ResponseBody directly
                if (-not $graphErrorDetail -and $ex.PSObject.Properties.Name -contains 'ResponseBody') {
                    $graphErrorDetail = $ex.ResponseBody | ConvertFrom-Json -ErrorAction SilentlyContinue
                }
                # 4. InnerException chain
                if (-not $graphErrorDetail -and $ex.InnerException) {
                    $inner = $ex.InnerException
                    if ($inner.PSObject.Properties.Name -contains 'ResponseBody') {
                        $graphErrorDetail = $inner.ResponseBody | ConvertFrom-Json -ErrorAction SilentlyContinue
                    }
                }
            } catch { <# ignore extraction failures #> }

            if ($graphErrorDetail) {
                $detailMsg  = $graphErrorDetail.error.message  ?? ($graphErrorDetail | ConvertTo-Json -Depth 5 -Compress)
                $detailCode = $graphErrorDetail.error.code     ?? 'unknown'
                $message = "$message  [Graph error code=$detailCode detail=$detailMsg]"
            } else {
                # Last resort: dump raw ErrorDetails string if it exists but wasn't valid JSON
                if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                    $message = "$message  [Raw error detail: $($_.ErrorDetails.Message)]"
                }
            }

            # ── Determine HTTP status code ──
            $statusCode = 0
            try {
                if ($ex.PSObject.Properties.Name -contains 'ResponseStatusCode') {
                    $statusCode = [int]$ex.ResponseStatusCode
                } elseif ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
            } catch { <# ignore #> }

            if ($statusCode -ge 400 -and $statusCode -lt 500 -and $statusCode -ne 429) {
                throw "Graph request failed with HTTP $statusCode. Method=$Method Uri=$logUri Error: $message"
            }
            if ($attempt -ge $MaxRetries) {
                throw "Graph request failed after $MaxRetries attempts (HTTP $statusCode). Method=$Method Uri=$logUri Error: $message"
            }

            # ── Check for throttling (429/503) ──
            if ($statusCode -in @(429, 503)) {
                $retryAfter = 0
                try {
                    $retryAfter = [int]$_.Exception.Response.Headers['Retry-After']
                } catch { $retryAfter = 0 }

                if ($retryAfter -le 0) {
                    $retryAfter = [math]::Min(60, [math]::Pow(2, $attempt))
                }

                Write-Log -Message "Graph throttled/temporarily unavailable (attempt $attempt). Retrying in $retryAfter sec..." -Color Yellow
                Start-Sleep -Seconds $retryAfter
                continue
            }

            # ── Server/transient error — retry with exponential backoff ──
            $delay = [math]::Min(30, [math]::Pow(2, $attempt))
            Write-Log -Message "Transient error (attempt $attempt): $message. Retrying in $delay sec..." -Color Yellow
            Start-Sleep -Seconds $delay
        }
    }
}