"""AWS Secrets Manager integration for dynamic secret retrieval.

This module provides dynamic secret discovery and retrieval without hardcoding ARNs.
Secrets are discovered via SSM Parameter Store, then retrieved from Secrets Manager.
"""

import json
import logging
import os
from typing import Any, Optional

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)


def discover_secret_name(secret_identifier: str, region: Optional[str] = None) -> str:
    """
    Discover secret name from SSM Parameter Store.
    
    This function reads the secret name from SSM Parameter Store, allowing
    applications to discover secrets dynamically without hardcoding ARNs or names.
    
    Args:
        secret_identifier: Secret identifier (e.g., 'jwt-signing-key', 'external-api-key')
        region: AWS region (defaults to AWS_REGION env var or 'us-east-1')
    
    Returns:
        str: Full secret name (e.g., 'dev/test-app/jwt-signing-key')
    
    Raises:
        ValueError: If secret discovery parameter not found
    """
    if region is None:
        region = os.getenv("AWS_REGION", "us-east-1")
    
    environment = os.getenv("ENVIRONMENT", "dev")
    application = os.getenv("APPLICATION", "test-app")
    
    # SSM Parameter path: /{environment}/{application}/secrets/{secret_identifier}/secret_name
    ssm_parameter_name = f"/{environment}/{application}/secrets/{secret_identifier}/secret_name"
    
    try:
        ssm_client = boto3.client("ssm", region_name=region)
        response = ssm_client.get_parameter(Name=ssm_parameter_name)
        secret_name = response["Parameter"]["Value"]
        logger.debug(f"Discovered secret name '{secret_name}' for identifier '{secret_identifier}'")
        return secret_name
    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "")
        if error_code == "ParameterNotFound":
            logger.warning(
                f"Secret discovery parameter '{ssm_parameter_name}' not found. "
                f"Secret '{secret_identifier}' may not be configured in infrastructure."
            )
            # Fallback: construct secret name from pattern
            fallback_name = f"{environment}/{application}/{secret_identifier}"
            logger.info(f"Using fallback secret name: {fallback_name}")
            return fallback_name
        else:
            logger.error(f"Error discovering secret '{secret_identifier}': {e}")
            raise
    except Exception as e:
        logger.error(f"Unexpected error discovering secret '{secret_identifier}': {e}")
        raise


def get_secret_from_secrets_manager(
    secret_name: str, region: Optional[str] = None
) -> dict[str, Any]:
    """
    Retrieve secret from AWS Secrets Manager.
    
    Args:
        secret_name: Name of the secret (e.g., 'dev/test-app/api-key')
                    Can be full ARN or just the name
        region: AWS region (defaults to AWS_REGION env var or 'us-east-1')
    
    Returns:
        dict: Secret value parsed as JSON if JSON, else {"value": secret_string}
    
    Raises:
        ClientError: If secret cannot be retrieved
        ValueError: If secret is not found and no fallback available
    """
    if region is None:
        region = os.getenv("AWS_REGION", "us-east-1")
    
    try:
        client = boto3.client("secretsmanager", region_name=region)
        
        response = client.get_secret_value(SecretId=secret_name)
        secret_string = response["SecretString"]
        
        # Try to parse as JSON, fallback to string
        try:
            return json.loads(secret_string)
        except json.JSONDecodeError:
            # If not JSON, return as dict with "value" key
            return {"value": secret_string}
            
    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "")
        if error_code == "ResourceNotFoundException":
            logger.error(f"Secret '{secret_name}' not found in Secrets Manager")
        elif error_code == "AccessDeniedException":
            logger.error(
                f"Access denied to secret '{secret_name}'. "
                "Check IAM permissions on ECS task execution role."
            )
        else:
            logger.error(f"Error retrieving secret '{secret_name}': {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error retrieving secret '{secret_name}': {e}")
        raise


def get_secret_value(
    secret_identifier: str,
    key: Optional[str] = None,
    env_var_fallback: Optional[str] = None,
    region: Optional[str] = None,
    use_discovery: bool = True,
) -> str:
    """
    Get a secret value dynamically with automatic discovery.
    
    This function:
    1. Discovers secret name from SSM Parameter Store (if use_discovery=True)
    2. Retrieves secret value from Secrets Manager
    3. Extracts specific key if secret is JSON
    4. Falls back to environment variable if secret not found
    
    Args:
        secret_identifier: Secret identifier (e.g., 'jwt-signing-key', 'external-api-key')
                          or full secret name (e.g., 'dev/test-app/jwt-signing-key')
        key: Key to extract from JSON secret (if None, returns "value" for string secrets)
        env_var_fallback: Environment variable name to use as fallback
        region: AWS region
        use_discovery: If True, discover secret name via SSM Parameter Store (recommended)
    
    Returns:
        str: Secret value
    
    Raises:
        ValueError: If secret not found and no fallback available
    """
    # Discover secret name from SSM Parameter Store (dynamic discovery)
    if use_discovery:
        try:
            secret_name = discover_secret_name(secret_identifier, region)
        except Exception as e:
            logger.warning(f"Secret discovery failed for '{secret_identifier}': {e}")
            # Fallback to using identifier as secret name
            environment = os.getenv("ENVIRONMENT", "dev")
            application = os.getenv("APPLICATION", "test-app")
            secret_name = f"{environment}/{application}/{secret_identifier}"
    else:
        # Use identifier directly as secret name
        environment = os.getenv("ENVIRONMENT", "dev")
        if not secret_identifier.startswith(environment):
            application = os.getenv("APPLICATION", "test-app")
            secret_name = f"{environment}/{application}/{secret_identifier}"
        else:
            secret_name = secret_identifier
    
    # Try Secrets Manager first (production)
    try:
        secret = get_secret_from_secrets_manager(secret_name, region)
        
        # Extract value based on key
        if key:
            value = secret.get(key)
            if value is None:
                raise ValueError(
                    f"Key '{key}' not found in secret '{secret_name}'. "
                    f"Available keys: {list(secret.keys())}"
                )
            return str(value)
        else:
            # Return "value" key for string secrets, or first value for JSON
            return secret.get("value") or str(list(secret.values())[0])
            
    except Exception as e:
        logger.warning(f"Could not retrieve secret '{secret_identifier}' from Secrets Manager: {e}")
        
        # Fallback to environment variable (local development)
        if env_var_fallback:
            value = os.getenv(env_var_fallback)
            if value:
                logger.info(f"Using {env_var_fallback} from environment variable (local dev)")
                return value
        
        # No fallback available
        raise ValueError(
            f"Secret '{secret_identifier}' not found in Secrets Manager "
            f"and {env_var_fallback or 'environment variable'} not set"
        )


