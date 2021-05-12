New-Item C:\MySite -type Directory
New-Item C:\MySite\MyApp -type Directory
Set-Content C:\MySite\Test.htm
Set-Content C:\MySite\MyApp\Test.htm
New-Item IIS:\AppPools\MyAppPool
Import-Module "WebAdministration"
New-Item IIS:\Sites\MySite -physicalPath C:\MySite -bindings @{protocol="http";bindingInformation=":8080:"}
Set-ItemProperty IIS:\Sites\MySite -name applicationPool -value MyAppPool
New-Item IIS:\Sites\MySite\MyApp -physicalPath C:\MySite\MyApp -type Application
Set-ItemProperty IIS:\sites\MySite\MyApp -name applicationPool -value MyAppPool
