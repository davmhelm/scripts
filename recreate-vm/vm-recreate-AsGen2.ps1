# THE SOFTWARE IS PROVIDED *AS IS*, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

# This script takes an existing VM and recreates it as a Hyper-V hardware generation 2 VM
# Put the exact resource group name and VM name of an existing VM in the configurable variables
# The script does the rest

# CONFIGURABLE VARIABLES
    $resourceGroup = "YourResourceGroupName"
    $vmName = "YourVmName"
# END CONFIGURABLE VARIABLES

# Get the details of the VM to be recreated
    $originalVM = Get-AzVM `
	   -ResourceGroupName $resourceGroup `
	   -Name $vmName 
   
# Remove the original VM
# WARNING: THIS STEP DELETES THE SOURCE VM
    Remove-AzVM -ResourceGroupName $resourceGroup -Name $vmName    

# Create the basic configuration for the replacement VM. 
    $newVM = New-AzVMConfig `
	   -VMName $originalVM.Name `
       -VMSize $originalVM.HardwareProfile.vmSize `
       -Tags $originalVM.Tags

# For Hyper-V Generation 2 VMs, update the Managed Disk object
# This needs to be done when no VM is attached to the disk
    $managedOsDisk = Get-AzResource -ResourceId $originalVM.StorageProfile.OsDisk.ManagedDisk.Id | Get-AzDisk
    $managedOsDisk.HyperVGeneration = "V2"
    $managedOsDisk | Update-AzDisk

# For a Linux VM, change the last parameter from -Windows to -Linux 
    Set-AzVMOSDisk `
	   -VM $newVM -CreateOption Attach `
	   -ManagedDiskId $originalVM.StorageProfile.OsDisk.ManagedDisk.Id `
	   -Name $originalVM.StorageProfile.OsDisk.Name `
	   -Windows

# Add Data Disks
    foreach ($disk in $originalVM.StorageProfile.DataDisks) { 
    Add-AzVMDataDisk -VM $newVM `
	   -Name $disk.Name `
	   -ManagedDiskId $disk.ManagedDisk.Id `
	   -Caching $disk.Caching `
	   -Lun $disk.Lun `
	   -DiskSizeInGB $disk.DiskSizeGB `
	   -CreateOption Attach
    }

# Add NIC(s) and keep the same NIC as primary
    foreach ($nic in $originalVM.NetworkProfile.NetworkInterfaces) {	
        if ($nic.Primary -eq "True")
            {
                Add-AzVMNetworkInterface `
                -VM $newVM `
                -Id $nic.Id -Primary
                }
            else
                {
                Add-AzVMNetworkInterface `
                -VM $newVM `
                -Id $nic.Id 
                    }
        }

# Recreate the VM
    New-AzVM `
	   -ResourceGroupName $resourceGroup `
	   -Location $originalVM.Location `
	   -VM $newVM `
	   -DisableBginfoExtension