# Convenience functions for common secret types
def get_jwt_signing_key(env_var: Optional[str] = None) -> str:
    """
    Get JWT signing key for authentication tokens.
    
    Args:
        env_var: Environment variable name for fallback (defaults to JWT_SIGNING_KEY)
    
    Returns:
        str: JWT signing key value
    """
    if env_var is None:
        env_var = "JWT_SIGNING_KEY"
    
    return get_secret_value(
        secret_identifier="jwt-signing-key",
        key="value",
        env_var_fallback=env_var,
        use_discovery=True,
    )


def get_session_secret(env_var: Optional[str] = None) -> str:
    """
    Get session encryption secret for secure cookies.
    
    Args:
        env_var: Environment variable name for fallback (defaults to SESSION_SECRET)
    
    Returns:
        str: Session secret value
    """
    if env_var is None:
        env_var = "SESSION_SECRET"
    
    return get_secret_value(
        secret_identifier="session-secret",
        key="value",
        env_var_fallback=env_var,
        use_discovery=True,
    )


def get_external_api_key(env_var: Optional[str] = None) -> str:
    """
    Get external API key for third-party service integration.
    
    Args:
        env_var: Environment variable name for fallback (defaults to EXTERNAL_API_KEY)
    
    Returns:
        str: API key value
    """
    if env_var is None:
        env_var = "EXTERNAL_API_KEY"
    
    return get_secret_value(
        secret_identifier="external-api-key",
        key="value",
        env_var_fallback=env_var,
        use_discovery=True,
    )


def get_backend_api_key(env_var: Optional[str] = None) -> str:
    """
    Get backend API key for API authentication.
    
    This key is used to authenticate requests to the backend API endpoints.
    Clients must include this key in the X-API-Key header.
    
    Args:
        env_var: Environment variable name for fallback (defaults to BACKEND_API_KEY)
    
    Returns:
        str: Backend API key value
    
    Raises:
        ValueError: If secret not found and no fallback available
    """
    if env_var is None:
        env_var = "BACKEND_API_KEY"
    
    return get_secret_value(
        secret_identifier="backend-api-key",
        key="value",
        env_var_fallback=env_var,
        use_discovery=True,
    )


def get_api_key(service_name: str, env_var: Optional[str] = None) -> str:
    """
    Get API key for a service (generic function).
    
    Args:
        service_name: Service identifier (e.g., 'external-api', 'payment-gateway')
        env_var: Environment variable name for fallback (defaults to {SERVICE_NAME}_API_KEY)
    
    Returns:
        str: API key value
    """
    if env_var is None:
        env_var = f"{service_name.upper().replace('-', '_')}_API_KEY"
    
    return get_secret_value(
        secret_identifier=f"{service_name}-api-key",
        key="value",
        env_var_fallback=env_var,
        use_discovery=True,
    )


def get_database_credentials(env_var_prefix: Optional[str] = None) -> dict[str, str]:
    """
    Get database credentials from Secrets Manager (for future use with RDS or other databases).
    
    Note: DynamoDB doesn't use traditional credentials (uses IAM), but this function
    is available for future database integrations.
    
    Args:
        env_var_prefix: Prefix for environment variable fallback (e.g., 'DB' for DB_USERNAME, DB_PASSWORD)
    
    Returns:
        dict: Database credentials with keys: username, password, host, port, database
    """
    if env_var_prefix is None:
        env_var_prefix = "DB"
    
    try:
        # Try to discover secret name via SSM Parameter Store
        secret_name = discover_secret_name("database-credentials")
        secret = get_secret_from_secrets_manager(secret_name)
        return {
            "username": secret.get("username", ""),
            "password": secret.get("password", ""),
            "host": secret.get("host", ""),
            "port": str(secret.get("port", "")),
            "database": secret.get("database", ""),
        }
    except Exception as e:
        logger.warning(f"Could not retrieve database credentials from Secrets Manager: {e}")
        
        # Fallback to environment variables
        return {
            "username": os.getenv(f"{env_var_prefix}_USERNAME", ""),
            "password": os.getenv(f"{env_var_prefix}_PASSWORD", ""),
            "host": os.getenv(f"{env_var_prefix}_HOST", ""),
            "port": os.getenv(f"{env_var_prefix}_PORT", ""),
            "database": os.getenv(f"{env_var_prefix}_NAME", ""),
        }
