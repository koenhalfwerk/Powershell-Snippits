<#
.SYNOPSIS
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory)]
    [String]$ProjectNames = @('', ''),
    [String]$IgnoreProjectNames = @('', ''),
    [string]$DevOpsOrganisation,
    [int]$Days,
    [string]$FromAddress,
    [string]$ToAddress,
    [string]$FromName
)
#Requires -PSEdition Desktop,Core

if (!(Get-Module PSSendGrid -ListAvailable)) { Install-Module PSSendGrid -Force -Scope CurrentUser }
$sendgridkey = $env:SendgridKey
$date = Get-Date

# loging and setting header
az config set extension.use_dynamic_install=yes_without_prompt
Write-Output $env:SYSTEM_ACCESSTOKEN | az devops login 
$header = @{Authorization = "Bearer $($env:SYSTEM_ACCESSTOKEN)"; 'Content-Type' = 'application/json' }
az devops configure --defaults organization=$devOpsOrganisation 

# get all the pipelines
$existingpipelines = @()
$projects = az devops project list | ConvertFrom-Json | Select-Object -ExpandProperty value |   Where-Object { $_.name -NotIn $IgnoreProjectNames }

$projects.id | ForEach-Object {
    $existingpipelines += az pipelines list --project $_ | ConvertFrom-Json
}
# filter the pipelines
$filteredPipelines = $existingpipelines 
# get the runs of the pipelines and their details
$failed = @()
foreach ($pipeline in $filteredPipelines) {
    $url = ('{0}{1}/_apis/pipelines/{2}/runs?api-version=7.1-preview.1' -f $devOpsOrganisation, $pipeline.project.id, $pipeline.id)

    $runs = Invoke-RestMethod -Method Get -Uri $url -Headers $header
    if ($runs.count -gt 0) {
        $runvalue = $runs.value | Where-Object { (Get-Date $_.createdDate) -gt $date.AddDays(-$Days) }
        $failed += $runvalue | Where-Object result -EQ 'failed' | Select-Object `
        @{name = 'name'; expression = { $pipeline.name } }, 
        @{name = 'projectName'; expression = { $pipeline.project.name } }, 
        @{name = 'url' ; expression = { "$devOpsOrganisation$($pipeline.project.id)/_build/results?buildId=$($_.id)" } }, 
        result, createddate, @{
            name       = 'branch'
            expression = { 
                $runDetails = Invoke-RestMethod -Method Get -Uri ('{0}{1}/_apis/pipelines/{2}/runs/{3}?api-version=7.1-preview.1' -f $devOpsOrganisation, $pipeline.project.id, $pipeline.id, $_.id) -Headers $header
                $runDetails.resources.repositories.self.refName
            }
        }

    }
}
$failed | Where-Object branch -NotIn @('refs/heads/master', 'refs/heads/main',  'refs/heads/PRD')  | format-table -AutoSize
$failed = $failed | Where-Object branch -In @('refs/heads/master', 'refs/heads/main',  'refs/heads/PRD') 

# if any failed, mail them using sendgrid
if ($failed) {
    $body = @()
    $body += 'Onderstaande pipelines zijn gefaald. zoek uit waarom en los het op.' 
    $body += $failed | ConvertTo-Html -Fragment | Out-String
    $body += ''
    $body += 'report is gegenereerd door Pad-naar-script.ps1.'
  
    $parameters = @{
        FromAddress = $FromAddress
        ToAddress   = $ToAddress
        Subject     = 'Fouten in pipelines'
        BodyAsHTML  = $body | Out-String
        Token       = $sendgridkey
        FromName    = $FromName
    }
    Send-PSSendGridMail @parameters
}
else {
    Write-Output 'Geen gefaalde productie pipelines gevonden.'
}