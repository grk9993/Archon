"""
PostgreSQL Client Manager Service

Manages direct PostgreSQL database connections using psycopg2.
"""

import os
import psycopg2
import psycopg2.extras
from psycopg2.pool import ThreadedConnectionPool
from contextlib import contextmanager
from typing import Optional, Dict, Any, List, Union
import json
from datetime import datetime, timezone

from ..config.logfire_config import search_logger
from ..config.postgres_config import get_postgres_config, PostgreSQLConfig


class DatabaseError(Exception):
    """Raised when there's a database operation error."""
    pass


class PostgreSQLClient:
    """
    PostgreSQL client that provides similar functionality to Supabase client
    but uses direct PostgreSQL connections.
    """

    def __init__(self, config: PostgreSQLConfig):
        self.config = config
        self.pool: Optional[ThreadedConnectionPool] = None
        self._initialize_pool()

    def _initialize_pool(self):
        """Initialize connection pool."""
        try:
            self.pool = ThreadedConnectionPool(
                minconn=1,
                maxconn=20,
                host=self.config.host,
                port=self.config.port,
                database=self.config.database,
                user=self.config.username,
                password=self.config.password,
                sslmode=self.config.ssl_mode,
                sslcert=self.config.ssl_cert,
                sslkey=self.config.ssl_key,
                sslrootcert=self.config.ssl_root_cert,
            )
            search_logger.debug("PostgreSQL connection pool initialized")
        except Exception as e:
            search_logger.error(f"Failed to initialize PostgreSQL pool: {e}")
            raise DatabaseError(f"Failed to initialize database connection: {e}")

    @contextmanager
    def get_connection(self):
        """Get a connection from the pool."""
        conn = None
        try:
            conn = self.pool.getconn()
            yield conn
            conn.commit()
        except Exception as e:
            if conn:
                conn.rollback()
            raise e
        finally:
            if conn:
                self.pool.putconn(conn)

    @contextmanager
    def get_cursor(self, cursor_factory=psycopg2.extras.RealDictCursor):
        """Get a cursor from the pool."""
        with self.get_connection() as conn:
            with conn.cursor(cursor_factory=cursor_factory) as cursor:
                yield cursor

    # Table operations (equivalent to Supabase table operations)
    def table(self, table_name: str):
        """Return a table query builder."""
        return PostgreSQLTable(self, table_name)

    # RPC functions (for stored procedures)
    def rpc(self, function_name: str, params: Optional[Dict[str, Any]] = None):
        """Call a stored procedure."""
        return PostgreSQLRPC(self, function_name, params or {})

    # Raw SQL execution
    def execute_sql(self, sql: str, params: Optional[tuple] = None) -> List[Dict[str, Any]]:
        """Execute raw SQL query."""
        try:
            with self.get_cursor() as cursor:
                cursor.execute(sql, params)
                if cursor.description:
                    return cursor.fetchall()
                return []
        except Exception as e:
            search_logger.error(f"SQL execution error: {e}")
            raise DatabaseError(f"Database query failed: {e}")

    def execute_sql_one(self, sql: str, params: Optional[tuple] = None) -> Optional[Dict[str, Any]]:
        """Execute raw SQL query and return single row."""
        try:
            with self.get_cursor() as cursor:
                cursor.execute(sql, params)
                return cursor.fetchone()
        except Exception as e:
            search_logger.error(f"SQL execution error: {e}")
            raise DatabaseError(f"Database query failed: {e}")

    def execute_sql_mutate(self, sql: str, params: Optional[tuple] = None) -> int:
        """Execute INSERT/UPDATE/DELETE and return affected row count."""
        try:
            with self.get_cursor() as cursor:
                cursor.execute(sql, params)
                return cursor.rowcount
        except Exception as e:
            search_logger.error(f"SQL mutation error: {e}")
            raise DatabaseError(f"Database mutation failed: {e}")

    def close(self):
        """Close all connections in the pool."""
        if self.pool:
            self.pool.closeall()
            search_logger.debug("PostgreSQL connection pool closed")


