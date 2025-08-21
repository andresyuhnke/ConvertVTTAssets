# ConvertVTTAssets.Core.ps1 — PS7+ parallel helpers (ThreadJob engine)

# Ensure ThreadJob is available
Import-Module ThreadJob -ErrorAction SilentlyContinue

function Invoke-WebMParallel {
    param(
        [System.IO.FileInfo[]]$Files,
        [hashtable]$S
    )
    Import-Module ThreadJob -ErrorAction SilentlyContinue
    Write-Verbose "Engine: ThreadJob (WebM)  | ThrottleLimit=$($S.ThrottleLimit)"
    [System.Collections.ArrayList]$jobs = @()

    foreach ($f in $Files) {
        while ($jobs.Count -ge [int]$S.ThrottleLimit) {
            if ($jobs.Count -gt 0) { Wait-Job -Job $jobs -Any | Out-Null }
            $jobs = @($jobs | Where-Object { $_.State -eq 'Running' })
        }

        $job = Start-ThreadJob -ScriptBlock {
            param($f,$S)
            # Import the full module with retry logic
            $modulePath = 'C:\PowerShell-Scripts\ConvertVTTAssets\ConvertVTTAssets.psd1'
            $imported = $false
            for ($i = 0; $i -lt 3; $i++) {
                try {
                    if (Test-Path $modulePath) { 
                        Import-Module $modulePath -Force -ErrorAction Stop
                        # Verify a function exists
                        if (Get-Command Get-DestinationPath -ErrorAction SilentlyContinue) {
                            $imported = $true
                            break
                        }
                    }
                    Start-Sleep -Milliseconds 100
                } catch {
                    Start-Sleep -Milliseconds 100
                }
            }
            if (-not $imported) {
                throw "Failed to import module after 3 attempts"
            }
            
            $VerbosePreference = $S.VerbosePreference
            $WhatIfPreference  = $S.WhatIfPreference
            $ErrorActionPreference = 'Stop'

            $result = [ordered]@{
                Time        = (Get-Date).ToString('s')
                Command     = 'Convert-ToWebM'
                Source      = $f.FullName
                Destination = $null
                Status      = 'Skipped'
                Reason      = ''
                DurationSec = 0.0
                SrcBytes    = $f.Length
                DstBytes    = 0
                SizeDeltaBytes = $null
                SizeDeltaPct   = $null
                Codec       = $S.Codec
                HasAlpha    = $false
                AlphaMode   = $S.AlphaMode
                FPSCap      = $S.MaxFPS
                WidthCap    = $S.MaxWidth
            }
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $dest = Get-DestinationPath -SourceFile $f -Root $S.Root -OutputRoot $S.OutputRoot -NewExtension '.webm'
                $result.Destination = $dest

                if (-not $S.Force -and (Test-Path $dest)) {
                    $dstInfo = Get-Item $dest
                    if ($dstInfo.LastWriteTimeUtc -ge $f.LastWriteTimeUtc) {
                        $result.Status = 'Skipped'; $result.Reason='UpToDate'
                        return [pscustomobject]$result
                    }
                }

                $info = Invoke-FFProbeJson -Path $f.FullName -FfprobePath $S.FfprobePath
                $hasAlpha = $false
                if ($info) { $hasAlpha = Get-HasAlpha -Info $info }
                elseif ($f.Extension.ToLower() -in @('.gif','.apng','.webp')) { $hasAlpha = $true }
                switch ($S.AlphaMode) {
                    'force'   { $hasAlpha = $true }
                    'disable' { $hasAlpha = $false }
                }
                $result.HasAlpha = $hasAlpha

                $srcW = Get-Width  -Info $info
                $srcH = Get-Height -Info $info
                $srcFps = Get-FrameRate -Info $info

                $vf = $null
                $useFlatten = ($S.AlphaMode -eq 'disable' -and -not $S.AlphaBackground)
                $vf = Get-FilterGraph -SrcWidth $srcW -SrcFps $srcFps -MaxWidth $S.MaxWidth -MaxFPS $S.MaxFPS -AlphaMode $S.AlphaMode -FlattenBlack:$useFlatten

                $codecArgs = @()
                switch ($S.Codec) {
                    'vp9' {
                        $codecArgs = @('-c:v','libvpx-vp9','-crf','28','-b:v','0','-row-mt','1','-threads','0','-speed','2','-deadline','good')
                        if ($hasAlpha) { $codecArgs += @('-pix_fmt','yuva420p','-auto-alt-ref','0') } else { $codecArgs += @('-pix_fmt','yuv420p') }
                    }
                    'av1' {
                        $codecArgs = @('-c:v','libaom-av1','-crf','30','-b:v','0','-threads','0','-cpu-used','4')
                        if ($hasAlpha) { $codecArgs += @('-pix_fmt','yuva420p') } else { $codecArgs += @('-pix_fmt','yuv420p') }
                    }
                }
                if ($S.MaxBitrateKbps -gt 0) {
                    $codecArgs += @('-maxrate', ("{0}k" -f $S.MaxBitrateKbps), '-bufsize', ("{0}k" -f ($S.MaxBitrateKbps*2)))
                }

                $args = @('-y','-hide_banner','-loglevel','error','-i', $f.FullName)

                $filtersApplied = $false
                if ($S.AlphaMode -eq 'disable' -and $S.AlphaBackground) {
                    $w = $srcW; $h = $srcH
                    if ($w -and $h -and $w -gt 0 -and $h -gt 0) {
                        $bg = ($S.AlphaBackground).Trim('#')
                        $fc = @()
                        if ($S.MaxFPS -gt 0) { $fc += ("fps={0}" -f $S.MaxFPS) }
                        if ($S.MaxWidth -gt 0 -and $w -gt $S.MaxWidth) { $fc += ("scale=min(iw\,{0}):-2:flags=lanczos" -f $S.MaxWidth) }
                        if ($fc.Count -eq 0) { $fc = @('format=rgba') } else { $fc.Insert(0,'format=rgba') }
                        $filterComplex = "color=c=#${bg}:s=${w}x${h}[bg];[0:v]" + ($fc -join ',') + "[v];[bg][v]overlay=format=auto,format=yuv420p"
                        $args += @('-filter_complex', $filterComplex)
                        $filtersApplied = $true
                    }
                }

                if (-not $filtersApplied) {
                    if ($vf) { $args += @('-filter:v', $vf) }
                }

                $args += $codecArgs
                $args += @('-an','-f','webm', $dest)

                if ($WhatIfPreference) {
                    Write-Host "WhatIf: would convert '$($f.FullName)' → '$dest'"
                    $result.Status = 'WhatIf'
                    return [pscustomobject]$result
                }

                & $S.FfmpegPath @args
                $ok = ($LASTEXITCODE -eq 0)
                if ($ok) {
                    $result.Status = 'Converted'
                    $dst = Get-Item $dest -ErrorAction SilentlyContinue
                    if ($dst) {
                        $result.DstBytes = $dst.Length
                        if ($result.SrcBytes -gt 0) {
                            $result.SizeDeltaBytes = [long]($result.DstBytes - $result.SrcBytes)
                            $result.SizeDeltaPct   = [math]::Round((($result.DstBytes / [double]$result.SrcBytes) - 1.0) * 100.0, 2)
                        }
                    }
                } else {
                    $result.Status = 'Failed'; $result.Reason = "ffmpeg exit $LASTEXITCODE"
                }
                return [pscustomobject]$result
            } catch {
                $result.Status = 'Failed'; $result.Reason = $_.Exception.Message
                return [pscustomobject]$result
            } finally {
                $sw.Stop(); $result.DurationSec = [math]::Round($sw.Elapsed.TotalSeconds,2)
            }
        } -ArgumentList $f, $S

        $jobs += $job
    }

    if ($jobs.Count -gt 0) {
        Wait-Job -Job $jobs | Out-Null
        $out = Receive-Job -Job $jobs -AutoRemoveJob -Wait
        return $out
    } else {
        return @()
    }
}

