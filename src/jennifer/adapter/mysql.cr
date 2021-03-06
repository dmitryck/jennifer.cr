require "mysql"
require "./base"

require "./mysql/sql_generator"
require "./mysql/command_interface"
require "./mysql/schema_processor"

module Jennifer
  module Mysql
    class Adapter < Adapter::Base
      alias EnumType = String

      TYPE_TRANSLATIONS = {
        :bool => "bool",
        :enum => "enum",

        :bigint  => "bigint",   # Int64
        :integer => "int",      # Int32
        :short   => "SMALLINT", # Int16
        :tinyint => "TINYINT",  # Int8

        :float  => "float",  # Float32
        :double => "double", # Float64

        :decimal => "decimal", # Float64

        :string     => "varchar",
        :varchar    => "varchar",
        :text       => "text",
        :var_string => "varstring",

        :timestamp => "datetime", # "timestamp",
        :date_time => "datetime",

        :blob => "blob",
        :json => "json",
      }

      DEFAULT_SIZES = {
        :string => 254,
      }

      # NOTE: ATM is not used
      TABLE_LOCK_TYPES = {
        "r"       => "READ",
        "rl"      => "READ LOCAL",
        "w"       => "WRITE",
        "lpw"     => "LOW_PRIORITY WRITE",
        "default" => "READ", # "r"
      }

      def sql_generator
        SQLGenerator
      end

      def schema_processor
        @schema_processor ||= SchemaProcessor.new(self)
      end

      def translate_type(name : Symbol)
        TYPE_TRANSLATIONS[name]
      rescue e : KeyError
        raise BaseException.new("Unknown data alias #{name}")
      end

      def default_type_size(name)
        DEFAULT_SIZES[name]?
      end

      def table_column_count(table)
        if table_exists?(table)
          Query["information_schema.COLUMNS"].where do
            (_table_name == table) & (_table_schema == Config.db)
          end.count
        else
          -1
        end
      end

      def tables_column_count(tables)
        Query["information_schema.COLUMNS"]
          .where { _table_name.in(tables) & (_table_schema == Config.db) }
          .group(:table_name)
          .select { [_table_name.alias("table_name"), count.alias("count")] }
      end

      def table_exists?(table)
        Query["information_schema.TABLES"]
          .where { (_table_schema == Config.db) & (_table_name == table) }
          .exists?
      end

      def view_exists?(name)
        Query["information_schema.TABLES"]
          .where { (_table_schema == Config.db) & (_table_type == "VIEW") & (_table_name == name) }
          .exists?
      end

      def index_exists?(table, name : String)
        Query["information_schema.statistics"].where do
          (_table_name == table) &
            (_index_name == name) &
            (_table_schema == Config.db)
        end.exists?
      end

      def column_exists?(table, name)
        Query["information_schema.COLUMNS"].where do
          (_table_name == table) &
            (_column_name == name) &
            (_table_schema == Config.db)
        end.exists?
      end

      def foreign_key_exists?(from_table, to_table = nil, column = nil, name : String? = nil)
        name = self.class.foreign_key_name(from_table, to_table, column, name)
        Query["information_schema.KEY_COLUMN_USAGE"]
          .where { and(_constraint_name == name, _table_schema == Config.db) }
          .exists?
      end

      def with_table_lock(table : String, type : String = "default", &block)
        transaction do |t|
          Config.logger.debug("MySQL doesn't support manual locking table from prepared statement." \
                              " Instead of this only transaction was started.")
          yield t
        end
      end

      def explain(q)
        body = sql_generator.explain(q)
        args = q.sql_args
        plan = [] of Array(String)
        query(*parse_query(body, args)) do |rs|
          rs.each do
            row = %w()
            12.times do
              temp = rs.read
              row << (temp.nil? ? "NULL" : temp.to_s)
            end
            plan << row
          end
        end

        format_query_explain(plan)
      end

      def self.command_interface
        @@command_interface ||= CommandInterface.new(Config.instance)
      end

      def self.create_database
        db_connection do |db|
          db.exec "CREATE DATABASE #{Config.db}"
        end
      end

      def self.drop_database
        db_connection do |db|
          db.exec "DROP DATABASE #{Config.db}"
        end
      end

      def self.database_exists? : Bool
        db_connection do |db|
          db.scalar <<-SQL,
            SELECT EXISTS(
              SELECT 1
              FROM INFORMATION_SCHEMA.SCHEMATA
              WHERE SCHEMA_NAME = ?
            )
          SQL
          Config.db
        end == 1
      end

      private def format_query_explain(plan : Array)
        headers = %w(id select_type table partitions type possible_keys key key_len ref rows filtered Extra)
        column_sizes = headers.map(&.size)
        plan.each do |row|
          row.each_with_index do |cell, column_i|
            cell_size = cell.size
            column_sizes[column_i] = cell_size if cell_size > column_sizes[column_i]
          end
        end

        String.build do |io|
          format_table_row(io, headers, column_sizes)

          io << "\n"
          io << column_sizes.map { |size| "-" * size }.join(" | ")
          io << "\n"

          plan.each_with_index do |row, row_i|
            io << "\n" if row_i != 0
            format_table_row(io, row, column_sizes)
          end
        end
      end

      private def format_table_row(io, row, column_sizes)
        row.each_with_index do |cell, i|
          io << " | " if i != 0
          io << cell.ljust(column_sizes[i])
        end
      end
    end
  end
end

require "./mysql/result_set"
require "./mysql/type"

::Jennifer::Adapter.register_adapter("mysql", ::Jennifer::Mysql::Adapter)
