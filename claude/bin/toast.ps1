param(
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $true)][string]$Body
)

Import-Module BurntToast -ErrorAction Stop
New-BurntToastNotification -Text $Title, $Body -Sound 'Default' | Out-Null
