#
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# NOTE:
#
# Uses the value of node['private_chef']['postgresql']['db_connection_superuser'] and ['db_superuser_password]
# to make the connection to the postgres server.

action :create do
  EcPostgres.with_connection(node, new_resource.database) do |connection|
    run_sql(connection, "GRANT #{database_access} ON DATABASE #{new_resource.database} TO #{new_resource.username}")
    run_sql(connection, "ALTER DEFAULT PRIVILEGES IN SCHEMA #{new_resource.schema} GRANT #{functions_access} ON FUNCTIONS TO #{new_resource.username};")
    run_sql(connection, "GRANT #{functions_access} ON ALL FUNCTIONS IN SCHEMA #{new_resource.schema} TO #{new_resource.username}")
    run_sql(connection, "ALTER DEFAULT PRIVILEGES IN SCHEMA #{new_resource.schema} GRANT #{sequences_access} ON SEQUENCES TO #{new_resource.username};")
    run_sql(connection, "GRANT #{sequences_access} ON ALL SEQUENCES IN SCHEMA #{new_resource.schema} TO #{new_resource.username}")
    run_sql(connection, "ALTER DEFAULT PRIVILEGES IN SCHEMA #{new_resource.schema} GRANT #{tables_access} ON TABLES TO #{new_resource.username};")
    run_sql(connection, "GRANT #{tables_access} ON ALL TABLES IN SCHEMA #{new_resource.schema} TO #{new_resource.username}")
  end
end

def database_access
  case new_resource.access_profile
  when :write
    'CONNECT, TEMPORARY'
  when :read
    'CONNECT'
  else
    raise "access profile #{new_resource.access_profile} not found"
  end
end

def tables_access
  case new_resource.access_profile
  when :write
    'INSERT, SELECT, UPDATE, DELETE'
  when :read
    'SELECT'
  else
    raise "access profile #{new_resource.access_profile} not found"
  end
end

def sequences_access
  case new_resource.access_profile
  when :write
    'SELECT, UPDATE'
  when :read
    'SELECT'
  else
    raise "access profile #{new_resource.access_profile} not found"
  end
end

def functions_access
  case new_resource.access_profile
  when :write
    'EXECUTE'
  when :read
    'EXECUTE'
  else
    raise "access profile #{new_resource.access_profile} not found"
  end
end

def run_sql(connection, sql, *params)
  converge_by sql do
    connection.exec(sql, *params)
  end
end
