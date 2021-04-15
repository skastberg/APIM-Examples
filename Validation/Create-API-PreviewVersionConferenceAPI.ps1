
function Check-LoadedModule {
    Param( [parameter(Mandatory = $true)][alias("Module")][string]$ModuleName)
    $LoadedModules = Get-Module | Select-Object Name
    if (!$LoadedModules -like "*$ModuleName*") { Import-Module -Name $ModuleName }
}


function Set-MyAzureContext() {
    $changeContext = $null -eq (Get-AzContext | Out-GridView -PassThru -Title "Continue with Azure Context?" )
    if ($changeContext) {
        $account = Connect-AzAccount
        $subscription = Get-AzSubscription | Out-GridView -PassThru
        $ctx = Set-AzContext -Subscription $subscription.Id
        return $ctx
    }
    return (Get-AzContext )
}


function Get-AccessToken {
    $context = Get-AzContext
    $myprofile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
    $profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($myprofile)
    $token = $profileClient.AcquireAccessToken($context.Subscription.TenantId)
    return $token.AccessToken
}

##################################
# Main code
##################################
Clear-Host

Check-LoadedModule -module az
$azContext = Set-MyAzureContext
if ($null -eq $azContext) {
    Write-Host "No Azure Context exit" -ForegroundColor Cyan
    exit
}

$apimInstance = Get-AzApiManagement | Out-GridView -Title "Select apim instance" -PassThru
if ($null -eq $apimInstance) {
    Write-Host "No Apim instance exit" -ForegroundColor Cyan
    exit
}

$ApiId = "demo-conference-api"
$OpId = "GetSession"
$ApiUri = "/subscriptions/$( $azContext.Subscription.Id)/resourceGroups/$($apimInstance.ResourceGroupName)/providers/Microsoft.ApiManagement/service/$($apimInstance.Name)/apis/$($ApiId)"

$ApiUrl = "https://management.azure.com$($ApiUri)?api-version=2021-01-01-preview"
$OpUrl = "https://management.azure.com$($ApiUri)/operations/$OpId/policies/policy?api-version=2021-01-01-preview"
$headers = @{"accept" = "application/json"; "content-type" = "application/json; charset=utf-8"; "Authorization" = "Bearer $(Get-AccessToken)" }
$respPol = $null

# Get the policy with the newly edited version. I do it this way as it is easier to edit the policies in the portal.
Write-Host "Get policy" -ForegroundColor Green
try {
    $respPol = Invoke-RestMethod -Uri $OpUrl -Headers $headers -UseBasicParsing -Method Get     
}
catch {
    Write-Host $_ -ForegroundColor Red
    if ($false -eq $_ -contains "404") {
        exit
    }
    Write-Host "Continue without operation policy update." -ForegroundColor DarkYellow
}

$body = '{
    "properties": {
      "format": "openapi-link",
      "value": "https://conferenceapi.azurewebsites.net/",
      "serviceUrl": "https://conferenceapi.azurewebsites.net/",
      "path": "conference"
    }
  }'


Read-Host -Prompt "Delete the api to recreate and press enter to continue or just enter to continue." | Out-Null
Write-Host "Create or update api" -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri $ApiUrl -Headers $headers -UseBasicParsing -Method Put -Body  ([System.Text.Encoding]::UTF8.GetBytes($body))
}
catch {
    Write-Host $_ -ForegroundColor Red
    exit
} 
  

  

if ($null -ne $respPol) {

    $OpBody = "{
        ""properties"": {
          ""format"": ""xml"",
          ""value"": ""$($respPol.properties.value.Replace('"','\"'))""
        }
      }"
    Write-Host "Create or update policy" -ForegroundColor Green
    try {
        $response = Invoke-RestMethod -Uri $OpUrl -Headers $headers -UseBasicParsing -Method Put -Body  ([System.Text.Encoding]::UTF8.GetBytes($OpBody))      
    }
    catch {
        Write-Host $_ -ForegroundColor Red
        exit
    }    
}


Write-Host "Completed" -ForegroundColor Cyan
