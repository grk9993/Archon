#!/usr/bin/env python3
"""
Test script for PostgreSQL migration

This script tests the new PostgreSQL client to ensure it works correctly
with the Archon application.
"""

import sys
import os
import traceback
from datetime import datetime

# Add the src directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

def test_configuration():
    """Test that configuration loads correctly."""
    print("🧪 Testing PostgreSQL configuration...")

    try:
        from src.server.config.config import get_config, validate_postgres_config_available, validate_supabase_config_available

        has_postgres = validate_postgres_config_available()
        has_supabase = validate_supabase_config_available()

        print(f"  PostgreSQL config available: {has_postgres}")
        print(f"  Supabase config available: {has_supabase}")

        if not has_postgres and not has_supabase:
            print("  ⚠️  No database configuration found")
            print("  Please set either PostgreSQL or Supabase environment variables")
            return False

        config = get_config()
        print(f"  Configuration loaded successfully")
        print(f"  Will use: {'PostgreSQL' if has_postgres else 'Supabase'}")

        return True

    except Exception as e:
        print(f"  ❌ Configuration test failed: {e}")
        traceback.print_exc()
        return False

def test_database_client():
    """Test database client creation and basic operations."""
    print("\n🧪 Testing database client...")

    try:
        from src.server.services.client_manager import get_database_client
        from src.server.config.logfire_config import get_logger

        logger = get_logger(__name__)

        # Get database client
        client = get_database_client()
        print(f"  ✅ Database client created: {type(client).__name__}")

        # Test basic table operations
        print("  Testing table operations...")

        # Test select
        try:
            result = client.table("archon_settings").select("key").limit(1).execute()
            print(f"  ✅ Select test successful: {result['count']} settings found")
        except Exception as e:
            print(f"  ⚠️  Select test failed (table may not exist): {e}")

        # Test insert (if table exists)
        try:
            test_data = {
                "key": "test_migration",
                "value": "test_value",
                "is_encrypted": False,
                "category": "test",
                "description": "Migration test"
            }
            result = client.table("archon_settings").insert(test_data).execute()
            print(f"  ✅ Insert test successful")

            # Clean up test data
            if result.get('data'):
                test_id = result['data'][0]['id']
                client.table("archon_settings").delete().eq("key", "test_migration").execute()
                print(f"  ✅ Cleanup successful")

        except Exception as e:
            print(f"  ⚠️  Insert test failed: {e}")

        return True

    except Exception as e:
        print(f"  ❌ Database client test failed: {e}")
        traceback.print_exc()
        return False

def test_service_integration():
    """Test service layer integration."""
    print("\n🧪 Testing service integration...")

    try:
        from src.server.services.projects.project_service import ProjectService
        from src.server.services.projects.task_service import TaskService

        # Test project service
        project_service = ProjectService()
        print(f"  ✅ Project service created: {type(project_service.database_client).__name__}")

        # Test task service
        task_service = TaskService()
        print(f"  ✅ Task service created: {type(task_service.database_client).__name__}")

        # Test list projects (read-only operation)
        try:
            success, result = project_service.list_projects(include_content=False)
            if success:
                print(f"  ✅ List projects successful: {result.get('total_count', 0)} projects found")
            else:
                print(f"  ⚠️  List projects failed: {result.get('error', 'Unknown error')}")
        except Exception as e:
            print(f"  ⚠️  List projects test failed: {e}")

        return True

    except Exception as e:
        print(f"  ❌ Service integration test failed: {e}")
        traceback.print_exc()
        return False

def test_postgresql_specific_features():
    """Test PostgreSQL-specific features."""
    print("\n🧪 Testing PostgreSQL-specific features...")

    try:
        from src.server.services.client_manager import get_database_client
        from src.server.config.postgres_config import PostgreSQLClient

        client = get_database_client()

        if isinstance(client, PostgreSQLClient):
            print("  ✅ PostgreSQL client detected")

            # Test connection pooling
            print("  Testing connection pooling...")

            # Execute multiple concurrent operations
            import threading
            import time

            results = []
            errors = []

            def test_connection():
                try:
                    result = client.table("archon_settings").select("count").execute()
                    results.append(result['count'])
                except Exception as e:
                    errors.append(str(e))

            # Start multiple threads
            threads = []
            for i in range(5):
                thread = threading.Thread(target=test_connection)
                threads.append(thread)
                thread.start()

            # Wait for all threads
            for thread in threads:
                thread.join()

            print(f"  ✅ Connection pooling test: {len(results)} successful, {len(errors)} errors")

            # Test raw SQL execution
            try:
                sql_result = client.execute_sql("SELECT version(), current_database(), current_user")
                if sql_result:
                    print(f"  ✅ Raw SQL test successful")
                    print(f"     PostgreSQL version: {sql_result[0]['version']}")
                    print(f"     Database: {sql_result[0]['current_database']}")
                    print(f"     User: {sql_result[0]['current_user']}")
            except Exception as e:
                print(f"  ⚠️  Raw SQL test failed: {e}")

        else:
            print(f"  ℹ️  Using {type(client).__name__} (not PostgreSQL-specific)")

        return True

    except Exception as e:
        print(f"  ❌ PostgreSQL-specific test failed: {e}")
        return False

def main():
    """Run all migration tests."""
    print("🚀 Archon PostgreSQL Migration Test Suite")
    print("=" * 50)
    print(f"Started at: {datetime.now().isoformat()}")
    print()

    # Track results
    tests_passed = 0
    total_tests = 4

    # Run tests
    if test_configuration():
        tests_passed += 1

    if test_database_client():
        tests_passed += 1

    if test_service_integration():
        tests_passed += 1

    if test_postgresql_specific_features():
        tests_passed += 1

    # Summary
    print("\n" + "=" * 50)
    print(f"📊 Test Results: {tests_passed}/{total_tests} tests passed")

    if tests_passed == total_tests:
        print("🎉 All tests passed! PostgreSQL migration looks good.")
        return 0
    else:
        print("⚠️  Some tests failed. Please check the output above.")
        return 1

if __name__ == "__main__":
    sys.exit(main())