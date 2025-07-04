# charles-project
my 3 tier dev project 





cluster_endpoint = "https://DD90FB76E573A7357EB616E5D9735362.gr7.us-east-1.eks.amazonaws.com"
cluster_name = "three-tier-eks"
rds_endpoint = "three-tier-db.c9q6u4gi2psp.us-east-1.rds.amazonaws.com:5432"



#Retrieve Vault token from AWS aecrets manager
Setup VPC peering
Obtain CA cert and JWT


#k8s host:
https://DD90FB76E573A7357EB616E5D9735362.gr7.us-east-1.eks.amazonaws.com

jwt token:













1. Created an RDS PostgreSQL Database (via Terraform)
You provisioned a PostgreSQL instance using terraform-aws-modules/rds.

You used:

appdb as the database name

appuser as the master user

Vault will now generate temporary credentials instead of apps using this static user/password.

2. Created a Vault Cluster on HCP
Vault was set up in HashiCorp Cloud Platform (HCP).

You are using the HCP web UI and CLI.

Vault is outside your AWS VPC, so it can't talk to your RDS DB directly.

3. Enabled VPC Peering (HCP → AWS)
You established a VPC peering connection from HCP Vault’s HVN to your AWS VPC.

Updated route tables and security groups to allow traffic from Vault to RDS over port 5432.

📌 Why? → Vault needs to talk to RDS to generate dynamic users.

4. Enabled the Database Secrets Engine in Vault
You enabled the database secrets engine on Vault.

Configured the connection to your PostgreSQL RDS database.

📌 Why? → Vault needs this to create short-lived database users automatically.

5. Created a Vault Role for RDS Access
You wrote a Vault role (app-role) that:

Generates a user

Grants login + full DB access

Sets TTL for dynamic credentials (e.g., 1 hour)

📌 Why? → Apps will request credentials from Vault tied to this role.

6. Enabled Kubernetes Authentication in Vault
You enabled the Kubernetes auth method in Vault.

Provided:

kubernetes_host → EKS cluster endpoint

kubernetes_ca_cert → Used to verify the EKS API server

token_reviewer_jwt → From a service account (vault-auth) in EKS

📌 Why? → So Vault can authenticate pods using their service account identity in Kubernetes.

7. (Almost Done) — Next Step: Map K8s Service Account to Vault Role
You will map an EKS service account (e.g., app-sa) to the Vault app-role:

bash
Copy
Edit
vault write auth/kubernetes/role/app-role \
  bound_service_account_names=app-sa \
  bound_service_account_namespaces=default \
  policies=app-policy \
  ttl=24h





  You’re building a secure, automated way for applications running in your EKS cluster to fetch temporary database credentials from Vault, rather than hardcoding passwords.

Here’s the full picture:

1️⃣ You Created an EKS Cluster
This is where your app runs (Kubernetes).

Your pods will need access to a PostgreSQL database.

2️⃣ You Created an RDS PostgreSQL Database
Using Terraform.

You gave it a username (e.g., appuser) and a db_name (appdb).

This is where your app stores its data.

But instead of using a fixed username/password, you want Vault to generate temporary ones securely.

3️⃣ You Deployed a Vault Cluster (via HashiCorp Cloud - HCP)
Vault is a secrets manager.

You’re using it to:

Connect to your RDS

Dynamically generate PostgreSQL users with short TTL (e.g., 1 hour)

Authenticate your EKS pods so only authorized apps get credentials

4️⃣ You Set Up VPC Peering
Vault runs in a separate network (HashiCorp’s HVN)

Your RDS is in your AWS VPC

You set up VPC peering so Vault can reach the RDS using its private IP

You also updated route tables and security groups to allow this connection

5️⃣ You Configured Vault's Database Secrets Engine
You enabled Vault's ability to manage databases

Gave it:

RDS endpoint

Master username/password

Created a Vault role (app-role) that:

Tells Vault how to generate users for your RDS

Specifies what permissions those users have

Example: "Create a temporary user that can login and has full access to appdb"

6️⃣ You Enabled Kubernetes Auth in Vault
This is the part that lets Vault trust EKS pods based on their service account identity.

To do this, you:

Step	What You Did	Why
✅	Retrieved the EKS cluster endpoint	Vault needs it to talk to the Kubernetes API
✅	Retrieved the Kubernetes CA certificate	Vault uses it to verify that it's talking to a legit EKS API server
✅	Created a Kubernetes service account (e.g. vault-auth)	Used by Vault to call Kubernetes and validate pod identities
✅	Extracted the service account's JWT token	Vault uses this token to call the Kubernetes API securely
✅	Ran vault auth enable kubernetes and passed all that info	This tells Vault how to trust EKS pods and validate who they are

7️⃣ You Created a Vault Policy
The app-policy defines what actions the EKS pods are allowed to perform:

Read secrets

Generate DB credentials

You used HCL to declare permissions like path "database/*" with read, create, etc.

8️⃣ You Mapped a K8s Service Account to the Vault Role
You told Vault:

“Any pod using the app-sa service account in the default namespace can log in as app-role and get the app-policy.”

bash
Copy
Edit
vault write auth/kubernetes/role/app-role \
  bound_service_account_names=app-sa \
  bound_service_account_namespaces=default \
  policies=app-policy \
  ttl=24h
🔁 So Now, What Can Happen?
Any pod in EKS using the app-sa service account can:

Use its JWT token to authenticate with Vault

Vault validates the token with the Kubernetes API

Vault returns temporary RDS credentials

The pod uses those to access the database — no hardcoded secrets

✅ What You’ve Achieved:
✅ EKS cluster that runs your app

✅ PostgreSQL database with no hardcoded credentials

✅ Vault setup that:

Connects securely to RDS

Authenticates Kubernetes pods

Issues dynamic, time-bound credentials

✅ Secure networking using VPC peering

🧠 What's Actually Going On Behind the Scenes?
Think of Vault as a smart doorman that says:

"Hey pod, who are you? Show me your ID (JWT from service account). Ok, you're legit. Here's a temp database key that expires in 1 hour. Use it and don’t lose it."

⏭️ What’s Next?
You can now:

Deploy your app pods using app-sa

Inject Vault secrets into your pod via:

Init container

Sidecar (Vault Agent)

CSI driver

Env vars (less secure)

Want help with one of those integration options (e.g., using Vault Agent to fetch DB creds at runtime)?