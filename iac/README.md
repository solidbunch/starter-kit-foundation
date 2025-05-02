# Terraform Infrastructure

This project creates AWS infrastructure using Terraform:
- A new VPC with IPv6 support
- Subnets with IPv6 CIDR blocks
- Internet Gateway and routing for IPv6
- Security Groups for HTTP(S) and SSH
- EC2 instances with public IPv6 and/or IPv4 addresses

---

## Prerequisites

- Terraform v1.5 or newer
- AWS CLI configured (`aws configure`)
- AWS credentials with permissions to create VPC, Subnets, EC2, Security Groups, Internet Gateway, and S3 bucket for state

---

## SSH Key Setup

Before applying Terraform:

- Make sure the folder `terraform/public_keys/` exists.
- Place your **public SSH key** inside it.

This key will be uploaded to Hosting provider and used for Instance access.

Use your **private key** locally to connect to the instances after deployment.

---

## Deployment Steps

### 1. Deploy the state backend (S3 bucket and DynamoDB)

```bash
cd terraform/state
terraform init
terraform apply
```

Confirm with `yes` when prompted.

### 2. Deploy shared infrastructure for VPC (network)

```bash
cd ../envs/shared
terraform init
terraform apply
```

Confirm with `yes` when prompted.

### 3. Deploy the development environment (instances)

```bash
cd ../dev
terraform init
terraform apply
```

Confirm with `yes` when prompted.

### 4. Deploy the production environment (instances)

```bash
cd ../prod
terraform init
terraform apply
```

Confirm with `yes` when prompted.

---

## Result

- A new S3 bucket for Terraform state
- New VPC with both IPv4 and IPv6
- Three subnets, each with a dedicated IPv4 and IPv6 CIDR block
- Internet access for both IPv4 and IPv6
- Security Groups allowing HTTP, HTTPS, and SSH over both IPv4 and IPv6
- EC2 instances running with public IPv4 and/or IPv6 addresses

After deployment, Terraform will output the public IP addresses of the created instances.

### SSH access

Configure your `~/.ssh/config.d/<project_ssh>/config` or `~/.ssh/config` file like this:

```
Host my-host-alias
    HostName <instance_ip_address>
    User admin
    IdentityFile ~/.ssh/<your_private_key>
```
You can use any alias you prefer (for example, `my-host-alias`) or a real hostname like `example.com`.  
You can use either the IPv4 or IPv6 address in `<instance_ip_address>`.

### Connect using SSH

```bash
ssh my-host-alias
```

**Notes:**
- Replace `<instance_ip_address>` with the actual IPv4 or IPv6 address from the Terraform output.
- Replace `<your_private_key>` with the filename of your private SSH key.

---

## Project Structure

```plaintext
terraform/
├── envs/
│   ├── dev/
│   ├── prod/
│   └── shared/
├── modules/
│   ├── instances/
│   ├── network/
│   └── security_groups/
├── public_keys/
└── state/
```

---

## Notes

- If you want new EC2 instances to automatically receive an IPv6 address without explicitly setting `ipv6_address_count`, update `modules/network/subnet.tf` to add:

```hcl
assign_ipv6_address_on_creation = true
```

### ⚙️ What to do if the instance IP address has changed

If the instance was recreated or its public IP was renewed, follow these steps to ensure everything keeps working smoothly:

1. **Update DNS records**  
   Update the DNS A or/and AAAA records for the affected domains to point to the new IP address.


2. **Update SSH configuration**  
   Update your local SSH configuration: `~/.ssh/config.d/<project_ssh>/config` or `~/.ssh/config` file


3. **Update SSH_CONFIG variable in Git**  
   Use same SSH Config for updating the `SSH_CONFIG` variable in your Git deployment pipeline or CI/CD system.


4. **Check Ansible inventory**  
   Check the Ansible inventory. Usually, it contains an alias or domain name, so you often don’t need to update the IP directly — but it’s important to verify.

## Destroy

To destroy the infrastructure, run in the needs infrastructure folder:

```bash
terraform destroy
```
