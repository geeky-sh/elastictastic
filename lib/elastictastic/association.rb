module Elastictastic
  #
  # Container for information about generic Elastictastic associations --
  # this might be an embed association or a parent/child association.
  #
  # @api private
  #
  class Association
    attr_reader :name, :options

    def initialize(name, options = {})
      @name, @options = name.to_s, options.symbolize_keys
    end

    def class_name
      @options[:class_name] || @name.to_s.classify
    end

    def clazz
      @clazz ||= class_name.constantize
    end

    def extract(instance)
      instance.__send__(name)
    end

    ## used only for embedded/nested documents
    def type
      @options[:type]
    end

    ## used only for embedded documents
    def include_in_root
      @options[:include_in_root]
    end
  end
end
