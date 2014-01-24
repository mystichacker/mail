# encoding: utf-8
module Mail
  
  # Represents a message entry.
  # 
  class Entry
    include Patterns
    include Utilities

    # Creates a new message entry object.
    #
    def initialize(folder, validity, uid, size, date, message_id, flags, options={})
      @folder = folder
      @validity = validity
      @uid = uid
      @size = size
      @date = date
      @message_id = message_id
      @flags = flags
    end

    attr_reader :folder, :validity, :uid, :size, :date, :message_id, :flags

    def to_s
      "#{folder}.#{validity}.#{uid}: #{sha}"
    end

    # Returns a message sha that can be used to identify a message
    #
    def sha
      Digest::SHA2.hexdigest "#{size}#{date}#{message_id}"
    end

    private


  end
end
