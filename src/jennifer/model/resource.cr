require "./scoping"
require "./translation"
require "./relation_definition"
require "../macros"

module Jennifer
  module Model
    # Base abstract class for a database entity.
    abstract class Resource
      module AbstractClassMethods
        abstract def build(values, new_record : Bool)
        abstract def build

        # Returns relation instance by given name.
        abstract def relation(name)

        # Returns table column counts grepped from the database.
        abstract def actual_table_field_count

        # Returns primary field name.
        abstract def primary_field_name

        # Returns `Jennifer::QueryBuilder::ModelQuery(T)`.
        #
        # This method is an entry point for writing query to your resource.
        #
        # ```
        # Address.all
        #   .where { _street.like("%St. Paul%") }
        #   .union(
        #     Profile.all
        #       .where { _login.in(["login1", "login2"]) }
        #       .select(:contact_id)
        #   )
        #   .select(:contact_id)
        #   .results
        # ```
        abstract def all

        # Returns superclass for the current class.
        #
        # ```
        # class A < Jennifer::Model::Base
        #   # ...
        # end
        #
        # class B < A
        # end
        #
        # B.superclass # => A
        # ```
        abstract def superclass

        # Returns criterion for the resource primary field.
        #
        # Is generated by `.mapping` macro.
        #
        # ```
        # User.primary.inspect # => #<Jennifer::QueryBuilder::Criteria:0x0 @field="id", @table="users">
        # ```
        abstract def primary

        # Returns field count.
        #
        # Is generated by `.mapping` macro.
        abstract def field_count

        # Returns array of field names
        #
        # Is generated by `.mapping` macro.
        abstract def field_names

        # Returns named tuple of column metadata
        #
        # Is generated by `.mapping` macro.
        abstract def columns_tuple

        # Accepts symbol hash or named tuple, stringifies it and calls constructor with string-based keys hash.
        #
        # It calls `after_initialize` callbacks.
        #
        # ```
        # User.new({ :name => "John Smith" })
        # User.new({ name: "John Smith" })
        # ```
        abstract def new(values : Hash(Symbol, ::Jennifer::DBAny) | NamedTuple)

        # Creates object based on given string hash.
        #
        # It calls `after_initialize` callbacks.
        #
        # ```
        # User.new({ "name" => "John Smith" })
        # ```
        abstract def new(values : Hash(String, ::Jennifer::DBAny))
      end

      extend AbstractClassMethods
      include Translation
      include Scoping
      include RelationDefinition
      include Macros

      # :nodoc:
      def self.superclass; end

      @@expression_builder : QueryBuilder::ExpressionBuilder?
      @@actual_table_field_count : Int32?
      @@has_table : Bool?
      @@table_name : String?

      # Returns a string containing a human-readable representation of object.
      #
      # ```
      # Address.new.inspect
      # # => "#<Address:0x7f532bdd5340 id: nil, street: "Ant st. 69", contact_id: nil, created_at: nil, updated_at: nil>"
      # ```
      def inspect(io) : Nil
        io << "#<" << {{@type.name.id.stringify}} << ":0x"
        object_id.to_s(16, io)
        inspect_attributes(io)
        io << '>'
        nil
      end

      private def inspect_attributes(io) : Nil
        nil
      end

      # Alias for `.new`.
      def self.build(values : Hash(Symbol, ::Jennifer::DBAny) | NamedTuple)
        new(values)
      end

      # ditto
      def self.build(values : Hash(String, ::Jennifer::DBAny))
        new(values)
      end

      # ditto
      def self.build(**values)
        new(values)
      end

      # Sets custom table name.
      def self.table_name(value : String | Symbol)
        @@table_name = value.to_s
        @@actual_table_field_count = nil
        @@has_table = nil
      end

      # Returns resource's table name.
      def self.table_name : String
        @@table_name ||=
          begin
            name = ""
            class_name = Inflector.demodulize(to_s)
            name = self.table_prefix if self.responds_to?(:table_prefix)
            Inflector.pluralize(name + class_name.underscore)
          end
      end

      # Returns adapter instance.
      def self.adapter
        Adapter.adapter
      end

      # Returns `QueryBuilder::ExpressionBuilder` object of this resource's table.
      #
      # ```
      # User.context.sql("ABS(1.2)")
      # ```
      def self.context
        @@expression_builder ||= QueryBuilder::ExpressionBuilder.new(table_name)
      end

      # Implementation of `AbstractClassMethods.all`.
      #
      # ```
      # User.all.where { _name == "John" }
      # ```
      def self.all
        {% begin %}
          QueryBuilder::ModelQuery({{@type}}).build(table_name)
        {% end %}
      end

      # Is a shortcut for `.all.where` call.
      #
      # ```
      # User.where { _name == "John" }
      # ```
      def self.where(&block)
        ac = all
        tree = with ac.expression_builder yield ac.expression_builder
        ac.set_tree(tree)
        ac
      end

      # Starts database transaction.
      #
      # For more details see `Jennifer::Adapter::Transactions`.
      #
      # ```
      # User.transaction do
      #   Post.create
      # end
      # ```
      def self.transaction
        adapter.transaction do |t|
          yield(t)
        end
      end

      # Returns criterion for column *name* of resource's table.
      #
      # ```
      # User.c(:email) # => users.email
      # ```
      def self.c(name : String | Symbol)
        context.c(name.to_s)
      end

      def self.c(name : String | Symbol, relation)
        QueryBuilder::Criteria.new(name.to_s, table_name, relation)
      end

      # Returns star field statement for current resource's table.
      #
      # ```
      # User.star # => users.*
      # ```
      def self.star
        context.star
      end

      def self.relation(name)
        raise UnknownRelation.new(self, name)
      end

      def append_relation(name : String, hash)
        raise Jennifer::UnknownRelation.new(self.class, name)
      end

      def set_inverse_of(name : String, object)
        raise Jennifer::UnknownRelation.new(self.class, name)
      end

      def get_relation(name : String)
        raise Jennifer::UnknownRelation.new(self.class, name)
      end

      # Returns value of attribute *name*.
      #
      # It method doesn't invoke getter. If no attribute with given name is found - `BaseException`
      # is raised. To prevent this and return `nil` instead - pass `false` for *raise_exception*.
      #
      # ```
      # contact.attribute(:name)          # => Jennifer::DBAny
      # contact.attribute("age")          # => Jennifer::DBAny
      # contact.attribute(:salary)        # => Jennifer::BaseException is raised
      # contact.attribute(:salary, false) # => nil
      # ```
      abstract def attribute(name, raise_exception : Bool = true)

      # Returns value of primary field
      #
      # Is generated by `.mapping` macro.
      abstract def primary

      # Returns hash with model attributes; keys are symbols.
      #
      # Is generated by `.mapping` macro.
      #
      # ```
      # contact.to_h # => { name: "Jennifer", age: 2 }
      # ```
      abstract def to_h

      # Returns hash with model attributes; keys are strings.
      #
      # Is generated by `.mapping` macro.
      #
      # ```
      # contact.to_h # => { "name" => "Jennifer", "age" => 2 }
      # ```
      abstract def to_str_h
    end
  end
end
