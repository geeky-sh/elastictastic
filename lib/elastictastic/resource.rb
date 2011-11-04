module Elastictastic
  module Resource
    extend ActiveSupport::Concern

    included do
      include Dirty
    end

    module ClassMethods
      def each_field
        properties.each_pair do |field, properties|
          if properties['properties']
            embeds[field].clazz.each_field do |embed_field, embed_properties|
              yield("#{field}.#{embed_field}", embed_properties)
            end
          elsif properties['fields']
            properties['fields'].each_pair do |variant_field, variant_properties|
              if variant_field == field
                yield(field, variant_properties)
              else
                yield("#{field}.#{variant_field}", variant_properties)
              end
            end
          else
            yield field, properties
          end
        end
      end

      def select_fields
        [].tap do |fields|
          each_field do |field, properties|
            fields << [field, properties] if yield(field, properties)
          end
        end
      end

      def all_fields
        @all_fields ||= {}.tap do |fields|
          each_field { |field, properties| fields[field] = properties }
        end
      end

      def field_properties
        @field_properties ||= {}
      end

      def properties
        return @properties if defined? @properties
        @properties = {}
        @properties.merge!(field_properties)
        embeds.each_pair do |name, embed|
          @properties[name] = { 'properties' => embed.clazz.properties }
        end
        @properties
      end

      def properties_for_field(field_name)
        properties[field_name.to_s]
      end

      def embeds
        @embeds ||= {}
      end

      def field(*field_names, &block)
        options = field_names.extract_options!
        field_names.each do |field_name|
          define_field(field_name, options, &block)
        end
      end

      def define_field(field_name, options, &block)
        field_name = field_name.to_s

        module_eval(<<-RUBY, __FILE__, __LINE__ + 1)
          def #{field_name}
            read_attribute(#{field_name.inspect})
          end

          def #{field_name}=(value)
            write_attribute(#{field_name.inspect}, value)
          end
        RUBY

        field_properties[field_name.to_s] =
          Field.process(field_name, options, &block)
      end

      def embed(*embed_names)
        options = embed_names.extract_options!

        embed_names.each do |embed_name|
          embed_name = embed_name.to_s
          embed = Association.new(embed_name, options)

          module_eval <<-RUBY, __FILE__, __LINE__ + 1
            def #{embed_name}
              read_embed(#{embed_name.inspect})
            end

            def #{embed_name}=(value)
              Util.call_or_each(value) do |check_value|
                unless check_value.nil? || check_value.is_a?(#{embed.class_name})
                  raise TypeError, "Expected instance of class #{embed.class_name}; got \#{check_value.inspect}"
                end
              end
              write_embed(#{embed_name.inspect}, value)
            end
          RUBY

          embeds[embed_name] = embed
        end
      end
    end

    module InstanceMethods
      def initialize
        @attributes = {}
        @embeds = {}
      end

      def attributes
        @attributes.with_indifferent_access
      end

      def elasticsearch_doc
        {}.tap do |doc|
          @attributes.each_pair do |field, value|
            next if value.nil?
            doc[field] = Util.call_or_map(value) do |item|
              serialize_value(field, item)
            end
          end
          @embeds.each_pair do |field, embedded|
            next if embedded.nil?
            doc[field] = Util.call_or_map(embedded) do |item|
              item.elasticsearch_doc
            end
          end
        end
      end

      def valid? #XXX temporary for RABL compatibility
        true
      end

      def ==(other)
        elasticsearch_doc == other.elasticsearch_doc
      end

      protected

      def read_attribute(field)
        @attributes[field.to_s]
      end

      def write_attribute(field, value)
        if value.nil?
          @attributes.delete(field.to_s)
        else
          @attributes[field.to_s] = value
        end
      end

      def read_embed(field)
        @embeds[field.to_s]
      end

      def write_embed(field, value)
        @embeds[field.to_s] = value
      end

      protected

      def elasticsearch_doc=(doc)
        return if doc.nil?
        doc.each_pair do |field_name, value|
          if self.class.properties.has_key?(field_name)
            embed = self.class.embeds[field_name]
            deserialized = Util.call_or_map(value) do |item|
              if embed
                embed.clazz.new.tap { |embed| embed.elasticsearch_doc = item }
              else
                deserialize_value(field_name, item)
              end
            end
            if embed then write_embed(field_name, deserialized)
            else write_attribute(field_name, deserialized)
            end
          end
        end
      end

      private

      def serialize_value(field_name, value)
        type = self.class.properties_for_field(field_name)['type'].to_s
        case type
        when 'date'
          time = value.to_time
          time.to_i * 1000 + time.usec / 1000
        when 'integer', 'byte', 'short', 'long'
          value.to_i
        when 'float', 'double'
          value.to_f
        when 'boolean'
          !!value
        else
          value
        end
      end

      def deserialize_value(field_name, value)
        return nil if value.nil?
        if self.class.properties_for_field(field_name)['type'].to_s == 'date'
          if value.is_a? Fixnum
            sec, usec = value / 1000, (value % 1000) * 1000
            Time.at(sec, usec).utc
          else
            Time.parse(value)
          end
        else
          value
        end
      end
    end
  end
end
