-- =====================================================
-- Archon PostgreSQL Database Setup
-- =====================================================
-- This script creates the complete Archon database schema
-- for direct PostgreSQL connections (no Supabase required)
--
-- Run this script in your PostgreSQL database to set up
-- the complete Archon database schema and initial data
-- =====================================================

-- =====================================================
-- SECTION 1: EXTENSIONS
-- =====================================================

-- Enable required PostgreSQL extensions
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- =====================================================
-- SECTION 2: KNOWLEDGE BASE TABLES
-- =====================================================

-- Knowledge sources (websites, documents, etc.)
CREATE TABLE IF NOT EXISTS archon_sources (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    url TEXT NOT NULL,
    title TEXT,
    description TEXT,
    content_type VARCHAR(50), -- 'website', 'document', 'pdf', etc.
    crawl_status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'crawling', 'completed', 'failed'
    crawl_config JSONB, -- Configuration for crawling this source
    metadata JSONB, -- Additional metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_crawled_at TIMESTAMP WITH TIME ZONE
);

-- Create indexes for sources
CREATE INDEX IF NOT EXISTS idx_archon_sources_url ON archon_sources(url);
CREATE INDEX IF NOT EXISTS idx_archon_sources_status ON archon_sources(crawl_status);
CREATE INDEX IF NOT EXISTS idx_archon_sources_created ON archon_sources(created_at);
CREATE INDEX IF NOT EXISTS idx_archon_sources_type ON archon_sources(content_type);
CREATE INDEX IF NOT EXISTS idx_archon_sources_metadata ON archon_sources USING GIN(metadata);

