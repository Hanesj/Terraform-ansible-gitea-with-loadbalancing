cd ../Terraform
terraform apply -auto-approve
> ~/.ssh/known_hosts
cd ~/ansible
ansible-playbook -i inventory playbook.yaml
cat lbip.txt
