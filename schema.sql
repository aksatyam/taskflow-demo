-- TaskFlow Database Schema
-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Profiles table (extends Supabase auth.users)
CREATE TABLE profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    email TEXT NOT NULL,
    display_name TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Projects table
CREATE TABLE projects (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    owner_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
    is_archived BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tasks table
CREATE TABLE tasks (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'todo' CHECK (status IN ('todo', 'in_progress', 'completed', 'cancelled')),
    priority TEXT DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
    assignee_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    due_date TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_by UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Comments table
CREATE TABLE comments (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    task_id UUID REFERENCES tasks(id) ON DELETE CASCADE NOT NULL,
    author_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Attachments table
CREATE TABLE attachments (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    task_id UUID REFERENCES tasks(id) ON DELETE CASCADE NOT NULL,
    filename TEXT NOT NULL,
    file_path TEXT NOT NULL,
    file_size BIGINT,
    mime_type TEXT,
    uploaded_by UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Activity table (audit trail)
CREATE TABLE activity (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    entity_type TEXT NOT NULL CHECK (entity_type IN ('project', 'task', 'comment', 'attachment')),
    entity_id UUID NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('created', 'updated', 'deleted', 'completed', 'assigned')),
    actor_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Project members junction table
CREATE TABLE project_members (
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member')),
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (project_id, user_id)
);

-- Row Level Security Policies

-- Enable RLS on all tables
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_members ENABLE ROW LEVEL SECURITY;

-- Profiles: Users can only see and modify their own profile
CREATE POLICY "Users can view own profile" ON profiles
    FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON profiles
    FOR UPDATE USING (auth.uid() = id);

-- Projects: Users can only access projects they're members of
CREATE POLICY "Project members can view projects" ON projects
    FOR SELECT USING (
        auth.uid() IN (
            SELECT user_id FROM project_members 
            WHERE project_members.project_id = projects.id
        )
    );

CREATE POLICY "Project owners can modify projects" ON projects
    FOR ALL USING (auth.uid() = owner_id);

-- Project members: Users can view memberships for projects they belong to
CREATE POLICY "Members can view project memberships" ON project_members
    FOR SELECT USING (
        auth.uid() = user_id OR 
        auth.uid() IN (
            SELECT user_id FROM project_members pm2 
            WHERE pm2.project_id = project_members.project_id
        )
    );

-- Tasks: Users can access tasks in projects they're members of
CREATE POLICY "Project members can view tasks" ON tasks
    FOR SELECT USING (
        auth.uid() IN (
            SELECT user_id FROM project_members 
            WHERE project_members.project_id = tasks.project_id
        )
    );

CREATE POLICY "Project members can modify tasks" ON tasks
    FOR ALL USING (
        auth.uid() IN (
            SELECT user_id FROM project_members 
            WHERE project_members.project_id = tasks.project_id
        )
    );

-- Comments: Users can access comments on tasks in their projects
CREATE POLICY "Project members can view comments" ON comments
    FOR SELECT USING (
        auth.uid() IN (
            SELECT user_id FROM project_members pm
            JOIN tasks t ON pm.project_id = t.project_id
            WHERE t.id = comments.task_id
        )
    );

CREATE POLICY "Project members can create comments" ON comments
    FOR INSERT WITH CHECK (
        auth.uid() IN (
            SELECT user_id FROM project_members pm
            JOIN tasks t ON pm.project_id = t.project_id
            WHERE t.id = comments.task_id
        )
    );

-- Attachments: Same as comments
CREATE POLICY "Project members can view attachments" ON attachments
    FOR SELECT USING (
        auth.uid() IN (
            SELECT user_id FROM project_members pm
            JOIN tasks t ON pm.project_id = t.project_id
            WHERE t.id = attachments.task_id
        )
    );

CREATE POLICY "Project members can upload attachments" ON attachments
    FOR INSERT WITH CHECK (
        auth.uid() IN (
            SELECT user_id FROM project_members pm
            JOIN tasks t ON pm.project_id = t.project_id
            WHERE t.id = attachments.task_id
        )
    );

-- Activity: Users can view activity for projects they're members of
CREATE POLICY "Project members can view activity" ON activity
    FOR SELECT USING (
        CASE 
            WHEN entity_type = 'project' THEN 
                auth.uid() IN (
                    SELECT user_id FROM project_members 
                    WHERE project_id = entity_id
                )
            WHEN entity_type IN ('task', 'comment', 'attachment') THEN
                auth.uid() IN (
                    SELECT user_id FROM project_members pm
                    JOIN tasks t ON pm.project_id = t.project_id
                    WHERE t.id = entity_id OR 
                          t.id = (SELECT task_id FROM comments WHERE id = entity_id) OR
                          t.id = (SELECT task_id FROM attachments WHERE id = entity_id)
                )
            ELSE FALSE
        END
    );

-- Performance Indexes

-- Projects
CREATE INDEX idx_projects_owner ON projects(owner_id);
CREATE INDEX idx_projects_created_at ON projects(created_at DESC);

-- Tasks
CREATE INDEX idx_tasks_project ON tasks(project_id);
CREATE INDEX idx_tasks_assignee ON tasks(assignee_id);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_priority ON tasks(priority);
CREATE INDEX idx_tasks_due_date ON tasks(due_date);
CREATE INDEX idx_tasks_created_at ON tasks(created_at DESC);
CREATE INDEX idx_tasks_project_status ON tasks(project_id, status);

-- Comments
CREATE INDEX idx_comments_task ON comments(task_id);
CREATE INDEX idx_comments_author ON comments(author_id);
CREATE INDEX idx_comments_created_at ON comments(created_at DESC);

-- Attachments
CREATE INDEX idx_attachments_task ON attachments(task_id);
CREATE INDEX idx_attachments_uploaded_by ON attachments(uploaded_by);

-- Activity
CREATE INDEX idx_activity_entity ON activity(entity_type, entity_id);
CREATE INDEX idx_activity_actor ON activity(actor_id);
CREATE INDEX idx_activity_created_at ON activity(created_at DESC);

-- Project members
CREATE INDEX idx_project_members_user ON project_members(user_id);

-- Update triggers for updated_at timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_projects_updated_at BEFORE UPDATE ON projects
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_tasks_updated_at BEFORE UPDATE ON tasks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_comments_updated_at BEFORE UPDATE ON comments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
