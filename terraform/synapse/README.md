# Synapse Workspace Terraform
Terraform module samples based on processes learned in [Azure Samples to create an Azure Synapse Workspace](https://github.com/Azure-Samples/Synapse/tree/master/Manage/DeployWorkspace).

[synapse-workspace-sample.tf](./synapse-workspace-sample.tf) is a basic workspace with options called out for adding workspace-level permissions, SQL pools, and Spark pools. Uses public endpoints. Network security is handled through the Synapse Workspace firewall.

[synapse-private-workspace-sample.tf](./synapse-private-workspace-sample.tf) is a workspace with more focus placed on network perimiter. Synapse firewall is left completely closed. Private endpoints are used to enable use within the secured network (Vnets and other connected networks by peering, VPN, ExpressRoute).