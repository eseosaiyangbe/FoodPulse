-- Create a dedicated replication user for streaming replication
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replicatorpass';