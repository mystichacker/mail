# encoding: utf-8
module Mail
  
  # Represents a message entry containing minimum information to uniquely identify
  # the corresponding message.
  # 
  class Entry
    include Patterns
    include Utilities

    # Creates a new message entry object.
    #
    def initialize(options={})
      @folder = options[:folder]
      @validity = options[:validity]
      @uid = options[:uid]
      @flags = options[:flags]
      @message_size = options[:message_size]
      @message_date = options[:message_date]
      @message_id = options[:message_id]
    end

    attr_reader :folder, :validity, :uid, :flags, :message_size, :message_date, :message_id

    def to_s
      "#{folder}.#{validity}.#{uid}: #{sha}"
    end

    # Returns a message sha that can be used to identify a message
    #
    def sha
      Digest::SHA2.hexdigest "#{message_size}#{message_date}#{message_id}"
    end

    private

  end
end
