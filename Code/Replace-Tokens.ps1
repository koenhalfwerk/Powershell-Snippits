function Replace-Token {
    <#
.SYNOPSIS
    Replaces tokens in a file
.DESCRIPTION
    Replaces all tokens from $TokenArray in the file from $File.
    TokenArray should be an array with key=ExactToken, value = WantedValueThatReplacesToken
.EXAMPLE
    $Tokens = @{'<--pipelineVariable1-->' = 'ID1'; '<--pipelineVariable2-->' = 'ID2'}
    .\Replace-Token.ps1 -TokenArray $Tokens -file .\test.json
    will replace any entry of <--pipelineVariable1--> in the file with the string ID1
.EXAMPLE
    $Tokens = @{'<--pipelineVariable1-->' = 'ID1'; '<--pipelineVariable2-->' = 'ID2'}
    .\CI\Tools\Replace-Token.ps1 -TokenArray $Tokens -file 'rel\path\test.json' -ErrorAction stop -verbose 
    Yaml Pipeline variant, will replace any entry of <--pipelineVariable2--> in the file with the string ID2
.EXAMPLE
    .\CI\Tools\Replace-Token.ps1 -Tokenstring '<token1>', '<token2>' -tokenvalue 'value1', 'value2' -file 'rel\path\test.json' -ErrorAction stop -verbose 
    Yaml Pipeline variant with string parameters when hashtables are not a real option
.NOTES
    General notes 
#>
    [CmdletBinding(DefaultParameterSetName = 'Array', 
        SupportsShouldProcess = $true,
        PositionalBinding = $false)]
    Param
    (
        [Parameter(Mandatory = $false, ParameterSetName = 'Array')] $TokenArray,
        [Parameter(Mandatory = $false, ParameterSetName = 'String')] [string[]] $TokenString,
        [Parameter(Mandatory = $true, ParameterSetName = 'String')] [string[]] $TokenValue,
        [Parameter(Mandatory = $true)] [ValidateScript( { test-path $_ })] [string] $File,
        [Parameter(Mandatory = $true)] [string] $VariableName,
        # Used when the $file is used multiple times in the same stages
        [Parameter(Mandatory = $false)] [string] $FilePrefix,
        [Parameter(Mandatory = $false)] [switch] $AsObject
    )
    #Requires -psedition core, desktop
    Begin {
        if (Test-Path $File) {
            $content = Get-Content -Path $File -raw
        }
        else {
            Write-Error ('File {0} not found from path {1}' -f $File, (Get-Item .\ | Select-Object -ExpandProperty fullname))
            break
        }
        $fileObj = Get-Item $File
        $fileParent = Split-Path -Path $fileObj -Parent
        Remove-Variable -Name OutputFile -ErrorAction SilentlyContinue
        if ($TokenString) {
            $TokenArray = @{}
            for ($i = 0 ; $i -lt $Tokenstring.Count; $i++) {
                $TokenArray.Add($TokenString[$i], $TokenValue[$i])
            }
        }

        $outputFile = Join-Path -Path $fileParent -ChildPath ($FilePrefix + $fileObj.Name) -Resolve -ErrorAction SilentlyContinue

        if (!$outputFile) {
            foreach ($number in (0..100)) {
                $outputFile = Join-Path -Path $fileParent -ChildPath ([string]$number + $fileObj.Name)
                if ((Test-Path -Path $outputFile)) {
                    Write-Output "$outputFile already exists"
                }
                else {
                    Write-Output "Using $outputFile"
                    break
                }
            }
        }
    }
    Process {
        foreach ($token in ([string[]]$TokenArray.keys)) {
            if ($psCmdlet.ShouldProcess($File, ('Replace Token {0} with value "{1}"' -f [string]$token, ($TokenArray[$token] | Out-String)))) {
                if (($content.indexof($token)) -eq -1) {
                    Write-Warning ('Token {1} not found in file {0}' -f $File, $token)
                }
                else {
                    Write-Verbose ('Replacing {0} with {1} in file {2}' -f $token, $TokenArray[$token], $File | Out-String)
                    $content = $content.Replace($token, $TokenArray["$token"])
                }
            }
        }
    }
    End {
        if ($AsObject) {
            return $content
        }
        else {
            $content | Set-Content -Path $outputFile -Verbose

            Write-Output "Writing property $VariableName value $($outputFile)"
            Write-Output "##vso[task.setvariable variable=$VariableName]$($outputFile)"
            Write-Output "##vso[task.setvariable variable=$VariableName;isOutput=true]$($outputFile)"
        }
    }
}