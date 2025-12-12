"""DynamoDB configuration and operations with error handling and monitoring."""

import logging
import os
import uuid
from datetime import UTC, datetime
from typing import Optional

import boto3
from botocore.exceptions import ClientError, NoCredentialsError

from config import settings


logger = logging.getLogger(__name__)

# DynamoDB client and table name
dynamodb_client = None
dynamodb_resource = None
table_name = None
database_available = False

def get_table_name_from_ssm(environment: str, table_key: str = "greetings") -> Optional[str]:
    """
    Get DynamoDB table name from SSM Parameter Store.
    
    Args:
        environment: Environment name (e.g., 'dev', 'staging', 'prod')
        table_key: Table identifier (e.g., 'greetings')
    
    Returns:
        Table name from SSM Parameter Store, or None if not found
    """
    try:
        ssm_client = boto3.client("ssm", region_name=os.getenv("AWS_REGION", "us-east-1"))
        parameter_name = f"/{environment}/dynamodb/{table_key}/table_name"
        
        response = ssm_client.get_parameter(Name=parameter_name)
        return response["Parameter"]["Value"]
    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "")
        if error_code == "ParameterNotFound":
            logger.debug(f"SSM parameter '{parameter_name}' not found, will use environment variable fallback")
        else:
            logger.warning(f"Error reading SSM parameter '{parameter_name}': {e}")
        return None
    except Exception as e:
        logger.warning(f"Unexpected error reading SSM parameter: {e}")
        return None


# Initialize DynamoDB client
try:
    # Get table name from SSM Parameter Store (preferred) or environment variable (fallback)
    environment = os.getenv("ENVIRONMENT", "dev")
    table_key = os.getenv("DYNAMODB_TABLE_KEY", "greetings")  # Configurable table key
    
    # Check if DynamoDB Local endpoint is configured (for local testing/E2E)
    dynamodb_endpoint_url = os.getenv("DYNAMODB_ENDPOINT_URL")
    
    # Try SSM Parameter Store first (best practice) - skip in testing/local mode
    if not settings.TESTING and not dynamodb_endpoint_url:
        # SSM Parameter path: /{environment}/dynamodb/{table_key}/table_name
        table_name = get_table_name_from_ssm(environment, table_key)
    else:
        table_name = None
    
    # Fallback to environment variable if SSM parameter not found
    if table_name is None:
        table_name = os.getenv("DYNAMODB_TABLE_NAME", f"{environment}-{table_key}")
        logger.info(f"Using table name from environment variable: {table_name}")
    else:
        logger.info(f"Using table name from SSM Parameter Store: {table_name} (key: {table_key})")
    
    # Initialize boto3 clients with optional endpoint URL for DynamoDB Local
    client_config = {"region_name": os.getenv("AWS_REGION", "us-east-1")}
    resource_config = {"region_name": os.getenv("AWS_REGION", "us-east-1")}
    
    if dynamodb_endpoint_url:
        client_config["endpoint_url"] = dynamodb_endpoint_url
        resource_config["endpoint_url"] = dynamodb_endpoint_url
        logger.info(f"Using DynamoDB Local endpoint: {dynamodb_endpoint_url}")
    
    dynamodb_client = boto3.client("dynamodb", **client_config)
    dynamodb_resource = boto3.resource("dynamodb", **resource_config)
    
    # Verify table exists
    try:
        dynamodb_client.describe_table(TableName=table_name)
        database_available = True
        logger.info(f"DynamoDB table '{table_name}' is available")
    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "")
        if error_code == "ResourceNotFoundException":
            logger.warning(
                f"DynamoDB table '{table_name}' not found. "
                "Database features will be unavailable. "
                "Ensure the table is created via Terraform or initialization script."
            )
            database_available = False
        else:
            logger.error(f"Error checking DynamoDB table: {e}")
            database_available = False
    except NoCredentialsError:
        # In DynamoDB Local mode, credentials are not required
        if dynamodb_endpoint_url:
            logger.info("DynamoDB Local mode: credentials not required")
            # Table might not exist yet, but client is available
            database_available = False  # Will be set to True after table creation
        else:
            logger.warning(
                "AWS credentials not found. DynamoDB features will be unavailable. "
                "Ensure ECS task role has DynamoDB permissions."
            )
            database_available = False
except Exception as e:
    logger.error(f"Failed to initialize DynamoDB client: {e}")
    database_available = False


# =============================================================================
# DynamoDB Models/Structures
# =============================================================================


class Greeting:
    """Greeting model for DynamoDB items."""

    def __init__(self, id: str, user_name: str, message: str, created_at: Optional[str] = None):
        self.id = id
        self.user_name = user_name
        self.message = message
        self.created_at = created_at or datetime.now(UTC).isoformat()

    def to_dict(self) -> dict:
        """Convert to DynamoDB item format."""
        return {
            "id": self.id,
            "user_name": self.user_name,
            "message": self.message,
            "created_at": self.created_at,
        }

    @classmethod
    def from_dict(cls, item: dict) -> "Greeting":
        """Create Greeting from DynamoDB item."""
        return cls(
            id=item.get("id", ""),
            user_name=item.get("user_name", ""),
            message=item.get("message", ""),
            created_at=item.get("created_at"),
        )

    def __repr__(self):
        return (
            f"<Greeting(id='{self.id}', user_name='{self.user_name}', "
            f"created_at='{self.created_at}')>"
        )


# =============================================================================
# Database Operations
# =============================================================================


