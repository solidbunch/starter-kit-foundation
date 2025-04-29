# Terraform Infrastructure

This project creates AWS infrastructure using Terraform:
- A new VPC with IPv6 support
- Subnets with IPv6 CIDR blocks
- Internet Gateway and routing for IPv6
- Security Groups for HTTP(S) and SSH
- EC2 instances with IPv6 addresses and no public IPv4

---

## Prerequisites

- Terraform v1.5 or newer
- AWS CLI configured (`aws configure`)
- AWS credentials with permissions to create VPC, Subnets, EC2, Security Groups, Internet Gateway, and S3 bucket for state

---

## SSH Key Setup

Before applying Terraform:

- Make sure the folder `terraform/public_keys/` exists.
- Place your **public SSH key** inside it

This key will be uploaded to AWS and used for EC2 access.

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

### 3. Deploy the production environment (instances)

```bash
cd ../prod
terraform init
terraform apply
```

Confirm with `yes` when prompted.

---

## Result

- A new S3 bucket for Terraform state
- New VPC with IPv4 and automatically generated IPv6 block
- Three subnets, each with a dedicated IPv6 CIDR block
- Internet access for both IPv4 and IPv6
- Security Groups allowing HTTP, HTTPS, and SSH over both IPv4 and IPv6
- EC2 instance running with a public IPv6 address

After deployment, Terraform will output the IPv6 address of the created instance.

Connect using:

```bash
ssh -i path_to_private_key.pem admin@[INSTANCE_IPV6_ADDRESS]
```

Replace `path_to_private_key.pem` with your private key and `[INSTANCE_IPV6_ADDRESS]` with the actual IPv6 address.

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
