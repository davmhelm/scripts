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

# PURPOSE
# This script collects limits and usage for a set of subscriptions and regions, 
# in an attempt to simplify finding quota increases to request as part of moving 
# resources from one subscription to another

# DEPENDS ON
# Bash or similar shell (Tested on WSL2 Ubuntu 20.04.1, GNU bash 5.0.17)
# Azure CLI (tested on 2.9.1) https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest

# AUTHOR
# Dave Helm (dahelm)

## BEGIN CONFIG ##
SOURCE_SUBSCRIPTION= #enter subscription name or guid here
DESTINATION_SUBSCRIPTION= #enter subscription name or guid here

LOCATIONS=(westus2 eastus2) #(enter space-separated list of regions you use here)
# Location names can be retrieved using "az account list-locations -o table"
# Example LOCATIONS=(eastus eastus2 westus westus2 westcentralus northcentralus southcentralus)
## END CONFIG ##

az login

# Collect limits for source subscription
az account set -s "${SOURCE_SUBSCRIPTION}"
for loc in $LOCATIONS; do
  limitsfile=LIMITS_${SOURCE_SUBSCRIPTION}_${loc}.tsv
  az vm list-usage --location $loc --query "[].{type:'Microsoft.Compute',name:name.value,limit:limit}" -o tsv > "$limitsfile"
  az network list-usages --location $loc --query "[].{type:'Microsoft.Network',name:name.value,limit:limit}" -o tsv >> "$limitsfile"
  az storage account show-usage --location $loc --query "{type:'Microsoft.Storage/storageAccounts',limit:limit,name:name.value}" -o tsv >> "$limitsfile"
  az sql list-usages --location $loc --query "[].{type:'Microsoft.Sql',limit:limit,name:name}" -o tsv >> "$limitsfile"
  sort $limitsfile > $limitsfile
done

# Collect limits for destination subscription
az account set -s "${DESTINATION_SUBSCRIPTION}"
for loc in $LOCATIONS; do
  limitsfile=LIMITS_${DESTINATION_SUBSCRIPTION}_${loc}.tsv
  az vm list-usage --location $loc --query "[].{type:'Microsoft.Compute',name:name.value,limit:limit}" -o tsv > "$limitsfile"
  az network list-usages --location $loc --query "[].{type:'Microsoft.Network',name:name.value,limit:limit}" -o tsv >> "$limitsfile"
  az storage account show-usage --location $loc --query "{type:'Microsoft.Storage/storageAccounts',limit:limit,name:name.value}" -o tsv >> "$limitsfile"
  az sql list-usages --location $loc --query "[].{type:'Microsoft.Sql',limit:limit,name:name}" -o tsv >> "$limitsfile"
  sort $limitsfile > $limitsfile
done

# Compare per-region limits between source and destination
for loc in $LOCATIONS; do
  srclimitsfile=LIMITS_${SOURCE_SUBSCRIPTION}_${loc}.tsv
  destlimitsfile=LIMITS_${DESTINATION_SUBSCRIPTION}_${loc}.tsv
  diff -ys "${srclimitsfile}" "${destlimitsfile}"
done
