# THE SOFTWARE IS PROVIDED *AS IS*, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

# Purpose: 
# Applies RBAC assignments and Azure Key Vault Access Policies defined for
# a subscription AFTER IT IS MOVED TO A DIFFERENT AZURE AD TENANT.
# 
# Requirements:
# 1. Must be run as an identity with Owner permissions at the scope of the 
# target subcription.
# 2. Must have run "Get-PreMigrationRBAC.ps1" first
# 3. Must have reviewed and saved the JSON files from the Get-PreMigrationRBAC
# script as directed, using the "mapped" naming convention over "original"; 
# automation of mapping identities from source to destination AAD tenant is 
# beyond the scope of this script

$SubscriptionId = "<enter subscription id here>"

$SubscriptionContext = Select-AzSubscription -SubscriptionId $SubscriptionId
if ($null -eq $SubscriptionContext) {
  Write-Host "You must configure this script with your Subscription ID before running, and if running outside of Cloud Shell, sign-in using Connect-AzAccount first."
  exit 1
}

$SubTenantId = $SubscriptionContext.Tenant.TenantId

$sourceFnamePrefix = $SubscriptionId + "_" + "mapped"
$sourceRbacFile = $sourceFnamePrefix + "-rbac-assignments.json"
$sourceKeyVaultPoliciesFile = $sourceFnamePrefix + "-keyvault-accessPolicies.json"

if ( Test-Path -Path $sourceRbacFile -PathType Leaf) {
  Write-Host "Processing RBAC..."
  $RbacArray = Get-Content -Path $sourceRbacFile | ConvertFrom-Json

  # Assign RBAC roles for updated sign-in names at their previous scope
  $RbacArray `
    | Where-Object { `
      ($_.ObjectType -eq "User") `
      -and ($_.Scope -notlike "/providers/Microsoft.Management/managementGroups*") `
      -and ($_.SignInName -ne $null) `
    } | ForEach-Object {
        # Cast classic administrator roles as Azure RBAC roles
        if ( 
          ($_.RoleDefinitionName -like "*ServiceAdministrator*") `
          -or ($_.RoleDefinitionName -like "*AccountAdministrator*")
        ) {
          $LocalRoleDefinitionName = "Owner"
        } else {
          $LocalRoleDefinitionName = $_.RoleDefinitionName
        }

        New-AzRoleAssignment -SignInName $_.SignInName `
          -RoleDefinitionName $LocalRoleDefinitionName `
          -Scope $_.Scope
    }

} else {
  Write-Host "$sourceRbacFile not found in current path. Skipping."
}

if ( Test-Path -Path $sourceKeyVaultPoliciesFile -PathType Leaf ) {
  Write-Host "Processing Key Vaults..."
  
  # Load KV Policies from File
  $keyVaultPolicyArray = Get-Content -Path $sourceKeyVaultPoliciesFile | ConvertFrom-Json

  # Get full list of key vaults   
  $vaults = Get-AzKeyVault

  foreach ($vault in $vaults) {
      # Check Tenant ID of vault
      $vaultProps = Get-AzResource -ResourceId $vault.ResourceId -ExpandProperties

      if ( $vaultProps.Properties.TenantId -eq $SubTenantId ) {
        Write-Host "$($vault.ResourceId) tenant ID matches subscription's current tenant ID $TenantId. No changes will be made."

      } else { # Vault needs to be updated
        # Change Tenant ID on vault resource
        $vaultProps.Properties.tenantId = $SubTenantId

        # Drop access policies on vault for rebuild
        $vaultProps.Properties.accessPolicies = @()

        # Commit Tenant ID and access policy changes to vault
        Set-AzResource -ResourceId $vaultProps.ResourceId -Properties $vaultProps.Properties -Force

        # Populate KV policies from policy array
        $keyVaultPolicyArray `
          | Where-Object { $_.ResourceId -eq $vaultProps.ResourceId } `
          | foreach-object {
              Set-AzKeyVaultAccessPolicy -ResourceId $_.ResourceId `
              -UserPrincipalName $_.UserPrincipalName `
              -PermissionsToKeys $_.PermissionsToKeys `
              -PermissionsToSecrets $_.PermissionsToSecrets `
              -PermissionsToCertificates $_.PermissionsToCertificates `
              -PermissionsToStorage $_.PermissionsToStorage
          }
      }
  }

} else { # No file found
  Write-Host "$sourceKeyVaultPoliciesFile not found in current path. Skipping."
}
