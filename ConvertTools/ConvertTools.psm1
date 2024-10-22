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

<#
.SYNOPSIS
Converts the contents of a file to a Base64 encoded string.

.DESCRIPTION
The ConvertTo-Base64 function reads the contents of a specified file and converts it to a Base64 encoded string using .NET's Convert class.

.PARAMETER path
The path to the file that needs to be converted to a Base64 string.

.EXAMPLE
PS C:\> ConvertTo-Base64 -path "C:\example\file.txt"
This command converts the contents of "file.txt" to a Base64 encoded string.

.NOTES
Author: Rekkertt
Date: 23-10-2024
#>
 
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
