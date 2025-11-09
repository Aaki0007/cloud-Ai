#!/usr/bin/python
"""
LocalStack AI Chatbot Infrastructure Demo
Demonstrates S3 and DynamoDB operations for the chatbot system
"""

import boto3
import json
from datetime import datetime
from botocore.exceptions import ClientError

# Configure boto3 to use LocalStack
def get_localstack_client(service_name):
    """Create a boto3 client configured for LocalStack"""
    return boto3.client(
        service_name,
        endpoint_url='http://localhost:4566',
        aws_access_key_id='test',
        aws_secret_access_key='test',
        region_name='us-east-1'
    )

# Initialize clients
s3_client = get_localstack_client('s3')
dynamodb_client = get_localstack_client('dynamodb')
dynamodb_resource = boto3.resource(
    'dynamodb',
    endpoint_url='http://localhost:4566',
    aws_access_key_id='test',
    aws_secret_access_key='test',
    region_name='us-east-1'
)

# Configuration
BUCKET_NAME = 'chatbot-conversations'
TABLE_NAME = 'chatbot-sessions'

def verify_s3_bucket():
    """Verify S3 bucket exists and is accessible"""
    print("\n" + "="*60)
    print("🪣 TESTING S3 BUCKET")
    print("="*60)
    
    try:
        # List all buckets
        response = s3_client.list_buckets()
        print(f"✓ Found {len(response['Buckets'])} bucket(s):")
        for bucket in response['Buckets']:
            print(f"  - {bucket['Name']}")
        
        # Verify our bucket exists
        if BUCKET_NAME in [b['Name'] for b in response['Buckets']]:
            print(f"\n✓ Target bucket '{BUCKET_NAME}' exists!")
            return True
        else:
            print(f"\n✗ Bucket '{BUCKET_NAME}' not found!")
            return False
    except ClientError as e:
        print(f"✗ Error accessing S3: {e}")
        return False

def test_s3_operations():
    """Test S3 upload and download operations"""
    print("\n" + "="*60)
    print("📤 TESTING S3 OPERATIONS")
    print("="*60)
    
    # Create sample conversation data
    user_id = "12345678"
    model_name = "llama3"
    session_id = "session_" + datetime.now().strftime("%Y%m%d_%H%M%S")
    
    conversation_data = {
        "user_id": user_id,
        "model": model_name,
        "session_id": session_id,
        "timestamp": datetime.now().isoformat(),
        "messages": [
            {"role": "user", "content": "Hello! How are you?"},
            {"role": "assistant", "content": "I'm doing great! How can I help you today?"},
            {"role": "user", "content": "Tell me about Python."},
            {"role": "assistant", "content": "Python is a versatile programming language..."}
        ],
        "metadata": {
            "temperature": 0.7,
            "max_tokens": 2000,
            "ollama_endpoint": "http://localhost:11434"
        }
    }
    
    # Upload to S3
    s3_key = f"{user_id}/model_{model_name}/{session_id}.json"
    try:
        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=s3_key,
            Body=json.dumps(conversation_data, indent=2),
            ContentType='application/json'
        )
        print(f"✓ Uploaded conversation to: s3://{BUCKET_NAME}/{s3_key}")
        
        # List objects in bucket
        response = s3_client.list_objects_v2(Bucket=BUCKET_NAME)
        if 'Contents' in response:
            print(f"\n✓ Files in bucket:")
            for obj in response['Contents']:
                print(f"  - {obj['Key']} ({obj['Size']} bytes)")
        
        # Download and verify
        response = s3_client.get_object(Bucket=BUCKET_NAME, Key=s3_key)
        downloaded_data = json.loads(response['Body'].read())
        print(f"\n✓ Downloaded and verified conversation data")
        print(f"  - Session: {downloaded_data['session_id']}")
        print(f"  - Messages: {len(downloaded_data['messages'])}")
        
        return s3_key
    except ClientError as e:
        print(f"✗ Error with S3 operations: {e}")
        return None

