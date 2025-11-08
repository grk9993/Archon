# PostgreSQL Migration Guide

This guide helps you migrate from Supabase to your own PostgreSQL database for better performance, cost savings, and no usage limits.

## 🎯 Why Migrate to PostgreSQL?

- **Cost Savings**: No Supabase usage limits or fees
- **Better Performance**: Direct database connections without API overhead
- **Full Control**: Complete control over your database configuration
- **No Vendor Lock-in**: Standard PostgreSQL that works anywhere
- **Scalability**: Scale as large as your hardware allows

## 📋 Migration Checklist

### 1. Prerequisites

- [ ] PostgreSQL 15+ server with pgvector extension support
- [ ] Database user with full privileges
- [ ] Network access to PostgreSQL server from your application
- [ ] Backup of your current Supabase data (if migrating existing data)

### 2. Environment Configuration

#### Option A: Full Connection URL (Recommended)
```bash
# Add to your .env file
POSTGRES_URL=postgresql://username:password@hostname:port/database

# Example:
POSTGRES_URL=postgresql://dbuser:mypassword@localhost:5432/archon
```

#### Option B: Individual Components
```bash
# Add to your .env file
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=archon
POSTGRES_USER=dbuser
POSTGRES_PASSWORD=your-secure-password

# Optional SSL configuration
POSTGRES_SSL_MODE=prefer
POSTGRES_SSL_CERT=/path/to/client-cert.pem
POSTGRES_SSL_KEY=/path/to/client-key.pem
POSTGRES_SSL_ROOT_CERT=/path/to/ca-cert.pem
```

### 3. Database Setup

#### A. Install PostgreSQL Extensions
Connect to your PostgreSQL database and run:
```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

#### B. Apply Schema
Run the complete schema setup:
```bash
# Copy the schema file to your database server or run locally
psql -h your-host -d your-database -U your-user -f migration/postgres_setup.sql
```

Or execute the schema manually through your database client.

### 4. Application Configuration

#### Update Dependencies
The application now includes `psycopg2-binary` in the requirements. Run:
```bash
cd python
uv sync --group all
```

#### Configuration Validation
The application automatically detects your database configuration:
- **PostgreSQL**: Uses `POSTGRES_URL` or individual `POSTGRES_*` variables
- **Supabase**: Uses `SUPABASE_URL` and `SUPABASE_SERVICE_KEY` (legacy)
- **Priority**: PostgreSQL takes precedence if both are configured

#### Test Configuration
```bash
cd python
uv run python -c "
from src.server.config.config import get_config
from src.server.services.client_manager import get_database_client
config = get_config()
client = get_database_client()
print('✅ Database configuration successful!')
print(f'Using: {type(client).__name__}')
"
```

## 🔧 Database Setup Options

### Option 1: Docker PostgreSQL with pgvector
```bash
# Run PostgreSQL with pgvector in Docker
docker run -d \
  --name archon-postgres \
  -e POSTGRES_DB=archon \
  -e POSTGRES_USER=dbuser \
  -e POSTGRES_PASSWORD=your-secure-password \
  -p 5432:5432 \
  ankane/pgvector:v0.5.1

# Set environment variable
POSTGRES_URL=postgresql://dbuser:your-secure-password@localhost:5432/archon
```

### Option 2: Cloud PostgreSQL Services

#### AWS RDS PostgreSQL
```bash
# Create RDS instance with PostgreSQL 15+
# Enable pgvector extension in parameter group
# Set security group to allow access from your application

POSTGRES_URL=postgresql://dbuser:password@your-rds-endpoint:5432/archon
```

#### Google Cloud SQL PostgreSQL
```bash
# Create Cloud SQL instance with PostgreSQL 15+
# Enable pgvector extension
# Configure authorized networks

POSTGRES_URL=postgresql://dbuser:password@your-cloud-sql-ip:5432/archon
```

#### Azure Database for PostgreSQL
```bash
# Create Azure Database for PostgreSQL
# Enable pgvector extension
# Configure firewall rules

POSTGRES_URL=postgresql://dbuser:password@your-azure-server:5432/archon
```

### Option 3: Self-Hosted PostgreSQL
```bash
# Install PostgreSQL 15+ on your server
# Install pgvector extension
# Configure postgresql.conf for optimal performance

# Add to postgresql.conf:
shared_buffers = 256MB
work_mem = 64MB
maintenance_work_mem = 256MB
max_connections = 200
```

## 🔄 Data Migration (Optional)

If you have existing data in Supabase that you want to migrate:

### 1. Export Data from Supabase
```bash
# Export each table to CSV
curl -H \"apikey: YOUR_SERVICE_KEY\" \
  -H \"Authorization: Bearer YOUR_SERVICE_KEY\" \
  \"https://your-project.supabase.co/rest/v1/archon_projects?select=*\" \
  -o archon_projects.csv
