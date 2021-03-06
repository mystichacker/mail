# encoding: utf-8

module Mail
  # The Pop3 retriever allows to get the last, first or all emails from a POP3 server.
  # Each email retrieved (RFC2822) is given as an instance of +Message+.
  #
  # While being retrieved, emails can be yielded if a block is given.
  # 
  # === Example of retrieving Emails from GMail:
  # 
  #   Mail.defaults do
  #     retriever_method :pop3, { :address             => "pop.gmail.com",
  #                               :port                => 995,
  #                               :user_name           => '<username>',
  #                               :password            => '<password>',
  #                               :enable_ssl          => true }
  #   end
  # 
  #   Mail.all    #=> Returns an array of all emails
  #   Mail.first  #=> Returns the first unread email
  #   Mail.last   #=> Returns the last unread email
  # 
  # You can also pass options into Mail.find to locate an email in your pop mailbox
  # with the following options:
  # 
  #   what:  last or first emails. The default is :first.
  #   order: order of emails returned. Possible values are :asc or :desc. Default value is :asc.
  #   count: number of emails to retrieve. The default value is 10. A value of 1 returns an
  #          instance of Message, not an array of Message instances.
  # 
  #   Mail.find(:what => :first, :count => 10, :order => :asc)
  #   #=> Returns the first 10 emails in ascending order
  # 
  class POP3 < Retriever
    require 'net/pop' unless defined?(Net::POP)

    def initialize(values)
      self.settings = { :address              => "localhost",
                        :port                 => 110,
                        :user_name            => nil,
                        :password             => nil,
                        :authentication       => nil,
                        :enable_ssl           => false }.merge!(values)
      @connection = nil
    end
    
    attr_accessor :settings

    # Find folders in a Pop3 mailbox. Without any options, the 10 last folders are returned.
    #
    # Possible options:
    #   mailbox: mailbox to search the folders(s) in. The default is 'INBOX'.
    #   what:    last or first emails. The default is :first.
    #   order:   order of emails returned. Possible values are :asc or :desc. Default value is :asc.
    #   count:   number of emails to retrieve. The default value is 10. A value of 1 returns an
    #            instance of Message, not an array of Message instances.
    #   subscribed: flag for whether to find subscribed folders only. Default is false
    #
    def find_folders(options={}, &block)
      if block_given?
        yield nil
      else
        nil
      end
    end

    # Find emails in a POP3 mailbox. Without any options, the 5 last received emails are returned.
    #
    # Possible options:
    #   what:  last or first emails. The default is :first.
    #   order: order of emails returned. Possible values are :asc or :desc. Default value is :asc.
    #   count: number of emails to retrieve. The default value is 10. A value of 1 returns an
    #          instance of Message, not an array of Message instances.
    #   delete_after_find: flag for whether to delete each retrieved email after find. Default
    #           is false. Use #find_and_delete if you would like this to default to true.
    #
    def find(options = {}, &block)
      options = validate_options(options)
      
      start do |pop3|
        mails = pop3.mails
        pop3.reset # Clears all "deleted" marks. This prevents non-explicit/accidental deletions due to server settings.
        mails.sort! { |m1, m2| m2.number <=> m1.number } if options[:what] == :last
        mails = mails.first(options[:count]) if options[:count].is_a? Integer
        
        if options[:what].to_sym == :last && options[:order].to_sym == :desc ||
           options[:what].to_sym == :first && options[:order].to_sym == :asc ||
          mails.reverse!
        end
        
        if block_given?
          mails.each do |mail|
            new_message = Mail.new(mail.pop)
            new_message.mark_for_delete = true if options[:delete_after_find]
            yield new_message
            mail.delete if options[:delete_after_find] && new_message.is_marked_for_delete? # Delete if still marked for delete
          end
        else
          emails = []
          mails.each do |mail|
            emails << Mail.new(mail.pop)
            mail.delete if options[:delete_after_find]
          end
          emails.size == 1 && options[:count] == 1 ? emails.first : emails
        end
        
      end
    end

    # Find batches of emails in a POP3 mailbox. Without any options, all emails are returned in batches of 100.
    #
    # Possible options:
    #   batch_size: size of batches returned
    #   delete_after_find: flag for whether to delete each retrieved email after find. Default
    #           is false. Use #find_and_delete if you would like this to default to true.
    #
    def find_in_batches(options={}, &block)
      options = validate_options(options)
      batch_size = options.delete(:batch_size) || 100

      start do |pop3|
        mails = pop3.mails
        pop3.reset # Clears all "deleted" marks. This prevents non-explicit/accidental deletions due to server settings.

        if block_given?
          mails.each_slice(batch_size) do |batch|
            emails = []
            batch.each do |mail|
              emails << Mail.new(mail.pop)
              mail.delete if options[:delete_after_find]
            end
            yield emails
          end
        end
      end
    end

    # Find each email in a POP3 mailbox using find_in_batches. Without any options,  emails are found in batches of 100.
    #
    # Possible options:
    #   batch_size: size of batches returned
    #   delete_after_find: flag for whether to delete each retrieved email after find. Default
    #           is false. Use #find_and_delete if you would like this to default to true.
    #
    def find_each(options = {})
      find_in_batches(options) do |messages|
        messages.each { |messages| yield messages }
      end
    end

    # Find batches of email entries in a mailbox.
    #
    # Possible options:
    #   batch_size: size of batches returned
    #
    def find_entries_in_batches(options={}, &block)
      options = validate_options(options)

      start do |pop3|
        if block_given?
          yield nil
        end
      end
    end


    # Find each email entry in a mailbox using find_entries_in_batches.
    #
    # Possible options:
    #   batch_size: size of batches used
    #
    def find_each_entry(options={}, &block)
      find_entries_in_batches(options) do |entries|
        entries.each { |entry| yield entry }
      end
    end

    # Delete all emails from a POP3 server
    def delete_all
      start do |pop3|
        unless pop3.mails.empty?
          pop3.delete_all
          pop3.finish
        end
      end
    end

    # Returns the connection object of the retrievable (IMAP or POP3)
    def connection(&block)
      raise ArgumentError.new('Mail::Retrievable#connection takes a block') unless block_given?

      start do |pop3|
        yield pop3
      end
    end
    
  private
  
    # Set default options
    def validate_options(options)
      options ||= {}
      options[:count] ||= 10
      options[:order] ||= :asc
      options[:what]  ||= :first
      options[:delete_after_find] ||= false
      options
    end
  
    # Start a POP3 session and ensure that it will be closed in any case. Any messages
    # marked for deletion via #find_and_delete or with the :delete_after_find option
    # will be deleted when the session is closed.
    def start(config = Configuration.instance, &block)
      raise ArgumentError.new("Mail::Retrievable#pop3_start takes a block") unless block_given?
      if @connection
        yield @connection
      else
        begin
          @connection = Net::POP3.new(settings[:address], settings[:port], false)
          @connection.enable_ssl(OpenSSL::SSL::VERIFY_NONE) if settings[:enable_ssl]
          @connection.start(settings[:user_name], settings[:password])

          yield @connection
        ensure
          if defined?(@connection) && @connection && @connection.started?
            @connection.finish
          end
          @connection = nil
        end
      end
    end

  end # POP3
end # Mail