function Invoke-WebPParallel {
    param(
        [System.IO.FileInfo[]]$Files,
        [hashtable]$S
    )
    Import-Module ThreadJob -ErrorAction SilentlyContinue
    Write-Verbose "Engine: ThreadJob (WebP)  | ThrottleLimit=$($S.ThrottleLimit)"
    [System.Collections.ArrayList]$jobs = @()

    foreach ($f in $Files) {
        while ($jobs.Count -ge [int]$S.ThrottleLimit) {
            if ($jobs.Count -gt 0) { Wait-Job -Job $jobs -Any | Out-Null }
            $jobs = @($jobs | Where-Object { $_.State -eq 'Running' })
        }

        $job = Start-ThreadJob -ScriptBlock {
            param($f,$S)
            # Import the full module with retry logic
            $modulePath = 'C:\PowerShell-Scripts\ConvertVTTAssets\ConvertVTTAssets.psd1'
            $imported = $false
            for ($i = 0; $i -lt 3; $i++) {
                try {
                    if (Test-Path $modulePath) { 
                        Import-Module $modulePath -Force -ErrorAction Stop
                        # Verify a function exists
                        if (Get-Command Get-DestinationPath -ErrorAction SilentlyContinue) {
                            $imported = $true
                            break
                        }
                    }
                    Start-Sleep -Milliseconds 100
                } catch {
                    Start-Sleep -Milliseconds 100
                }
            }
            if (-not $imported) {
                throw "Failed to import module after 3 attempts"
            }
            
            $VerbosePreference = $S.VerbosePreference
            $WhatIfPreference  = $S.WhatIfPreference
            $ErrorActionPreference = 'Stop'

            $result = [ordered]@{
                Time        = (Get-Date).ToString('s')
                Command     = 'Convert-ToWebP'
                Source      = $f.FullName
                Destination = $null
                Status      = 'Skipped'
                Reason      = ''
                DurationSec = 0.0
                SrcBytes    = $f.Length
                DstBytes    = 0
                SizeDeltaBytes = $null
                SizeDeltaPct   = $null
                Quality     = $S.Quality
                Lossless    = [bool]$S.Lossless
                WidthCap    = $S.MaxWidth
            }
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $dest = Get-DestinationPath -SourceFile $f -Root $S.Root -OutputRoot $S.OutputRoot -NewExtension '.webp'
                $result.Destination = $dest

                if (-not $S.Force -and (Test-Path $dest)) {
                    $dstInfo = Get-Item $dest
                    if ($dstInfo.LastWriteTimeUtc -ge $f.LastWriteTimeUtc) {
                        $result.Status = 'Skipped'; $result.Reason='UpToDate'
                        return [pscustomobject]$result
                    }
                }

                $info = Invoke-FFProbeJson -Path $f.FullName -FfprobePath $S.FfprobePath
                $srcW = Get-Width  -Info $info

                $vf = $null
                if ($srcW -and $srcW -gt $S.MaxWidth) { $vf = "scale=min(iw\,{0}):-2:flags=lanczos" -f $S.MaxWidth }

                $args = @('-y','-hide_banner','-loglevel','error','-i', $f.FullName)
                if ($vf) { $args += @('-vf', $vf) }

                $args += @('-c:v','libwebp')
                if ($S.Lossless) { $args += @('-lossless','1','-compression_level','6') }
                else { $args += @('-q:v', $S.Quality) }

                $args += @('-frames:v','1', $dest)

                if ($WhatIfPreference) {
                    Write-Host "WhatIf: would convert '$($f.FullName)' → '$dest'"
                    $result.Status = 'WhatIf'
                    return [pscustomobject]$result
                }

                & $S.FfmpegPath @args
                $ok = ($LASTEXITCODE -eq 0)
                if ($ok) {
                    $result.Status = 'Converted'
                    $dst = Get-Item $dest -ErrorAction SilentlyContinue
                    if ($dst) {
                        $result.DstBytes = $dst.Length
                        if ($result.SrcBytes -gt 0) {
                            $result.SizeDeltaBytes = [long]($result.DstBytes - $result.SrcBytes)
                            $result.SizeDeltaPct   = [math]::Round((($result.DstBytes / [double]$result.SrcBytes) - 1.0) * 100.0, 2)
                        }
                    }
                } else {
                    $result.Status = 'Failed'; $result.Reason = "ffmpeg exit $LASTEXITCODE"
                }
                return [pscustomobject]$result
            } catch {
                $result.Status = 'Failed'; $result.Reason = $_.Exception.Message
                return [pscustomobject]$result
            } finally {
                $sw.Stop(); $result.DurationSec = [math]::Round($sw.Elapsed.TotalSeconds,2)
            }
        } -ArgumentList $f, $S

        $jobs += $job
    }

    if ($jobs.Count -gt 0) {
        Wait-Job -Job $jobs | Out-Null
        $out = Receive-Job -Job $jobs -AutoRemoveJob -Wait
        return $out
    } else {
        return @()
    }
}

