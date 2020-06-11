# THE SOFTWARE IS PROVIDED *AS IS*, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

# Purpose: Collects RBAC assignments and Azure Key Vault Access Policies defined for
#     a subscription BEFORE IT IS MOVED TO A DIFFERENT AZURE AD TENANT.
# 
# Requirements: Must be run as an identity with Owner permissions at the scope
#     of the target subcription to be moved.

$SubscriptionId = "<enter subscription id here>"

$SubscriptionContext = Select-AzSubscription -SubscriptionId $SubscriptionId
#Connect-AzureAD

$fnamePrefix = $SubscriptionId + "_" + "original"

# Get RBAC Assignments for subscription
# Export RBAC assigments to JSON for later use
Get-AzRoleAssignment -IncludeClassicAdministrators `
  | ConvertTo-Json `
  | Out-File "$Home/$fnamePrefix-rbac-assignments.json"

# TODO: add logic for getting custom RBAC roles referenced in role assignments

# Get List of Key Vaults and access policies in current subscription
# After changing the AAD Tenant for a subscription, you must follow 
# guidance here before key vaults will work:
# https://docs.microsoft.com/en-us/azure/key-vault/key-vault-subscription-move-fix
$keyVaultProps = Get-AzKeyVault `
  | ForEach-Object { Get-AzKeyVault -VaultName $($_.VaultName) } `
  | Select-Object -Property ResourceId -ExpandProperty AccessPolicies 

# Object ID uniquely identifies an identity within a specific AAD tenant
# Display Name is not a good search parameter as-is, but User Principal Name may be
# Attach UPN to KV access policies where they can be found
$keyVaultProps | ForEach-Object {
  $user = Get-AzAdUser -ObjectId $_.ObjectId
  if ($user -ne $null) {$_ | Add-Member -MemberType NoteProperty -Name UserPrincipalName -Value $user.UserPrincipalName}
}

# Export access policies to JSON for later use
$keyVaultProps `
  | ConvertTo-Json `
  | Out-File "$Home/$fnamePrefix-keyvault-accessPolicies.json"

# TODO: Add logic for updating system and user managed identities
# Get User Managed Identities
#Get-AzResource -ResourceType "Microsoft.ManagedIdentity/userAssignedIdentities" `
#  | ConvertTo-Json `
#  | Out-File "$Home/clouddrive/umi.json"

Write-Host @"
Next Steps:
1. Copy the following files to a safe location for your records:
`ta. $Home/$fnamePrefix-rbac-assignments.json
`tb. $Home/$fnamePrefix-keyvault-accessPolicies.json
2. Review the original json files
`ta. Update them to reflect your new Azure AD tenant (Tenant ID, UserPrincipalNames)
`tb. For RBAC assignments:
`t`ti. For ObjectType of Unknown, and determine if those mappings should be carried over (usually reflects orphaned RBAC entries for identities that no longer exist)
`t`tii. For ServicePrincipal types, decide whether the service principal identities should be created in the destination AAD tenant first, or if that will be done manually post-migration; update service principal Object IDs
`tc. For Key Vault Policies:
`t`ti. For entries with a UserPrincipalName, make sure that UPN is present in the destination AAD, and update it if necessary
`t`tii. For anything with an ObjectId but no UserPrincipalName, follow same approach as with RBAC above -- Object IDs will need to be updated for service principal accounts in the destination AAD tenant
3. Save the resulting files as `"$subscriptionID`_mapped-{listtype}.json`" (where listtype is either `"rbac-assigments`" or `"keyvault-accessPolicies`")
4. Configure and run the `"Set-PostMigrationRBAC.ps1`" script
"@
