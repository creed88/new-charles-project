#Enable AWS secrets engine

path "aws/*" { capabilities = ["create", "read", "update", "delete", "list"] }

#Enable database secrets engine

path "database/*" { capabilities = ["create", "read", "update", "delete", "list"] }

#Policy for Kubernetes pods to access secrets

path "secret/data/app/*" { capabilities = ["read"] }

#Configure Kubernetes auth

path "auth/kubernetes/*" { capabilities = ["create", "read", "update", "delete", "list"] }