-- Crawled pages with vector embeddings
CREATE TABLE IF NOT EXISTS archon_crawled_pages (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    source_id UUID REFERENCES archon_sources(id) ON DELETE CASCADE,
    url TEXT NOT NULL,
    title TEXT,
    content TEXT NOT NULL,
    content_type VARCHAR(50),
    metadata JSONB,
    -- Multiple embedding dimensions for different models
    embedding_384 vector(384),
    embedding_768 vector(768),
    embedding_1024 vector(1024),
    embedding_1536 vector(1536),
    embedding_3072 vector(3072),
    -- Generated columns for full-text search
    content_tsv tsvector GENERATED ALWAYS SET (to_tsvector('english'::regconfig, content)) STORED,
    title_tsv tsvector GENERATED ALWAYS SET (to_tsvector('english'::regconfig, COALESCE(title, ''))) STORED,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for crawled pages
CREATE INDEX IF NOT EXISTS idx_archon_crawled_pages_source ON archon_crawled_pages(source_id);
CREATE INDEX IF NOT EXISTS idx_archon_crawled_pages_url ON archon_crawled_pages(url);
CREATE INDEX IF NOT EXISTS idx_archon_crawled_pages_created ON archon_crawled_pages(created_at);
CREATE INDEX IF NOT EXISTS idx_archon_crawled_pages_content_tsv ON archon_crawled_pages USING GIN(content_tsv);
CREATE INDEX IF NOT EXISTS idx_archon_crawled_pages_title_tsv ON archon_crawled_pages USING GIN(title_tsv);

-- Vector indexes for different embedding dimensions
CREATE INDEX IF NOT EXISTS idx_archon_crawled_pages_embedding_384 ON archon_crawled_pages
    USING ivfflat (embedding_384 vector_cosine_ops) WITH (lists = 100);
CREATE INDEX IF NOT EXISTS idx_archon_crawled_pages_embedding_768 ON archon_crawled_pages
    USING ivfflat (embedding_768 vector_cosine_ops) WITH (lists = 100);
CREATE INDEX IF NOT EXISTS idx_archon_crawled_pages_embedding_1024 ON archon_crawled_pages
    USING ivfflat (embedding_1024 vector_cosine_ops) WITH (lists = 100);
CREATE INDEX IF NOT EXISTS idx_archon_crawled_pages_embedding_1536 ON archon_crawled_pages
    USING ivfflat (embedding_1536 vector_cosine_ops) WITH (lists = 100);
CREATE INDEX IF NOT EXISTS idx_archon_crawled_pages_embedding_3072 ON archon_crawled_pages
    USING ivfflat (embedding_3072 vector_cosine_ops) WITH (lists = 100);

-- Code examples table
CREATE TABLE IF NOT EXISTS archon_code_examples (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    source_id UUID REFERENCES archon_sources(id) ON DELETE CASCADE,
    page_id UUID REFERENCES archon_crawled_pages(id) ON DELETE CASCADE,
    code_content TEXT NOT NULL,
    language VARCHAR(50),
    summary TEXT,
    relevance_score FLOAT,
    embedding_1536 vector(1536),
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for code examples
CREATE INDEX IF NOT EXISTS idx_archon_code_examples_source ON archon_code_examples(source_id);
CREATE INDEX IF NOT EXISTS idx_archon_code_examples_page ON archon_code_examples(page_id);
CREATE INDEX IF NOT EXISTS idx_archon_code_examples_language ON archon_code_examples(language);
CREATE INDEX IF NOT EXISTS idx_archon_code_examples_relevance ON archon_code_examples(relevance_score);
CREATE INDEX IF NOT EXISTS idx_archon_code_examples_embedding_1536 ON archon_code_examples
    USING ivfflat (embedding_1536 vector_cosine_ops) WITH (lists = 100);

-- Page metadata for agent retrieval
CREATE TABLE IF NOT EXISTS archon_page_metadata (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    source_id UUID REFERENCES archon_sources(id) ON DELETE CASCADE,
    page_id UUID REFERENCES archon_crawled_pages(id) ON DELETE CASCADE,
    full_content TEXT NOT NULL,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for page metadata
CREATE INDEX IF NOT EXISTS idx_archon_page_metadata_source ON archon_page_metadata(source_id);
CREATE INDEX IF NOT EXISTS idx_archon_page_metadata_page ON archon_page_metadata(page_id);

-- =====================================================
-- SECTION 3: PROJECT MANAGEMENT TABLES
-- =====================================================

-- Projects table
CREATE TABLE IF NOT EXISTS archon_projects (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    features JSONB DEFAULT '[]'::jsonb, -- Array of feature strings
    docs JSONB DEFAULT '[]'::jsonb, -- Array of documentation items
    data JSONB DEFAULT '{}'::jsonb, -- Additional project data
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for projects
CREATE INDEX IF NOT EXISTS idx_archon_projects_name ON archon_projects(name);
CREATE INDEX IF NOT EXISTS idx_archon_projects_created ON archon_projects(created_at);
CREATE INDEX IF NOT EXISTS idx_archon_projects_metadata ON archon_projects USING GIN(metadata);
CREATE INDEX IF NOT EXISTS idx_archon_projects_features ON archon_projects USING GIN(features);

-- Tasks table
CREATE TABLE IF NOT EXISTS archon_tasks (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    project_id UUID REFERENCES archon_projects(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(20) DEFAULT 'todo' CHECK (status IN ('todo', 'doing', 'review', 'done')),
    assignee VARCHAR(50), -- 'User', 'Archon', 'AI IDE Agent'
    priority VARCHAR(20) DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high')),
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for tasks
CREATE INDEX IF NOT EXISTS idx_archon_tasks_project ON archon_tasks(project_id);
CREATE INDEX IF NOT EXISTS idx_archon_tasks_status ON archon_tasks(status);
CREATE INDEX IF NOT EXISTS idx_archon_tasks_assignee ON archon_tasks(assignee);
CREATE INDEX IF NOT EXISTS idx_archon_tasks_created ON archon_tasks(created_at);
CREATE INDEX IF NOT EXISTS idx_archon_tasks_metadata ON archon_tasks USING GIN(metadata);

-- Project sources junction table (many-to-many)
CREATE TABLE IF NOT EXISTS archon_project_sources (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    project_id UUID REFERENCES archon_projects(id) ON DELETE CASCADE,
    source_id UUID REFERENCES archon_sources(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(project_id, source_id)
);

-- Create indexes for project sources
CREATE INDEX IF NOT EXISTS idx_archon_project_sources_project ON archon_project_sources(project_id);
CREATE INDEX IF NOT EXISTS idx_archon_project_sources_source ON archon_project_sources(source_id);
CREATE INDEX IF NOT EXISTS idx_archon_project_sources_created ON archon_project_sources(created_at);

-- Document versions table
CREATE TABLE IF NOT EXISTS archon_document_versions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    project_id UUID REFERENCES archon_projects(id) ON DELETE CASCADE,
    version_number INTEGER NOT NULL,
    docs JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by VARCHAR(100)
);

-- Create indexes for document versions
CREATE INDEX IF NOT EXISTS idx_archon_document_versions_project ON archon_document_versions(project_id);
CREATE INDEX IF NOT EXISTS idx_archon_document_versions_created ON archon_document_versions(created_at);
CREATE INDEX IF NOT EXISTS idx_archon_document_versions_number ON archon_document_versions(project_id, version_number);

-- =====================================================
-- SECTION 4: CREDENTIALS AND SETTINGS
-- =====================================================

-- Credentials and Configuration Management Table
CREATE TABLE IF NOT EXISTS archon_settings (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    key VARCHAR(255) UNIQUE NOT NULL,
    value TEXT, -- For plain text config values
    encrypted_value TEXT, -- For encrypted sensitive data (bcrypt hashed)
    is_encrypted BOOLEAN DEFAULT FALSE,
    category VARCHAR(100), -- Group related settings (e.g., 'rag_strategy', 'api_keys', 'server_config')
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for settings
CREATE INDEX IF NOT EXISTS idx_archon_settings_key ON archon_settings(key);
CREATE INDEX IF NOT EXISTS idx_archon_settings_category ON archon_settings(category);

-- =====================================================
-- SECTION 5: AGENT WORK ORDERS TABLES
-- =====================================================

-- Agent work orders table
CREATE TABLE IF NOT EXISTS archon_agent_work_orders (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'failed', 'cancelled')),
    prompt TEXT NOT NULL,
    context JSONB,
    result JSONB,
    error_message TEXT,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE
);

-- Create indexes for agent work orders
CREATE INDEX IF NOT EXISTS idx_archon_agent_work_orders_status ON archon_agent_work_orders(status);
CREATE INDEX IF NOT EXISTS idx_archon_agent_work_orders_created ON archon_agent_work_orders(created_at);
CREATE INDEX IF NOT EXISTS idx_archon_agent_work_orders_updated ON archon_agent_work_orders(updated_at);
CREATE INDEX IF NOT EXISTS idx_archon_agent_work_orders_metadata ON archon_agent_work_orders USING GIN(metadata);

-- Agent work order steps table
CREATE TABLE IF NOT EXISTS archon_agent_work_order_steps (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    work_order_id UUID REFERENCES archon_agent_work_orders(id) ON DELETE CASCADE,
    step_number INTEGER NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'failed')),
    command TEXT,
    output TEXT,
    error_output TEXT,
    exit_code INTEGER,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for agent work order steps
CREATE INDEX IF NOT EXISTS idx_archon_agent_work_order_steps_work_order ON archon_agent_work_order_steps(work_order_id);
CREATE INDEX IF NOT EXISTS idx_archon_agent_work_order_steps_status ON archon_agent_work_order_steps(status);
CREATE INDEX IF NOT EXISTS idx_archon_agent_work_order_steps_step_number ON archon_agent_work_order_steps(work_order_id, step_number);

-- =====================================================
-- SECTION 6: MIGRATION TRACKING
-- =====================================================

-- Migration tracking table
CREATE TABLE IF NOT EXISTS archon_migrations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    version VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    applied_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create index for migrations
CREATE INDEX IF NOT EXISTS idx_archon_migrations_version ON archon_migrations(version);
CREATE INDEX IF NOT EXISTS idx_archon_migrations_applied ON archon_migrations(applied_at);

-- =====================================================
-- SECTION 7: PROMPTS TABLE
-- =====================================================

-- AI Agent prompts table
CREATE TABLE IF NOT EXISTS archon_prompts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL,
    content TEXT NOT NULL,
    prompt_type VARCHAR(50) DEFAULT 'system', -- 'system', 'user', 'assistant'
    version INTEGER DEFAULT 1,
    is_active BOOLEAN DEFAULT TRUE,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for prompts
CREATE INDEX IF NOT EXISTS idx_archon_prompts_name ON archon_prompts(name);
CREATE INDEX IF NOT EXISTS idx_archon_prompts_type ON archon_prompts(prompt_type);
CREATE INDEX IF NOT EXISTS idx_archon_prompts_active ON archon_prompts(is_active);
CREATE INDEX IF NOT EXISTS idx_archon_prompts_metadata ON archon_prompts USING GIN(metadata);

-- =====================================================
-- SECTION 8: UPDATE TRIGGERS
-- =====================================================

-- Create function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for all tables with updated_at columns
CREATE TRIGGER update_archon_sources_updated_at
    BEFORE UPDATE ON archon_sources
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_archon_crawled_pages_updated_at
    BEFORE UPDATE ON archon_crawled_pages
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_archon_code_examples_updated_at
    BEFORE UPDATE ON archon_code_examples
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_archon_page_metadata_updated_at
    BEFORE UPDATE ON archon_page_metadata
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_archon_projects_updated_at
    BEFORE UPDATE ON archon_projects
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_archon_tasks_updated_at
    BEFORE UPDATE ON archon_tasks
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_archon_settings_updated_at
    BEFORE UPDATE ON archon_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_archon_agent_work_orders_updated_at
    BEFORE UPDATE ON archon_agent_work_orders
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_archon_agent_work_order_steps_updated_at
    BEFORE UPDATE ON archon_agent_work_order_steps
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_archon_prompts_updated_at
    BEFORE UPDATE ON archon_prompts
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- SECTION 9: SEARCH FUNCTIONS
-- =====================================================

-- Function to detect embedding dimension from query embedding
CREATE OR REPLACE FUNCTION detect_embedding_dimension(query_embedding vector)
RETURNS INTEGER AS $$
BEGIN
    RETURN COALESCE(
        CASE
            WHEN pg_column_size(query_embedding) = 1540 THEN 384  -- 384D vector + header
            WHEN pg_column_size(query_embedding) = 3084 THEN 768  -- 768D vector + header
            WHEN pg_column_size(query_embedding) = 4116 THEN 1024 -- 1024D vector + header
            WHEN pg_column_size(query_embedding) = 6164 THEN 1536 -- 1536D vector + header
            WHEN pg_column_size(query_embedding) = 12308 THEN 3072 -- 3072D vector + header
        END,
        1536  -- Default to 1536D
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Multi-dimensional vector search function
CREATE OR REPLACE FUNCTION match_archon_crawled_pages_multi(
    query_embedding vector,
    embedding_dimension INTEGER DEFAULT 1536,
    match_count INTEGER DEFAULT 10,
    filter_source_ids UUID[] DEFAULT NULL
)
RETURNS TABLE(
    id UUID,
    source_id UUID,
    url TEXT,
    title TEXT,
    content TEXT,
    metadata JSONB,
    similarity FLOAT
) AS $$
BEGIN
    -- Validate embedding dimension
    IF embedding_dimension NOT IN (384, 768, 1024, 1536, 3072) THEN
        RAISE EXCEPTION 'Invalid embedding dimension. Must be one of: 384, 768, 1024, 1536, 3072';
    END IF;

    RETURN QUERY
    EXECUTE format($f$
        SELECT
            id,
            source_id,
            url,
            title,
            content,
            metadata,
            1 - (embedding_%s <=> $1) AS similarity
        FROM archon_crawled_pages
        WHERE
            embedding_%s IS NOT NULL
            AND ($3 IS NULL OR source_id = ANY($3))
        ORDER BY embedding_%s <=> $1
        LIMIT $2
    $f$, embedding_dimension, embedding_dimension, embedding_dimension)
    USING query_embedding, match_count, filter_source_ids;
END;
$$ LANGUAGE plpgsql;

-- Hybrid search combining vector similarity and full-text search
CREATE OR REPLACE FUNCTION hybrid_search_archon_crawled_pages_multi(
    query_embedding vector,
    query_text TEXT,
    embedding_dimension INTEGER DEFAULT 1536,
    match_count INTEGER DEFAULT 10,
    filter_source_ids UUID[] DEFAULT NULL,
    full_text_weight FLOAT DEFAULT 0.3,
    semantic_weight FLOAT DEFAULT 0.7
)
RETURNS TABLE(
    id UUID,
    source_id UUID,
    url TEXT,
    title TEXT,
    content TEXT,
    metadata JSONB,
    similarity FLOAT,
    rank_score FLOAT
) AS $$
BEGIN
    RETURN QUERY
    WITH vector_results AS (
        SELECT
            id,
            source_id,
            url,
            title,
            content,
            metadata,
            similarity
        FROM match_archon_crawled_pages_multi(
            query_embedding,
            embedding_dimension,
            match_count * 2, -- Get more results for hybrid ranking
            filter_source_ids
        )
    ),
    text_results AS (
        SELECT
            id,
            source_id,
            url,
            title,
            content,
            metadata,
            -- Calculate text similarity using ts_rank_cd
            ts_rank_cd(
                setweight(content_tsv, 'A') || setweight(title_tsv, 'B'),
                plainto_tsquery('english', query_text)
            ) AS text_score
        FROM archon_crawled_pages
        WHERE
            ($4 IS NULL OR source_id = ANY($4))
            AND (content_tsv @@ plainto_tsquery('english', query_text)
                 OR title_tsv @@ plainto_tsquery('english', query_text))
    )
    SELECT
        v.id,
        v.source_id,
        v.url,
        v.title,
        v.content,
        v.metadata,
        v.similarity,
        -- Combine vector similarity and text relevance
        (v.similarity * semantic_weight) + (COALESCE(t.text_score, 0) * full_text_weight) AS rank_score
    FROM vector_results v
    LEFT JOIN text_results t ON v.id = t.id
    ORDER BY rank_score DESC
    LIMIT match_count;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- SECTION 10: INITIAL DATA
-- =====================================================

-- Server Configuration
INSERT INTO archon_settings (key, value, is_encrypted, category, description) VALUES
('MCP_TRANSPORT', 'dual', false, 'server_config', 'MCP server transport mode - sse (web clients), stdio (IDE clients), or dual (both)'),
('HOST', 'localhost', false, 'server_config', 'Host to bind to if using sse as the transport (leave empty if using stdio)'),
('PORT', '8051', false, 'server_config', 'Port to listen on if using sse as the transport (leave empty if using stdio)'),
('MODEL_CHOICE', 'gpt-4.1-nano', false, 'rag_strategy', 'The LLM you want to use for summaries and contextual embeddings. Generally this is a very cheap and fast LLM like gpt-4.1-nano')
ON CONFLICT (key) DO NOTHING;

-- RAG Strategy Configuration (all default to true)
INSERT INTO archon_settings (key, value, is_encrypted, category, description) VALUES
('USE_CONTEXTUAL_EMBEDDINGS', 'false', false, 'rag_strategy', 'Enhances embeddings with contextual information for better retrieval'),
('CONTEXTUAL_EMBEDDINGS_MAX_WORKERS', '3', false, 'rag_strategy', 'Maximum parallel workers for contextual embedding generation (1-10)'),
('USE_HYBRID_SEARCH', 'true', false, 'rag_strategy', 'Combines vector similarity search with keyword search for better results'),
('USE_AGENTIC_RAG', 'true', false, 'rag_strategy', 'Enables code example extraction, storage, and specialized code search functionality'),
('USE_RERANKING', 'true', false, 'rag_strategy', 'Applies cross-encoder reranking to improve search result relevance')
ON CONFLICT (key) DO NOTHING;

-- Monitoring Configuration
INSERT INTO archon_settings (key, value, is_encrypted, category, description) VALUES
('LOGFIRE_ENABLED', 'true', false, 'monitoring', 'Enable or disable Pydantic Logfire logging and observability platform'),
('PROJECTS_ENABLED', 'true', false, 'features', 'Enable or disable Projects and Tasks functionality')
ON CONFLICT (key) DO NOTHING;

-- Placeholder for sensitive credentials (to be added via Settings UI)
INSERT INTO archon_settings (key, encrypted_value, is_encrypted, category, description) VALUES
('OPENAI_API_KEY', NULL, true, 'api_keys', 'OpenAI API Key for embedding model (text-embedding-3-small). Get from: https://help.openai.com/en/articles/4936850-where-do-i-find-my-openai-api-key')
ON CONFLICT (key) DO NOTHING;

-- LLM Provider configuration settings
INSERT INTO archon_settings (key, value, is_encrypted, category, description) VALUES
('LLM_PROVIDER', 'openai', false, 'rag_strategy', 'LLM provider to use: openai, ollama, or google'),
('LLM_BASE_URL', NULL, false, 'rag_strategy', 'Custom base URL for LLM provider (mainly for Ollama, e.g., http://host.docker.internal:11434/v1)'),
('EMBEDDING_MODEL', 'text-embedding-3-small', false, 'rag_strategy', 'Embedding model for vector search and similarity matching (required for all embedding operations)')
ON CONFLICT (key) DO NOTHING;

-- =====================================================
-- SECTION 11: MONITORING FUNCTIONS
-- =====================================================

-- Database health check function
CREATE OR REPLACE FUNCTION check_database_health()
RETURNS TABLE(
    table_name TEXT,
    row_count BIGINT,
    last_updated TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        'archon_sources'::TEXT,
        COUNT(*),
        MAX(updated_at)
    FROM archon_sources
    UNION ALL
    SELECT
        'archon_crawled_pages'::TEXT,
        COUNT(*),
        MAX(updated_at)
    FROM archon_crawled_pages
    UNION ALL
    SELECT
        'archon_projects'::TEXT,
        COUNT(*),
        MAX(updated_at)
    FROM archon_projects
    UNION ALL
    SELECT
        'archon_tasks'::TEXT,
        COUNT(*),
        MAX(updated_at)
    FROM archon_tasks
    UNION ALL
    SELECT
        'archon_settings'::TEXT,
        COUNT(*),
        MAX(updated_at)
    FROM archon_settings;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- SECTION 12: PERFORMANCE OPTIMIZATIONS
-- =====================================================

-- Analyze all tables to update statistics
ANALYZE archon_sources;
ANALYZE archon_crawled_pages;
ANALYZE archon_code_examples;
ANALYZE archon_page_metadata;
ANALYZE archon_projects;
ANALYZE archon_tasks;
ANALYZE archon_settings;
ANALYZE archon_agent_work_orders;
ANALYZE archon_agent_work_order_steps;
ANALYZE archon_prompts;

-- Set optimal PostgreSQL settings for vector operations
-- (These may require superuser privileges)
-- ALTER SYSTEM SET shared_buffers = '256MB';
-- ALTER SYSTEM SET work_mem = '64MB';
-- ALTER SYSTEM SET maintenance_work_mem = '256MB';
-- SELECT pg_reload_conf();

-- =====================================================
-- COMPLETION MESSAGE
-- =====================================================

SELECT 'Archon PostgreSQL database setup completed successfully!' AS setup_status;