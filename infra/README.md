# Infra Repository

This repository is the third Git repository for the project.
It is meant to hold the full Ansible infrastructure code plus a Vault file for secrets.
At the moment it contains a scaffold and a bootstrap script that can copy the existing `ansible/` tree into this repository.

## What goes here
- Ansible inventory
- Ansible playbook
- All roles
- Group variables
- Vault file with secrets such as username and password

## Important note about secrets
Do not commit plaintext secrets.
Use Ansible Vault for any value that contains a username, password, token, or private key.

## Bootstrap from the current workspace
If you want to create this repository from the existing cluster workspace, run:

```bash
cd /home/vagrant
mkdir -p infra-repo
cp -r /vagrant/ansible infra-repo/
cp /vagrant/infra/ansible/group_vars/vault.yml infra-repo/ansible/group_vars/vault.yml
cd infra-repo/ansible
ansible-vault encrypt group_vars/vault.yml
```

## Vault file
The file [`ansible/group_vars/vault.yml`](ansible/group_vars/vault.yml) contains placeholder values for:
- username
- password

Replace them with real values, then encrypt the file before pushing.
