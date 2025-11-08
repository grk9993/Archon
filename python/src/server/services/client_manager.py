"""
Client Manager Service

Manages database and API client connections.
Supports both PostgreSQL (recommended) and Supabase (legacy).
"""

import os
import re
from typing import Union

from supabase import Client, create_client

from ..config.logfire_config import search_logger
from ..config.config import get_config, validate_postgres_config_available, validate_supabase_config_available

# Import PostgreSQL client manager
try:
    from .postgres_client_manager import get_postgres_client, PostgreSQLClient
    POSTGRES_AVAILABLE = True
except ImportError:
    POSTGRES_AVAILABLE = False
    PostgreSQLClient = None


def get_database_client() -> Union[Client, 'PostgreSQLClient']:
    """
    Get the appropriate database client based on configuration.

    Priority: PostgreSQL > Supabase

    Returns:
        Either PostgreSQLClient or Supabase Client instance
    """
    # Check configuration priority
    has_postgres = validate_postgres_config_available()
    has_supabase = validate_supabase_config_available()

    if has_postgres and POSTGRES_AVAILABLE:
        search_logger.info("Using PostgreSQL database client")
        return get_postgres_client()
    elif has_supabase:
        search_logger.info("Using Supabase database client (legacy)")
        return get_supabase_client()
    else:
        raise ValueError(
            "No valid database configuration found. Please set either:\n"
            "1. PostgreSQL: POSTGRES_URL or POSTGRES_HOST/PORT/DB/USER/PASSWORD\n"
            "2. Supabase: SUPABASE_URL and SUPABASE_SERVICE_KEY"
        )


def get_supabase_client() -> Client:
    """
    Get a Supabase client instance (legacy support).

    Returns:
        Supabase client instance
    """
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_KEY")

    if not url or not key:
        raise ValueError(
            "SUPABASE_URL and SUPABASE_SERVICE_KEY must be set in environment variables"
        )

    try:
        # Let Supabase handle connection pooling internally
        client = create_client(url, key)

        # Extract project ID from URL for logging purposes only
        match = re.match(r"https://([^.]+)\.supabase\.co", url)
        if match:
            project_id = match.group(1)
            search_logger.debug(f"Supabase client initialized - project_id={project_id}")

        return client
    except Exception as e:
        search_logger.error(f"Failed to create Supabase client: {e}")
        raise


# Legacy alias for backward compatibility
def get_supabase_client_legacy() -> Client:
    """Legacy function name for backward compatibility."""
    return get_supabase_client()