def verify_dynamodb_table():
    """Verify DynamoDB table exists and check its structure"""
    print("\n" + "="*60)
    print("🗄️  TESTING DYNAMODB TABLE")
    print("="*60)
    
    try:
        # List tables
        response = dynamodb_client.list_tables()
        print(f"✓ Found {len(response['TableNames'])} table(s):")
        for table_name in response['TableNames']:
            print(f"  - {table_name}")
        
        # Describe our table
        if TABLE_NAME in response['TableNames']:
            print(f"\n✓ Target table '{TABLE_NAME}' exists!")
            
            table_info = dynamodb_client.describe_table(TableName=TABLE_NAME)
            table_desc = table_info['Table']
            
            print(f"\nTable Details:")
            print(f"  - Status: {table_desc['TableStatus']}")
            print(f"  - Item Count: {table_desc['ItemCount']}")
            print(f"  - Keys:")
            for key in table_desc['KeySchema']:
                print(f"    • {key['AttributeName']} ({key['KeyType']})")
            
            if 'GlobalSecondaryIndexes' in table_desc:
                print(f"  - Global Secondary Indexes:")
                for gsi in table_desc['GlobalSecondaryIndexes']:
                    print(f"    • {gsi['IndexName']}")
            
            return True
        else:
            print(f"\n✗ Table '{TABLE_NAME}' not found!")
            return False
    except ClientError as e:
        print(f"✗ Error accessing DynamoDB: {e}")
        return False

def test_dynamodb_operations(s3_path=None):
    """Test DynamoDB CRUD operations"""
    print("\n" + "="*60)
    print("💾 TESTING DYNAMODB OPERATIONS")
    print("="*60)
    
    table = dynamodb_resource.Table(TABLE_NAME)
    
    # Sample session data
    user_id = "12345678"
    model_name = "llama3"
    session_id = "session_" + datetime.now().strftime("%Y%m%d_%H%M%S")
    
    # 1. PUT ITEM - Create a new session
    print("\n1️⃣ Creating new session...")
    try:
        item = {
            'pk': f'USER#{user_id}',
            'sk': f'MODEL#{model_name}#SESSION#{session_id}',
            'user_id': user_id,
            'chat_id': '987654321',
            'model_name': model_name,
            'session_id': session_id,
            'conversation': json.dumps([
                {"role": "user", "content": "Hello!"},
                {"role": "assistant", "content": "Hi there!"}
            ]),
            'last_message_ts': datetime.now().isoformat(),
            'status': 'active',
            'ollama_endpoint': 'http://localhost:11434',
            'temperature': '0.7',
            'max_tokens': '2000',
            's3_path': s3_path or ''
        }
        
        table.put_item(Item=item)
        print(f"✓ Created session: {session_id}")
        print(f"  - PK: {item['pk']}")
        print(f"  - SK: {item['sk']}")
    except ClientError as e:
        print(f"✗ Error creating session: {e}")
        return
    
    # 2. GET ITEM - Retrieve the session
    print("\n2️⃣ Retrieving session...")
    try:
        response = table.get_item(
            Key={
                'pk': f'USER#{user_id}',
                'sk': f'MODEL#{model_name}#SESSION#{session_id}'
            }
        )
        if 'Item' in response:
            print(f"✓ Retrieved session successfully")
            print(f"  - Model: {response['Item']['model_name']}")
            print(f"  - Status: {response['Item']['status']}")
            print(f"  - Last message: {response['Item']['last_message_ts']}")
        else:
            print("✗ Session not found")
    except ClientError as e:
        print(f"✗ Error retrieving session: {e}")
    
    # 3. QUERY - Get all sessions for a user
    print("\n3️⃣ Querying all sessions for user...")
    try:
        response = table.query(
            KeyConditionExpression='pk = :pk',
            ExpressionAttributeValues={
                ':pk': f'USER#{user_id}'
            }
        )
        print(f"✓ Found {response['Count']} session(s) for user {user_id}")
        for item in response['Items']:
            print(f"  - {item['sk']} (Status: {item['status']})")
    except ClientError as e:
        print(f"✗ Error querying sessions: {e}")
    
    # 4. UPDATE ITEM - Update session status
    print("\n4️⃣ Updating session status...")
    try:
        table.update_item(
            Key={
                'pk': f'USER#{user_id}',
                'sk': f'MODEL#{model_name}#SESSION#{session_id}'
            },
            UpdateExpression='SET #status = :status, last_message_ts = :ts',
            ExpressionAttributeNames={
                '#status': 'status'
            },
            ExpressionAttributeValues={
                ':status': 'archived',
                ':ts': datetime.now().isoformat()
            }
        )
        print(f"✓ Updated session status to 'archived'")
    except ClientError as e:
        print(f"✗ Error updating session: {e}")
    
    # 5. QUERY GSI - Query by model name across all users
    print("\n5️⃣ Querying Global Secondary Index (GSI)...")
    try:
        response = dynamodb_client.query(
            TableName=TABLE_NAME,
            IndexName='model_index',
            KeyConditionExpression='model_name = :model',
            ExpressionAttributeValues={
                ':model': {'S': model_name}
            }
        )
        print(f"✓ Found {response['Count']} session(s) using model '{model_name}'")
    except ClientError as e:
        print(f"✗ Error querying GSI: {e}")
    
    # 6. SCAN - Get all items (for demo purposes)
    print("\n6️⃣ Scanning entire table...")
    try:
        response = table.scan()
        print(f"✓ Total items in table: {response['Count']}")
    except ClientError as e:
        print(f"✗ Error scanning table: {e}")

