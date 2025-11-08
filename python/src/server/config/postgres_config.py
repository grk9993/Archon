"""
PostgreSQL configuration management for direct database connections.
"""

import os
from dataclasses import dataclass
from urllib.parse import urlparse


class ConfigurationError(Exception):
    """Raised when there's an error in configuration."""
    pass


@dataclass
class PostgreSQLConfig:
    """Configuration for PostgreSQL database connection."""

    host: str
    port: int
    database: str
    username: str
    password: str
    # Optional SSL configuration
    ssl_mode: str = "prefer"
    ssl_cert: str | None = None
    ssl_key: str | None = None
    ssl_root_cert: str | None = None

    @property
    def connection_string(self) -> str:
        """Build PostgreSQL connection string."""
        conn_str = f"postgresql://{self.username}:{self.password}@{self.host}:{self.port}/{self.database}"

        # Add SSL parameters if provided
        params = []
        if self.ssl_mode != "disable":
            params.append(f"sslmode={self.ssl_mode}")
            if self.ssl_cert:
                params.append(f"sslcert={self.ssl_cert}")
            if self.ssl_key:
                params.append(f"sslkey={self.ssl_key}")
            if self.ssl_root_cert:
                params.append(f"sslrootcert={self.ssl_root_cert}")

        if params:
            conn_str += "?" + "&".join(params)

        return conn_str


def validate_postgres_url(url: str) -> tuple[bool, str]:
    """Validate PostgreSQL URL format.

    Returns:
        tuple[bool, str]: (is_valid, error_message)
    """
    if not url:
        return False, "PostgreSQL URL cannot be empty"

    try:
        parsed = urlparse(url)

        # Check scheme
        if parsed.scheme not in ("postgresql", "postgres"):
            return False, f"URL must use postgresql:// or postgres:// scheme, got: {parsed.scheme}"

        # Check required components
        if not parsed.hostname:
            return False, "Missing hostname in PostgreSQL URL"

        if not parsed.username:
            return False, "Missing username in PostgreSQL URL"

        if not parsed.password:
            return False, "Missing password in PostgreSQL URL"

        if not parsed.path or parsed.path == "/":
            return False, "Missing database name in PostgreSQL URL"

        # Extract port (default to 5432)
        port = parsed.port or 5432
        if not (1 <= port <= 65535):
            return False, f"Invalid port number: {port}"

        return True, ""

    except Exception as e:
        return False, f"Invalid PostgreSQL URL format: {str(e)}"


def load_postgres_config() -> PostgreSQLConfig:
    """Load PostgreSQL configuration from environment variables.

    Environment Variables:
        POSTGRES_URL: Full PostgreSQL connection URL (postgresql://user:pass@host:port/db)
        POSTGRES_HOST: Database host (default: localhost)
        POSTGRES_PORT: Database port (default: 5432)
        POSTGRES_DB: Database name (required if not using POSTGRES_URL)
        POSTGRES_USER: Database username (required if not using POSTGRES_URL)
        POSTGRES_PASSWORD: Database password (required if not using POSTGRES_URL)
        POSTGRES_SSL_MODE: SSL mode (default: prefer)
        POSTGRES_SSL_CERT: Path to SSL certificate file (optional)
        POSTGRES_SSL_KEY: Path to SSL key file (optional)
        POSTGRES_SSL_ROOT_CERT: Path to SSL root certificate file (optional)

    Returns:
        PostgreSQLConfig: Configuration object

    Raises:
        ConfigurationError: If configuration is invalid or incomplete
    """

    # Try to use full URL first
    postgres_url = os.getenv("POSTGRES_URL")

    if postgres_url:
        # Validate full URL
        is_valid, error_msg = validate_postgres_url(postgres_url)
        if not is_valid:
            raise ConfigurationError(f"Invalid POSTGRES_URL: {error_msg}")

        # Parse URL
        parsed = urlparse(postgres_url)

        return PostgreSQLConfig(
            host=parsed.hostname or "localhost",
            port=parsed.port or 5432,
            database=parsed.path.lstrip("/"),
            username=parsed.username or "",
            password=parsed.password or "",
            ssl_mode="prefer"  # Default for URL-based connections
        )

    # Fall back to individual components
    host = os.getenv("POSTGRES_HOST", "localhost")
    port_str = os.getenv("POSTGRES_PORT", "5432")
    database = os.getenv("POSTGRES_DB")
    username = os.getenv("POSTGRES_USER")
    password = os.getenv("POSTGRES_PASSWORD")
    ssl_mode = os.getenv("POSTGRES_SSL_MODE", "prefer")

    # Validate required fields
    if not database:
        raise ConfigurationError(
            "POSTGRES_DB or POSTGRES_URL environment variable is required"
        )

    if not username:
        raise ConfigurationError(
            "POSTGRES_USER or POSTGRES_URL environment variable is required"
        )

    if not password:
        raise ConfigurationError(
            "POSTGRES_PASSWORD or POSTGRES_URL environment variable is required"
        )

    # Validate port
    try:
        port = int(port_str)
    except ValueError:
        raise ConfigurationError(f"POSTGRES_PORT must be a valid integer, got: {port_str}")

    if not (1 <= port <= 65535):
        raise ConfigurationError(f"POSTGRES_PORT must be between 1 and 65535, got: {port}")

    # Get optional SSL configuration
    ssl_cert = os.getenv("POSTGRES_SSL_CERT")
    ssl_key = os.getenv("POSTGRES_SSL_KEY")
    ssl_root_cert = os.getenv("POSTGRES_SSL_ROOT_CERT")

    return PostgreSQLConfig(
        host=host,
        port=port,
        database=database,
        username=username,
        password=password,
        ssl_mode=ssl_mode,
        ssl_cert=ssl_cert,
        ssl_key=ssl_key,
        ssl_root_cert=ssl_root_cert
    )


def get_postgres_config() -> PostgreSQLConfig:
    """Get PostgreSQL configuration with validation."""
    return load_postgres_config()