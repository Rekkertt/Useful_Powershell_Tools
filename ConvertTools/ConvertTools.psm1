Function ConvertFrom-Base64 {  

    [CmdletBinding()]
    param
    (    
        [Parameter(Mandatory)]
        [ValidateSet("UTF8", "Unicode", "ASCII")]
        [string]$Encoding,
        
        [Parameter(Mandatory)]
        [String]$InputString
    )

    return [System.Text.Encoding]::$Encoding.GetString([System.Convert]::FromBase64String("$InputString"))
}


Function ConvertTo-Base64($path) {
	
    return [Convert]::ToBase64String((Get-Content $path -Encoding byte))
}


Function ConvertStringTo-CSV {

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [String]$Header,
        
        [Parameter(Mandatory)]
        [string]$MultiLineString
    )
    
    $Output = "$header`n" + $MultiLineString.Trim() -replace '(.+)', '"$1",' -replace ',$', '' | Out-String
    Return $Output
}