```

### 2. Import Data to PostgreSQL
```bash
# Import CSV files to your PostgreSQL database
cat archon_projects.csv | psql -h your-host -d your-database -c \"COPY archon_projects FROM STDIN WITH CSV HEADER;\"
```

### 3. Migrate Vector Data
Vector embeddings will be automatically regenerated when documents are reprocessed.

## 🧪 Testing the Migration

### 1. Basic Connection Test
```bash
cd python
uv run python -c "
from src.server.services.client_manager import get_database_client
from src.server.config.logfire_config import search_logger

client = get_database_client()
search_logger.info(f'Connected to database: {type(client).__name__}')

# Test basic query
result = client.table('archon_settings').select('key').limit(1).execute()
print('✅ Database connection and query successful!')
print(f'Found {result[\"count\"]} settings')
"
```

### 2. Full Application Test
```bash
# Start the application
cd python
uv run python -m src.server.main

# In another terminal, test API endpoints
curl http://localhost:8181/api/health
```

### 3. Feature Testing
Test all major features:
- [ ] Knowledge base crawling and search
- [ ] Project management (create, update, delete projects)
- [ ] Task management
- [ ] Settings management
- [ ] MCP server functionality

## 🔍 Troubleshooting

### Common Issues

#### 1. Connection Refused
```
Error: Connection refused
```
**Solution**:
- Check PostgreSQL is running: `sudo systemctl status postgresql`
- Verify network access and firewall rules
- Check connection string format

#### 2. Authentication Failed
```
Error: authentication failed for user "dbuser"
```
**Solution**:
- Verify username and password
- Check pg_hba.conf for authentication method
- Ensure user has proper privileges

#### 3. Extension Not Available
```
Error: extension "vector" is not available
```
**Solution**:
- Install pgvector: `CREATE EXTENSION vector;`
- May require superuser privileges
- Check PostgreSQL version compatibility

#### 4. SSL Connection Issues
```
Error: SSL connection required
```
**Solution**:
- Set `POSTGRES_SSL_MODE=require` for SSL connections
- Or configure SSL certificates properly

### Performance Optimization

#### Connection Pooling
The PostgreSQL client automatically uses connection pooling. Default settings:
- Min connections: 1
- Max connections: 20

#### Database Tuning
```sql
-- Optimize for vector operations
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET work_mem = '64MB';
ALTER SYSTEM SET maintenance_work_mem = '256MB';
SELECT pg_reload_conf();
```

## 🔒 Security Considerations

### 1. Network Security
- Use SSL/TLS connections in production
- Configure firewall rules to restrict access
- Use VPN or private networks when possible

### 2. Database Security
- Create dedicated application user with limited privileges
- Use strong passwords
- Enable connection logging
- Regular security updates

### 3. Connection Security
```bash
# Use SSL in production
POSTGRES_SSL_MODE=require
POSTGRES_SSL_CERT=/path/to/client-cert.pem
POSTGRES_SSL_KEY=/path/to/client-key.pem
POSTGRES_SSL_ROOT_CERT=/path/to/ca-cert.pem
```

## 📊 Performance Monitoring

### Database Health Check
The application includes database health monitoring:
```sql
-- Check database statistics
SELECT * FROM check_database_health();
```

### Connection Pool Monitoring
Connection pool statistics are logged automatically:
- Active connections
- Idle connections
- Connection errors

## 🔄 Rollback Procedure

If you need to revert to Supabase:

1. **Restore Environment Variables**
```bash
# Remove PostgreSQL variables
unset POSTGRES_URL POSTGRES_HOST POSTGRES_PORT POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD

# Restore Supabase variables
export SUPABASE_URL=your-supabase-url
export SUPABASE_SERVICE_KEY=your-service-key
```

2. **Restart Application**
```bash
docker compose down
docker compose up -d
```

## 📞 Support

For issues related to:
- **PostgreSQL Setup**: Check your database documentation
- **Application Issues**: Review application logs
- **Migration Problems**: Check this guide and PostgreSQL logs

## ✅ Migration Complete!

Once you've completed all steps:
1. ✅ PostgreSQL database configured and accessible
2. ✅ Schema applied successfully
3. ✅ Application connected to PostgreSQL
4. ✅ All features tested and working
5. ✅ Performance verified

Your Archon instance is now running on PostgreSQL with better performance and no usage limits! 🎉