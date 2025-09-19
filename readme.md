# After deployment, test S3 access:
```
kubectl exec -it aws-cli-test -- aws s3 ls
```


# Configure kubectl
```
aws eks update-kubeconfig --region us-east-1 --name minimal-eks
```

# Test the setup
```
kubectl get nodes
kubectl get pods
kubectl exec -it aws-cli-test -- aws sts get-caller-identity
```