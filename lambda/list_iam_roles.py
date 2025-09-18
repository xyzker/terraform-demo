import boto3

def lambda_handler(event, context):
    iam = boto3.client('iam')
    roles = []
    paginator = iam.get_paginator('list_roles')
    for page in paginator.paginate():
        roles.extend(page['Roles'])
    # Return just the role names for brevity
    return {
        'role_names': [role['RoleName'] for role in roles],
        'count': len(roles)
    }