def init_db():
    """
    Verify DynamoDB table exists (tables are created via Terraform).
    
    Raises:
        Exception: If table verification fails.
    """
    if not database_available or dynamodb_client is None:
        logger.warning("DynamoDB is not available. Skipping table verification.")
        return

    try:
        response = dynamodb_client.describe_table(TableName=table_name)
        logger.info(
            f"DynamoDB table '{table_name}' verified successfully. "
            f"Status: {response['Table']['TableStatus']}"
        )
    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "")
        if error_code == "ResourceNotFoundException":
            logger.error(
                f"DynamoDB table '{table_name}' not found. "
                "Please create the table via Terraform before deploying the application."
            )
            raise
        else:
            logger.error(f"Error verifying DynamoDB table: {e}")
            raise
    except Exception as e:
        logger.error(f"Unexpected error verifying DynamoDB table: {e}")
        raise


def get_db():
    """
    Get DynamoDB table resource.
    
    Yields:
        Table: DynamoDB table resource.
    
    Raises:
        RuntimeError: If DynamoDB is not available.
    """
    if not database_available or dynamodb_resource is None or table_name is None:
        raise RuntimeError(
            "DynamoDB is not available. Table name is not configured or table does not exist."
        )

    table = dynamodb_resource.Table(table_name)
    yield table


def create_greeting(user_name: str, message: str) -> Greeting:
    """
    Create a new greeting in DynamoDB.
    
    Args:
        user_name: Name of the user
        message: Greeting message
    
    Returns:
        Greeting: Created greeting object
    
    Raises:
        ClientError: If DynamoDB operation fails
    """
    if not database_available or dynamodb_resource is None or table_name is None:
        raise RuntimeError("DynamoDB is not available")

    greeting = Greeting(
        id=str(uuid.uuid4()),
        user_name=user_name,
        message=message,
    )

    table = dynamodb_resource.Table(table_name)
    try:
        table.put_item(Item=greeting.to_dict())
        logger.info(f"Created greeting: {greeting.id} for user: {user_name}")
        return greeting
    except ClientError as e:
        logger.error(f"Error creating greeting in DynamoDB: {e}")
        raise


def get_greetings(skip: int = 0, limit: int = 10) -> tuple[list[Greeting], int]:
    """
    Get all greetings with pagination.
    
    Args:
        skip: Number of items to skip
        limit: Maximum number of items to return
    
    Returns:
        tuple: (list of greetings, total count)
    
    Raises:
        ClientError: If DynamoDB operation fails
    """
    if not database_available or dynamodb_resource is None or table_name is None:
        raise RuntimeError("DynamoDB is not available")

    table = dynamodb_resource.Table(table_name)
    
    try:
        # Scan table (for small datasets, consider using Query with GSI for better performance)
        # Note: Scan is expensive for large tables - consider pagination with LastEvaluatedKey
        response = table.scan(
            Limit=limit + skip,  # Get more items to account for skip
        )
        
        items = response.get("Items", [])
        
        # Apply skip and limit manually (DynamoDB doesn't support offset natively)
        # For production, use LastEvaluatedKey for proper pagination
        total = len(items)
        items = items[skip : skip + limit]
        
        greetings = [Greeting.from_dict(item) for item in items]
        
        # Get total count (approximate for large tables)
        # For exact count, use a separate count operation or maintain count in separate item
        # Note: Scan with Select="COUNT" returns approximate count for large tables
        # For now, use the count from the scan response
        total_count = response.get("Count", 0)
        
        # If there are more items, we need to paginate (for now, return approximate count)
        # In production, consider maintaining a separate count item or using a more efficient method
        return greetings, total_count
    except ClientError as e:
        logger.error(f"Error getting greetings from DynamoDB: {e}")
        raise


def get_user_greetings(user_name: str) -> list[Greeting]:
    """
    Get all greetings for a specific user using GSI.
    
    Args:
        user_name: Name of the user
    
    Returns:
        list: List of greetings for the user
    
    Raises:
        ClientError: If DynamoDB operation fails
    """
    if not database_available or dynamodb_resource is None or table_name is None:
        raise RuntimeError("DynamoDB is not available")

    table = dynamodb_resource.Table(table_name)
    
    try:
        # Query using GSI on user_name
        response = table.query(
            IndexName="user-name-index",
            KeyConditionExpression="user_name = :user_name",
            ExpressionAttributeValues={":user_name": user_name},
        )
        
        items = response.get("Items", [])
        greetings = [Greeting.from_dict(item) for item in items]
        
        logger.info(f"Found {len(greetings)} greetings for user: {user_name}")
        return greetings
    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "")
        if error_code == "ResourceNotFoundException":
            logger.warning(
                f"GSI 'user-name-index' not found. "
                "Falling back to scan (less efficient)."
            )
            # Fallback to scan if GSI doesn't exist
            return _get_user_greetings_scan(user_name)
        logger.error(f"Error getting user greetings from DynamoDB: {e}")
        raise


def _get_user_greetings_scan(user_name: str) -> list[Greeting]:
    """Fallback method using scan (less efficient)."""
    if not database_available or dynamodb_resource is None or table_name is None:
        raise RuntimeError("DynamoDB is not available")

    table = dynamodb_resource.Table(table_name)
    
    try:
        response = table.scan(
            FilterExpression="user_name = :user_name",
            ExpressionAttributeValues={":user_name": user_name},
        )
        
        items = response.get("Items", [])
        greetings = [Greeting.from_dict(item) for item in items]
        return greetings
    except ClientError as e:
        logger.error(f"Error scanning for user greetings: {e}")
        raise