class PostgreSQLTable:
    """Query builder for PostgreSQL table operations (similar to Supabase table API)."""

    def __init__(self, client: PostgreSQLClient, table_name: str):
        self.client = client
        self.table_name = table_name
        self.select_columns = "*"
        self.where_conditions = []
        self.where_params = []
        self.order_by_clause = ""
        self.limit_count = None
        self.offset_count = None

    def select(self, columns: str = "*") -> 'PostgreSQLTable':
        """Specify columns to select."""
        self.select_columns = columns
        return self

    def eq(self, column: str, value: Any) -> 'PostgreSQLTable':
        """Add equality condition."""
        self.where_conditions.append(f"{column} = %s")
        self.where_params.append(value)
        return self

    def neq(self, column: str, value: Any) -> 'PostgreSQLTable':
        """Add not equal condition."""
        self.where_conditions.append(f"{column} != %s")
        self.where_params.append(value)
        return self

    def gt(self, column: str, value: Any) -> 'PostgreSQLTable':
        """Add greater than condition."""
        self.where_conditions.append(f"{column} > %s")
        self.where_params.append(value)
        return self

    def gte(self, column: str, value: Any) -> 'PostgreSQLTable':
        """Add greater than or equal condition."""
        self.where_conditions.append(f"{column} >= %s")
        self.where_params.append(value)
        return self

    def lt(self, column: str, value: Any) -> 'PostgreSQLTable':
        """Add less than condition."""
        self.where_conditions.append(f"{column} < %s")
        self.where_params.append(value)
        return self

    def lte(self, column: str, value: Any) -> 'PostgreSQLTable':
        """Add less than or equal condition."""
        self.where_conditions.append(f"{column} <= %s")
        self.where_params.append(value)
        return self

    def like(self, column: str, pattern: str) -> 'PostgreSQLTable':
        """Add LIKE condition."""
        self.where_conditions.append(f"{column} LIKE %s")
        self.where_params.append(pattern)
        return self

    def ilike(self, column: str, pattern: str) -> 'PostgreSQLTable':
        """Add ILIKE condition (case-insensitive)."""
        self.where_conditions.append(f"{column} ILIKE %s")
        self.where_params.append(pattern)
        return self

    def in_(self, column: str, values: List[Any]) -> 'PostgreSQLTable':
        """Add IN condition."""
        if not values:
            self.where_conditions.append("FALSE")  # No values match
        else:
            placeholders = ", ".join(["%s"] * len(values))
            self.where_conditions.append(f"{column} IN ({placeholders})")
            self.where_params.extend(values)
        return self

    def is_(self, column: str, value: Any) -> 'PostgreSQLTable':
        """Add IS NULL/IS NOT NULL condition."""
        if value is None:
            self.where_conditions.append(f"{column} IS NULL")
        else:
            self.where_conditions.append(f"{column} IS %s")
            self.where_params.append(value)
        return self

    def order(self, column: str, desc: bool = False) -> 'PostgreSQLTable':
        """Add ORDER BY clause."""
        direction = "DESC" if desc else "ASC"
        self.order_by_clause = f"ORDER BY {column} {direction}"
        return self

    def limit(self, count: int) -> 'PostgreSQLTable':
        """Add LIMIT clause."""
        self.limit_count = count
        return self

    def offset(self, count: int) -> 'PostgreSQLTable':
        """Add OFFSET clause."""
        self.offset_count = count
        return self

    def execute(self) -> Dict[str, Any]:
        """Execute the query and return results."""
        try:
            # Build query
            sql = f"SELECT {self.select_columns} FROM {self.table_name}"

            if self.where_conditions:
                where_clause = " AND ".join(self.where_conditions)
                sql += f" WHERE {where_clause}"

            if self.order_by_clause:
                sql += f" {self.order_by_clause}"

            if self.limit_count is not None:
                sql += f" LIMIT {self.limit_count}"

            if self.offset_count is not None:
                sql += f" OFFSET {self.offset_count}"

            # Execute query
            with self.client.get_cursor() as cursor:
                cursor.execute(sql, tuple(self.where_params))
                results = cursor.fetchall()

                return {"data": results, "count": len(results)}

        except Exception as e:
            search_logger.error(f"Table query error for {self.table_name}: {e}")
            raise DatabaseError(f"Database query failed: {e}")

    def insert(self, data: Union[Dict[str, Any], List[Dict[str, Any]]]) -> Dict[str, Any]:
        """Insert data into the table."""
        try:
            if isinstance(data, dict):
                data = [data]

            if not data:
                return {"data": [], "count": 0}

            # Get column names from first record
            columns = list(data[0].keys())
            placeholders = ", ".join(["%s"] * len(columns))
            column_list = ", ".join(columns)

            sql = f"INSERT INTO {self.table_name} ({column_list}) VALUES ({placeholders}) RETURNING *"

            results = []
            with self.client.get_cursor() as cursor:
                for record in data:
                    values = tuple(record[col] for col in columns)
                    cursor.execute(sql, values)
                    results.append(cursor.fetchone())

                return {"data": results, "count": len(results)}

        except Exception as e:
            search_logger.error(f"Table insert error for {self.table_name}: {e}")
            raise DatabaseError(f"Database insert failed: {e}")

    def update(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Update records in the table."""
        try:
            if not self.where_conditions:
                raise DatabaseError("UPDATE requires WHERE conditions for safety")

            # Build SET clause
            set_columns = ", ".join([f"{col} = %s" for col in data.keys()])
            set_values = list(data.values())

            # Build WHERE clause
            where_clause = " AND ".join(self.where_conditions)

            sql = f"UPDATE {self.table_name} SET {set_columns} WHERE {where_clause} RETURNING *"
            all_params = set_values + self.where_params

            with self.client.get_cursor() as cursor:
                cursor.execute(sql, tuple(all_params))
                results = cursor.fetchall()

                return {"data": results, "count": len(results)}

        except Exception as e:
            search_logger.error(f"Table update error for {self.table_name}: {e}")
            raise DatabaseError(f"Database update failed: {e}")

    def delete(self) -> Dict[str, Any]:
        """Delete records from the table."""
        try:
            if not self.where_conditions:
                raise DatabaseError("DELETE requires WHERE conditions for safety")

            where_clause = " AND ".join(self.where_conditions)
            sql = f"DELETE FROM {self.table_name} WHERE {where_clause} RETURNING *"

            with self.client.get_cursor() as cursor:
                cursor.execute(sql, tuple(self.where_params))
                results = cursor.fetchall()

                return {"data": results, "count": len(results)}

        except Exception as e:
            search_logger.error(f"Table delete error for {self.table_name}: {e}")
            raise DatabaseError(f"Database delete failed: {e}")


class PostgreSQLRPC:
    """RPC function caller (for stored procedures)."""

    def __init__(self, client: PostgreSQLClient, function_name: str, params: Dict[str, Any]):
        self.client = client
        self.function_name = function_name
        self.params = params

    def execute(self) -> Dict[str, Any]:
        """Execute the stored procedure."""
        try:
            # Build parameter placeholders
            param_placeholders = ", ".join([f"%({key})s" for key in self.params.keys()])
            sql = f"SELECT * FROM {self.function_name}({param_placeholders})"

            with self.client.get_cursor() as cursor:
                cursor.execute(sql, self.params)
                results = cursor.fetchall()

                return {"data": results, "count": len(results)}

        except Exception as e:
            search_logger.error(f"RPC execution error for {self.function_name}: {e}")
            raise DatabaseError(f"Database function call failed: {e}")


# Global client instance
_postgres_client: Optional[PostgreSQLClient] = None


def get_postgres_client() -> PostgreSQLClient:
    """Get PostgreSQL client instance."""
    global _postgres_client

    if _postgres_client is None:
        config = get_postgres_config()
        _postgres_client = PostgreSQLClient(config)
        search_logger.debug("PostgreSQL client initialized")

    return _postgres_client


def reset_postgres_client():
    """Reset the global PostgreSQL client (useful for testing)."""
    global _postgres_client

    if _postgres_client:
        _postgres_client.close()
        _postgres_client = None
        search_logger.debug("PostgreSQL client reset")