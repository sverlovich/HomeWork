import-module WebAdministration
$existingWebApplications = Get-WebApplication
$website = Read-Host "What web site do you want to remove applications from?";
$webAppToRemove = Read-Host "What application do you want to remove (wildcard(*)?";

if($webAppToRemove){

    foreach($existingWebApp in $existingWebApplications){
        $webappName = $existingWebApp.Attributes[0].Value;
        if($webAppName -Like "/" + $webAppToRemove){
            Write-Host "Removing " + $webAppName
            if($website){
                Remove-WebApplication -Name $webAppName -Site $website
            }
            else{
                Remove-WebApplication -Name $webAppName -Site "Default Web Site"   
            }

        }
    }
}
else{
    Write-Host "Provide an application name";
}
Get-ChildItem -Path C:\MySite -Include *.* -File -Recurse | foreach { $_.Delete()}