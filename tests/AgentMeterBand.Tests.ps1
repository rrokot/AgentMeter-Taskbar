Describe 'AgentMeterBand COM persistence' {
    It 'exposes IPersist through QueryInterface' {
        $toolbarSourcePath = Join-Path $PSScriptRoot '..\src\AgentMeterBand.cs'
        Add-Type -Path $toolbarSourcePath -ReferencedAssemblies System.Drawing.dll, System.Windows.Forms.dll, System.Web.Extensions.dll -ErrorAction Stop

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
}
