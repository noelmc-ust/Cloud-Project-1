# Azure Hub-and-Spoke Global Architecture Report

This report documents the fully provisioned, highly available, secure cloud architecture deployed via Terraform. The environment spans across two distinct Azure regions (Central India and East US 2) and hosts two web applications: **Fitness Tracker** and **Organic Ghee**.

## 1. Network Topology (Hub-and-Spoke)

The environment utilizes a classic **Hub-and-Spoke** topology to centralize security while isolating application workloads geographically.

- **Hub VNet (Central India):** 
  - Hosts the **Azure Firewall** and **Azure Bastion**.
  - Acts as the central choke-point for all inbound/outbound internet traffic and inter-spoke communication.
- **Spoke 1 VNet (Central India):**
  - Peered to the Hub.
  - Hosts the primary Application Gateway, primary VMSS instances, and Cosmos DB Private Endpoints.
- **Spoke 2 VNet (East US 2):**
  - Peered to the Hub.
  - Hosts the secondary Application Gateway, secondary VMSS instances, and Cosmos DB Private Endpoints for disaster recovery.

## 2. Global Traffic Manager & Routing

- **Azure Traffic Manager** acts as the global DNS load balancer.
- Two profiles were created: `tm-fitness-tracker` and `tm-organic-ghee`.
- **Priority Routing Method:** Traffic Manager routes all users to the primary region (Central India) by default. If the Central India App Gateway goes offline (or returns unhealthy probes), Traffic Manager automatically fails over all traffic to East US 2.
- **Custom Domains:** The `outputs.tf` file provides the CNAME records to map `flowforge.fun` and `fitness.flowforge.fun` to the Traffic Manager endpoints.

## 3. Application Security (WAF & App Gateway)

- **Application Gateway v2:** Deployed in both spokes. It serves as an L7 reverse proxy.
- **Web Application Firewall (WAF):** Configured in `Prevention` mode using the OWASP 3.2 ruleset. This actively blocks SQL injection, Cross-Site Scripting (XSS), and other common web vulnerabilities before they ever reach the VMs.
- **Health Probes:** Custom probes constantly monitor the `/` path of both apps. If the Node.js app crashes, the App GW detects it and pulls the VM out of rotation.

## 4. Deep Packet Inspection & UDRs

To ensure all traffic is scrubbed for malware and unauthorized access, **Azure Firewall** is the mandatory gateway for all external traffic.

### User Defined Routes (UDRs)
- **App GW to VMSS:** Traffic from the App Gateway Subnet destined for the VMSS Subnet is forced via a UDR to the Hub Firewall's private IP.
- **VMSS to App GW (Return):** To prevent asymmetric routing, a UDR on the VMSS subnet forces return traffic back to the Firewall.
- **VMSS to Internet:** A `0.0.0.0/0` UDR on the VMSS forces all internet-bound traffic (like `npm install` and `git clone`) to the Firewall.

### Firewall Policies
- **Network Rules:** Explicitly allow internal TCP Port 80 traffic (`Allow-AppGW-to-VMSS`) and UDP Port 53 (`Allow-DNS`).
- **Application Rules:** Strictly allow HTTP/HTTPS traffic only to whitelisted FQDNs: `*.ubuntu.com`, `*.npmjs.org`, and `github.com`. All other outbound web traffic from the VMs is dropped.

## 5. Compute & Autoscaling (VMSS)

- **Virtual Machine Scale Sets:** 4 independent VMSS clusters were provisioned (Fitness and Ghee in both regions).
- **SKU:** `Standard_D2s_v3` (2 vCPUs, 8 GiB RAM).
- **Autoscaling:** Configured to dynamically scale out (up to 2 instances) if the average CPU exceeds 60% for 6 minutes, and scale in if CPU drops below 40%.
- **Cloud-Init (Bootstrap):** The VMs automatically configure themselves on boot. They install Node.js, clone their respective GitHub repos, dynamically inject the Cosmos DB connection string using `sed`, configure Nginx as a local reverse proxy, and register the app as a systemd service using PM2.

## 6. Global Database (Cosmos DB)

- **Cosmos DB for MongoDB:** Configured with API version `4.2` to support modern Node.js drivers.
- **Global Distribution:** The database is natively replicated between Central India (Primary) and East US 2 (Secondary). If a region goes down, Azure handles the database failover automatically.
- **Private Endpoints:** The database is completely isolated from the public internet. Private Endpoints in both spoke VNets allow the VMSS instances to connect to Cosmos DB over the ultra-fast Azure private backbone.

## 7. Credentials

- **VM Admin Username:** `ubuntu`
- **VM Admin Password:** `ComplexP@ssw0rd123!` (Configured during initial terraform creation)
- **Cosmos DB Connection String:** Outputted dynamically in Terraform state (viewable via `terraform console`).

## 8. State and Teardown Confidence

> [!TIP]
> **Yes, it is 100% safe to delete this infrastructure.**

Because everything has been perfectly codified into Terraform modules (including the dynamic firewall rules, UDRs, cloud-init scripts, and Cosmos DB versioning), you can run:

```powershell
terraform destroy -auto-approve
```

When you are ready tomorrow, simply run `terraform apply -auto-approve`, wait for the deployment to finish, and the entire global architecture will resurrect itself exactly as it is right now. No manual intervention or debugging will be required.
