# k3s-Xpress — Create cluster demo
# Usage: vhs docs/demos/k3s-create-cluster.tape

Output docs/demos/k3s-create-cluster.gif
Output docs/demos/k3s-create-cluster.mp4

Set FontSize 14
Set Width 1200
Set Height 700
Set Theme "Catppuccin Mocha"
Set Padding 20
Set TypingSpeed 40ms

Type "# k3s-Xpress — Production-ready k3s cluster on AWS in under 3 minutes"
Enter
Sleep 2s

Type "# Step 1: Create a k3s cluster"
Enter
Sleep 1s

Type 'ecp create-cluster my-k3s --distribution k3s --arch arm64 --pricing ondemand --k8s-version 1.35 --wait'
Enter
Sleep 200s

Type ""
Enter
Sleep 2s

Type "# Step 2: SSH into the cluster"
Enter
Sleep 1s

Type "ecp get-cluster-access my-k3s"
Enter
Sleep 5s

Type "# Step 3: Check nodes and pods"
Enter
Sleep 1s

Type "kubectl get nodes"
Enter
Sleep 3s

Type "kubectl get pods -A"
Enter
Sleep 5s

Type "# Step 4: Configure Karpenter node pool for worker autoscaling"
Enter
Sleep 1s

Type "sudo bash /opt/k3s-xpress/cluster-setup/karpenter/configure-nodepools.sh"
Enter
Sleep 15s

Type "kubectl get nodepools,ec2nodeclasses"
Enter
Sleep 3s

Type ""
Enter
Type "# ✓ k3s-Xpress cluster ready — VPC CNI, Karpenter, Workload Identity, CloudWatch, EBS CSI"
Enter
Sleep 3s

Type "# Clean up"
Enter
Type "ecp delete-cluster my-k3s"
Enter
Sleep 10s
