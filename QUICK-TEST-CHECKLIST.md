# Quick Testing Checklist

Use this for rapid verification. See [TESTING-DEPLOYMENT.md](TESTING-DEPLOYMENT.md) for detailed instructions.

## ☐ Phase 1: Terraform (5 min)
```bash
cd E:/DEVOPS/live/dev/03-github-oidc
cp terraform.tfvars.example terraform.tfvars
# Edit: github_owner, github_repo
terraform init && terraform apply
# Save output: github_actions_role_arn
```

## ☐ Phase 2: GitHub Secrets (2 min)
```bash
cd E:/CI
gh secret set AWS_ROLE_ARN --body "arn:aws:iam::XXX..."
gh secret set AWS_REGION --body "us-east-1"
gh secret list  # Verify both set
```

## ☐ Phase 3: EC2 Setup (10 min)
```bash
# Find instance
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Environment,Values=dev" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

# Check SSM
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$INSTANCE_ID"

# Connect
aws ssm start-session --target $INSTANCE_ID

# On EC2 (optional - everything is automated):
# Just verify SSM agent is running (Docker will be installed automatically)
sudo systemctl status amazon-ssm-agent
exit
```

## ☐ Phase 4: Test Manual Deployment (5 min)
```bash
cd E:/CI
gh workflow run deploy.yml
gh run watch  # Watch until complete

# In parallel, monitor EC2:
aws ssm start-session --target $INSTANCE_ID
tail -f /var/log/ci-deploy.log
```

**Expected:** ✅ All green, deployment successful

## ☐ Phase 5: Verify Deployment (3 min)
```bash
# On EC2:
docker ps  # 3 containers running
docker compose ps  # All healthy
curl http://localhost:8000/health  # {"status":"healthy"}
curl http://localhost:8000/version  # Shows version
curl http://localhost:3000/  # HTML response
```

## ☐ Phase 6: Test Auto-Deploy (10 min)
```bash
cd E:/CI
git checkout -b test-deploy
echo "test" >> README.md
git add . && git commit -m "test: auto-deploy"
git push origin test-deploy
gh pr create --title "Test Auto Deploy" --body "Testing"
# Wait for CI to pass
gh pr merge --merge --delete-branch
gh run watch  # Deploy should trigger automatically
```

**Expected:** ✅ Deployment triggers and succeeds after merge

## ☐ Phase 7: Verify Everything Works

**All green?** 🎉 You're done!

- ✅ Terraform applied
- ✅ Secrets configured
- ✅ EC2 prepared
- ✅ Manual deployment works
- ✅ Auto deployment works
- ✅ Health checks pass
- ✅ Rollback tested

## 🚨 Quick Troubleshooting

**OIDC fails:** Check Terraform output matches GitHub secret
```bash
terraform output github_actions_role_arn
gh secret list | grep AWS_ROLE_ARN
```

**Instance not found:** Check tags
```bash
aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID"
```

**SSM not online:** Restart agent
```bash
sudo systemctl restart amazon-ssm-agent
```

**Images not found:** Check CI pushed them
```bash
gh run list --workflow=ci.yml --limit 1
```

**Health checks fail:** Check logs
```bash
docker compose logs backend frontend
```

## 📝 Common Commands

```bash
# Watch deployment
gh run watch

# View logs on EC2
tail -f /var/log/ci-deploy.log

# Check containers
docker compose ps

# Manual rollback
cd /opt/ci-app
source .last-successful-deployment
docker compose down && docker compose up -d
```

## 🎯 Success = All Checkboxes Checked!

