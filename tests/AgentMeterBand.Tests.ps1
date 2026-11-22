Describe 'AgentMeterBand' {
    BeforeAll {
        $version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\VERSION') -Raw).Trim()
        $toolbarDll = Join-Path $TestDrive "AgentMeterBand-$version.dll"
        & (Join-Path $PSScriptRoot '..\build\Build-Toolbar.ps1') -Version $version -OutputPath $toolbarDll
        [void][Reflection.Assembly]::Load([IO.File]::ReadAllBytes($toolbarDll))
    }

    It 'exposes IPersist through QueryInterface' {
        $band = [AgentMeterBand]::new()
        $unknownPointer = [Runtime.InteropServices.Marshal]::GetIUnknownForObject($band)
        $persistInterfaceId = [guid]'0000010C-0000-0000-C000-000000000046'
        $persistPointer = [IntPtr]::Zero
        try {
            $queryResult = [Runtime.InteropServices.Marshal]::QueryInterface($unknownPointer, [ref]$persistInterfaceId, [ref]$persistPointer)
            $queryResult | Should Be 0
        } finally {
            if ($persistPointer -ne [IntPtr]::Zero) {
                [void][Runtime.InteropServices.Marshal]::Release($persistPointer)
            }
            [void][Runtime.InteropServices.Marshal]::Release($unknownPointer)
        }
    }

    It 'requests a compact resizable height in horizontal mode' {
        $band = [AgentMeterBand]::new()
        $requestedFields = [DeskBandFields]::MinimumSize -bor [DeskBandFields]::PreferredSize -bor [DeskBandFields]::ModeFlags
        $horizontal = New-Object DeskBandInfo
        $horizontal.Fields = $requestedFields
        $band.GetBandInfo(0, 0, [ref]$horizontal) | Should Be 0
        $horizontal.MinimumSize.Y | Should Be 14
        $horizontal.PreferredSize.Y | Should Be 26
        ($horizontal.ModeFlags -band 8) | Should Be 8

        $vertical = New-Object DeskBandInfo
        $vertical.Fields = $requestedFields
        $band.GetBandInfo(0, 1, [ref]$vertical) | Should Be 0
        $vertical.MinimumSize.X | Should Be 116
        $vertical.MinimumSize.Y | Should Be 48
        $vertical.ModeFlags | Should Be 0
    }

    It 'lays out both quota windows per service inside a short horizontal band' {
        $binding = [Reflection.BindingFlags]'Instance, NonPublic'
        $viewType = [AgentMeterBand].Assembly.GetType('QuotaView')
        $view = $viewType.GetConstructor($binding, $null, [type[]]@([IntPtr]), $null).Invoke(@([IntPtr]::Zero))
        $track = $viewType.GetMethod('GetTrackBounds', $binding)
        try {
            $view.Size = [Drawing.Size]::new(105, 21)
            $fiveHour = $track.Invoke($view, @(0, 144))
            $weekly = $track.Invoke($view, @(1, 144))
            $otherService = $track.Invoke($view, @(2, 144))
            $fiveHour.Left | Should Be $weekly.Left
            $fiveHour.Width | Should Be $weekly.Width
            ($fiveHour.Width -gt $fiveHour.Height) | Should Be $true
            ($fiveHour.Bottom -lt $weekly.Top) | Should Be $true
            ($weekly.Right -lt $otherService.Left) | Should Be $true
            foreach ($index in 0..3) {
                $bounds = $track.Invoke($view, @($index, 144))
                $view.ClientRectangle.Contains($bounds) | Should Be $true
            }

            $view.Size = [Drawing.Size]::new(48, 213)
            $viewType.GetMethod('SetTaskbarOrientation', $binding).Invoke($view, @($true))
            $fiveHour = $track.Invoke($view, @(0, 96))
            $weekly = $track.Invoke($view, @(1, 96))
            $fiveHour.Top | Should Be $weekly.Top
            ($fiveHour.Right -lt $weekly.Left) | Should Be $true
            ($fiveHour.Height -gt $fiveHour.Width) | Should Be $true
        } finally { $view.Dispose() }
    }

    It 'opens the popup toward the desktop on the corresponding taskbar edge' {
        $popupType = [AgentMeterBand].Assembly.GetType('QuotaPopup')
        $location = $popupType.GetMethod('GetPopupLocation', [Reflection.BindingFlags]'Static, NonPublic')
        $workArea = [Drawing.Rectangle]::new(0, 0, 1920, 1080)
        $popupSize = [Drawing.Size]::new(284, 220)

        $top = [Drawing.Rectangle]::new(1600, -26, 104, 26)
        $location.Invoke($null, @($top, $workArea, $popupSize, 8, $false)).Y | Should Be 8

        $bottom = [Drawing.Rectangle]::new(1850, 1080, 104, 26)
        $above = $location.Invoke($null, @($bottom, $workArea, $popupSize, 8, $false))
        $above.Y | Should Be 852
        ($above.X + $popupSize.Width) | Should Be $workArea.Right

        $left = [Drawing.Rectangle]::new(-48, 200, 48, 116)
        $location.Invoke($null, @($left, $workArea, $popupSize, 8, $true)).X | Should Be 8

        $right = [Drawing.Rectangle]::new(1920, 200, 48, 116)
        $location.Invoke($null, @($right, $workArea, $popupSize, 8, $true)).X | Should Be 1628
    }

    It 'shows the last Claude percentages while the collector is offline' {
        $members = [Reflection.BindingFlags]'Instance, NonPublic'
        $viewType = [AgentMeterBand].Assembly.GetType('QuotaView')
        $view = $viewType.GetConstructor($members, $null, [type[]]@([IntPtr]), $null).Invoke(@([IntPtr]::Zero))
        try {
            $now = [DateTimeOffset]::UtcNow
            $writtenAt = $now.AddHours(-1)
            $snapshot = New-Object 'System.Collections.Generic.Dictionary[string,string]'
            $snapshot['claude_status'] = 'ok'
            $snapshot['claude_c1_last_pct'] = '37'
            $snapshot['claude_c1_observed_at'] = $writtenAt.ToString('o')
            $snapshot['claude_c2_last_pct'] = '0'
            $snapshot['claude_c2_observed_at'] = $writtenAt.ToString('o')
            $viewType.GetMethod('ApplySnapshot', $members).Invoke($view, @($snapshot.PSObject.BaseObject, $writtenAt, $now))
            $rows = $viewType.GetMethod('BuildPopupRows', $members).Invoke($view, @())
            $percent = $rows[1].GetType().GetField('Percent', $members)
            $note = $rows[1].GetType().GetField('Note', $members)
            $percent.GetValue($rows[1]) | Should Be '37%'
            $percent.GetValue($rows[2]) | Should Be '0%'
            $note.GetValue($rows[1]) | Should Match '^Last known'
        } finally { $view.Dispose() }
    }

    It 'does not animate the difference between expired and current observations' {
        $viewType = [AgentMeterBand].Assembly.GetType('QuotaView')
        $members = [Reflection.BindingFlags]'Static, NonPublic'
        $now = [DateTimeOffset]::UtcNow
        $previous = New-Object 'System.Collections.Generic.Dictionary[string,string]'
        $previous['claude_status'] = 'ok'
        $previous['claude_c1_pct'] = '23'
        $previous['claude_c1_fresh_until'] = $now.AddSeconds(-1).ToString('o')
        $current = New-Object 'System.Collections.Generic.Dictionary[string,string]'
        $current['claude_status'] = 'ok'
        $current['claude_c1_pct'] = '41'
        $current['claude_c1_fresh_until'] = $now.AddMinutes(15).ToString('o')
        $method = $viewType.GetMethod('GetUsageIncrease', $members)
        $arguments = @($previous.PSObject.BaseObject, $current.PSObject.BaseObject, 0, $now)
        $method.Invoke($null, $arguments) | Should Be 0
        $previous['claude_c1_fresh_until'] = $now.AddMinutes(1).ToString('o')
        $method.Invoke($null, $arguments) | Should Be 18
    }

    It 'keeps the update button inside the popup at 150 percent scaling' {
        $members = [Reflection.BindingFlags]'Instance, NonPublic'
        $assembly = [AgentMeterBand].Assembly
        $viewType = $assembly.GetType('QuotaView')
        $popupType = $assembly.GetType('QuotaPopup')
        $view = $viewType.GetConstructor($members, $null, [type[]]@([IntPtr]), $null).Invoke(@([IntPtr]::Zero))
        $popup = $popupType.GetConstructor($members, $null, [type[]]@(), $null).Invoke(@())
        try {
            $rows = $viewType.GetMethod('BuildPopupRows', $members).Invoke($view, @())
            $band = [Drawing.Rectangle]::new(0, 200, 48, 150)
            $workArea = [Drawing.Rectangle]::new(48, 0, 360, 650)
            $popupType.GetMethod('UpdateContentAndPosition', $members).Invoke(
                $popup, @($rows.PSObject.BaseObject, $false, 144, $band, $workArea, $true))
            $button = $popup.Controls | Where-Object { $_ -is [Windows.Forms.Button] }
            $button.Text | Should Be 'Check for updates'
            $popup.ClientRectangle.Contains($button.Bounds) | Should Be $true
            ($button.Width -ge 120) | Should Be $true
            $initialButtonWidth = $button.Width
            $popupType.GetMethod('SetUpdateState', $members).Invoke($popup, @('Update', 'A new version is available.', $true))
            $popupType.GetMethod('UpdateContentAndPosition', $members).Invoke(
                $popup, @($rows.PSObject.BaseObject, $false, 144, $band, $workArea, $true))
            $button.Text | Should Be 'Update'
            $button.Width | Should Be $initialButtonWidth
            $popup.AccessibleDescription | Should Match 'A new version is available'
        } finally {
            $popup.Dispose()
            $view.Dispose()
        }
    }
}
