# encoding: utf-8
module Mail
  
  # Represents a folder object.
  # 
  class Folder
    include Patterns
    include Utilities

    # Creates a new mailbox object.
    #
    def initialize(name = nil, options={})
      @name = name
      @delim ||= options[:delim] || '/'
      @flags ||= options[:flags] || []
      @messages ||= options[:messages]
      @unseen ||= options[:unseen]
      @validity ||= options[:validity]
      @next ||= options[:next]
    end

    attr_reader :messages, :unseen, :validity, :next

    def name
      encoded
    end

    def delim
      @delim
    end

    def flags
      @flags
    end

    def encoded
      buffer = ''
      buffer.force_encoding('us-ascii') if buffer.respond_to?(:force_encoding)
      buffer << @name
      buffer
    end

    def to_s
      encoded
    end

    def decoded
      do_decode
    end

    def default
      decoded
    end

    private

    def do_decode
      @name.blank? ? nil : Encodings.decode_encode(@name, :decode)
    end

  end
end