def cleanup_demo_data():
    """Optional: Clean up demo data"""
    print("\n" + "="*60)
    print("🧹 CLEANUP (Optional)")
    print("="*60)
    
    choice = input("\nDo you want to clean up demo data? (y/n): ").lower()
    if choice != 'y':
        print("Skipping cleanup.")
        return
    
    # Clean S3
    try:
        response = s3_client.list_objects_v2(Bucket=BUCKET_NAME)
        if 'Contents' in response:
            for obj in response['Contents']:
                s3_client.delete_object(Bucket=BUCKET_NAME, Key=obj['Key'])
                print(f"✓ Deleted S3 object: {obj['Key']}")
    except ClientError as e:
        print(f"✗ Error cleaning S3: {e}")
    
    # Clean DynamoDB
    try:
        table = dynamodb_resource.Table(TABLE_NAME)
        response = table.scan()
        for item in response['Items']:
            table.delete_item(
                Key={
                    'pk': item['pk'],
                    'sk': item['sk']
                }
            )
            print(f"✓ Deleted DynamoDB item: {item['pk']} / {item['sk']}")
    except ClientError as e:
        print(f"✗ Error cleaning DynamoDB: {e}")
    
    print("\n✓ Cleanup complete!")

def main():
    """Main demo function"""
    print("\n" + "="*60)
    print("🚀 LOCALSTACK AI CHATBOT INFRASTRUCTURE DEMO")
    print("="*60)
    print("\nThis script will demonstrate:")
    print("  • S3 bucket operations (upload/download)")
    print("  • DynamoDB CRUD operations")
    print("  • Global Secondary Index queries")
    print("\nMake sure LocalStack is running: docker compose up -d")
    print("="*60)
    
    input("\nPress Enter to start the demo...")
    
    # Run tests
    s3_exists = verify_s3_bucket()
    if not s3_exists:
        print("\n⚠️  S3 bucket not found. Run 'terraform apply' first!")
        return
    
    s3_path = test_s3_operations()
    
    dynamodb_exists = verify_dynamodb_table()
    if not dynamodb_exists:
        print("\n⚠️  DynamoDB table not found. Run 'terraform apply' first!")
        return
    
    test_dynamodb_operations(s3_path)
    
    cleanup_demo_data()
    
    print("\n" + "="*60)
    print("✅ DEMO COMPLETE!")
    print("="*60)
    print("\nYour LocalStack infrastructure is working correctly!")
    print("You can now use these resources for your AI chatbot.\n")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  Demo interrupted by user.")
    except Exception as e:
        print(f"\n\n❌ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
