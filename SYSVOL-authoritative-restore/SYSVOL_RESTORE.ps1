# This sample script is not supported under any Microsoft standard support program or service. 
# The sample script is provided AS IS without warranty of any kind. Microsoft further disclaims 
# all implied warranties including, without limitation, any implied warranties of merchantability 
# or of fitness for a particular purpose. The entire risk arising out of the use or performance of 
# the sample scripts and documentation remains with you. In no event shall Microsoft, its authors, 
# or anyone else involved in the creation, production, or delivery of the scripts be liable for any 
# damages whatsoever (including, without limitation, damages for loss of business profits, business 
# interruption, loss of business information, or other pecuniary loss) arising out of the use of or 
# inability to use the sample scripts or documentation, even if Microsoft has been advised of the 
# possibility of such damages 

# Original credit: Mark Renoden
# Source: https://docs.microsoft.com/en-us/archive/blogs/markrenoden/authoritative-restore-of-sysvol-after-deallocation-of-azure-dcs

# Optionally enable verbose tracking of actions
# $VerbosePreference = 'Continue'

# Get the list of all DCs in the local domain
$domainControllers = Get-ADDomainController -Filter *

# Use the first DC in the list as the primary member for DFSR
# If a specific DC is preferred, use Get-ADDomainController -Identity <DC_Hostname>
#$primaryDC = $domainControllers[0]

$primaryDC = Get-ADDomainController -Identity ((Get-ADDomain | Select-Object PDCEmulator).PDCEmulator)

Write-Verbose -Message "Found the following domain controllers: $domainControllers" 
Write-Verbose -Message "Found primary DC: $primaryDC"

# Verify all DCs are online before forcing SYSVOL replication
foreach ($dc in $domainControllers)
{
    if (!(Test-Connection -ComputerName ($dc.HostName) -BufferSize 16 -Count 1 -ErrorAction SilentlyContinue -Quiet))
    {
        Write-Error -Message "Could not confirm availability of $($dc.Name). Please ensure all of the following DCs are running and try again.`n$domainControllers"
        exit 1
    }
}

# Stop DFSR on all DCs
foreach ($dc in $domainControllers)
{
    Write-Verbose -Message "Stopping DFSR service on $dc..."
    Invoke-Command -ComputerName $dc.HostName -ScriptBlock {Stop-Service DFSR}
}
 
# Modify DFSR subscription object to disable the SYSVOL replica in AD and replicate it
foreach ($dc in $domainControllers)
{
    Write-Verbose -Message "Disabling SYSVOL replication between $dc and PDC $primaryDC..."
    $sysvolSubscriptionObject = "CN=SYSVOL Subscription,CN=Domain System Volume,CN=DFSR-LocalSettings," + $dc.ComputerObjectDN
    Get-ADObject -Identity $sysvolSubscriptionObject | Set-ADObject -Server $primaryDC -Replace @{"msDFSR-Enabled"=$false}
    Get-ADDomainController -filter * | foreach {Sync-ADObject -Object $sysvolSubscriptionObject -Source $primaryDC -Destination $_.hostname}
}
 
# Start and then stop DFSR on all DCs
foreach ($dc in $domainControllers)
{
    Write-Verbose -Message "Starting and stopping DFSR service on $dc to update state..."
    Invoke-Command -ComputerName $dc.HostName -ScriptBlock {Start-Service DFSR}
    Start-Sleep -Seconds 20
    Invoke-Command -ComputerName $dc.HostName -ScriptBlock {Stop-Service DFSR}
}
 
# Modify DFSR subscription to enable the SYSVOL replica in AD and set the primary
# Force replication of these changes
Write-Verbose -Message "Configuring SYSVOL replication from PDC $primaryDC..."
$sysvolSubscriptionObject = "CN=SYSVOL Subscription,CN=Domain System Volume,CN=DFSR-LocalSettings," + $primaryDC.ComputerObjectDN
Get-ADObject -Identity $sysvolSubscriptionObject | Set-ADObject -Server $primaryDC -Replace @{"msDFSR-Options"=1}
 
foreach ($dc in $domainControllers)
{
    Write-Verbose -Message "Forcing sync of SYSVOL replication to $dc..."
    $sysvolSubscriptionObject = "CN=SYSVOL Subscription,CN=Domain System Volume,CN=DFSR-LocalSettings," + $dc.ComputerObjectDN
    Get-ADObject -Identity $sysvolSubscriptionObject | Set-ADObject -Server $primaryDC -Replace @{"msDFSR-Enabled"=$true}
    Get-ADDomainController -filter * | foreach {Sync-ADObject -Object $sysvolSubscriptionObject -Source $primaryDC -Destination $_.hostname}
}
 
# Start DFSR on all DCs
foreach ($dc in $domainControllers)
{
    Write-Verbose -Message "Starting DFSR service on $dc..."
    Invoke-Command -ComputerName $dc.HostName -ScriptBlock {Start-Service DFSR}
}
