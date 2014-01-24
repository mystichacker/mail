# encoding: utf-8

module Mail
  # The IMAP retriever allows to get the last, first or all emails from a IMAP server.
  # Each email retrieved (RFC2822) is given as an instance of +Message+.
  #
  # While being retrieved, emails can be yielded if a block is given.
  #
  # === Example of retrieving Emails from GMail:
  #
  #   Mail.defaults do
  #     retriever_method :imap, { :address             => "imap.googlemail.com",
  #                               :port                => 993,
  #                               :user_name           => '<username>',
  #                               :password            => '<password>',
  #                               :enable_ssl          => true }
  #   end
  #
  #   Mail.all    #=> Returns an array of all emails
  #   Mail.first  #=> Returns the first unread email
  #   Mail.last   #=> Returns the last unread email
  #
  # You can also pass options into Mail.find to locate an email in your imap mailbox
  # with the following options:
  #
  #   mailbox: name of the mailbox used for email retrieval. The default is 'INBOX'.
  #   what:    last or first emails. The default is :first.
  #   order:   order of emails returned. Possible values are :asc or :desc. Default value is :asc.
  #   count:   number of emails to retrieve. The default value is 10. A value of 1 returns an
  #            instance of Message, not an array of Message instances.
  #   keys:    are passed as criteria to the SEARCH command.  They can either be a string holding the entire search string, 
  #            or a single-dimension array of search keywords and arguments.  Refer to  [IMAP] section 6.4.4 for a full list
  #            The default is 'ALL'
  #
  #   Mail.find(:what => :first, :count => 10, :order => :asc, :keys=>'ALL')
  #   #=> Returns the first 10 emails in ascending order
  #
  class IMAP < Retriever
    require 'net/imap' unless defined?(Net::IMAP)
    
    def initialize(values)
      self.settings = { :address              => "localhost",
                        :port                 => 143,
                        :user_name            => nil,
                        :password             => nil,
                        :authentication       => nil,
                        :enable_ssl           => false }.merge!(values)
    end

    attr_accessor :settings

    # Find folders in a IMAP mailbox. Without any options, the 10 last folders are returned.
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
      options[:mailbox] ||= ''
      options = validate_options(options)
      mailbox = options[:mailbox] || ''
      mailbox = Net::IMAP.encode_utf7(mailbox)
      mailbox = mailbox.empty? ? '*' : "#{mailbox}/*"

      start do |imap|

        boxes = options[:subscribed] ? imap.lsub('', mailbox) : imap.list('', mailbox)
        boxes.reverse! if options[:what].to_sym == :last
        boxes = boxes.first(options[:count]) if options[:count].is_a?(Integer)
        boxes.reverse! if (options[:what].to_sym == :last && options[:order].to_sym == :asc) ||
            (options[:what].to_sym != :last && options[:order].to_sym == :desc)

        if block_given?
          boxes.each do |box|
            name = Net::IMAP.decode_utf7(box.name)
            next if name =~ /^\[Gmail\]\/*/
            name = 'INBOX' if name.downcase == 'inbox'
            flags = box.attr ? box.attr.map{|e| e.to_s.downcase.to_sym} : nil
            status = imap.status(box.name, ["MESSAGES", "UNSEEN", "UIDVALIDITY", "UIDNEXT"])
            yield Folder.new(name, delim: box.delim, flags: flags, messages: status['MESSAGES'], unseen: status['UNSEEN'], validity: status['UIDVALIDITY'], next: status['UIDNEXT'])
          end unless boxes.nil?
        else
          folders = []
          boxes.each do |box|
            name = Net::IMAP.decode_utf7(box.name)
            next if name =~ /^\[Gmail\]\/*/
            name = 'INBOX' if name.downcase == 'inbox'
            flags = box.attr ? box.attr.map{|e| e.to_s.downcase.to_sym} : nil
            status = imap.status(box.name, ["MESSAGES", "UNSEEN", "UIDVALIDITY", "UIDNEXT"])
            folders << Folder.new(name, delim: box.delim, flags: flags, messages: status['MESSAGES'], unseen: status['UNSEEN'], validity: status['UIDVALIDITY'], next: status['UIDNEXT'])
          end unless boxes.nil?
          folders.size == 1 && options[:count] == 1 ? folders.first : folders
        end
      end
    end

    # Find emails in a IMAP mailbox. Without any options, the 10 last received emails are returned.
    #
    # Possible options:
    #   mailbox: mailbox to search the email(s) in. The default is 'INBOX'.
    #   what:    last or first emails. The default is :first.
    #   order:   order of emails returned. Possible values are :asc or :desc. Default value is :asc.
    #   count:   number of emails to retrieve. The default value is 10. A value of 1 returns an
    #            instance of Message, not an array of Message instances.
    #   read_only: will ensure that no writes are made to the inbox during the session.  Specifically, if this is
    #              set to true, the code will use the EXAMINE command to retrieve the mail.  If set to false, which
    #              is the default, a SELECT command will be used to retrieve the mail
    #              This is helpful when you don't want your messages to be set to read automatically. Default is false.
    #   delete_after_find: flag for whether to delete each retrieved email after find. Default
    #           is false. Use #find_and_delete if you would like this to default to true.
    #   keys:   are passed as criteria to the SEARCH command.  They can either be a string holding the entire search string, 
    #           or a single-dimension array of search keywords and arguments.  Refer to  [IMAP] section 6.4.4 for a full list
    #           The default is 'ALL'
    #
    def find(options={}, &block)
      options = validate_options(options)

      start do |imap|
        options[:read_only] ? imap.examine(options[:mailbox]) : imap.select(options[:mailbox])

        uids = imap.uid_search(options[:keys])
        uids.reverse! if options[:what].to_sym == :last
        uids = uids.first(options[:count]) if options[:count].is_a?(Integer)
        uids.reverse! if (options[:what].to_sym == :last && options[:order].to_sym == :asc) ||
                                (options[:what].to_sym != :last && options[:order].to_sym == :desc)

        if block_given?
          uids.each do |uid|
            uid = options[:uid].to_i unless options[:uid].nil?
            fetchdata = imap.uid_fetch(uid, ['RFC822'])[0]
            new_message = Mail.new(fetchdata.attr['RFC822'])
            new_message.mark_for_delete = true if options[:delete_after_find]
            if block.arity == 3
              yield new_message, imap, uid
            else
              yield new_message
            end
            imap.uid_store(uid, "+FLAGS", [Net::IMAP::DELETED]) if options[:delete_after_find] && new_message.is_marked_for_delete?
            break unless options[:uid].nil?
          end
          imap.expunge if options[:delete_after_find]
        else
          emails = []
          uids.each do |uid|
            uid = options[:uid].to_i unless options[:uid].nil?
            fetchdata = imap.uid_fetch(uid, ['RFC822'])[0]
            emails << Mail.new(fetchdata.attr['RFC822'])
            imap.uid_store(uid, "+FLAGS", [Net::IMAP::DELETED]) if options[:delete_after_find]
            break unless options[:uid].nil?
          end
          imap.expunge if options[:delete_after_find]
          emails.size == 1 && options[:count] == 1 ? emails.first : emails
        end
      end
    end

    # Find batches of emails in a IMAP mailbox. Without any options, all emails are returned in batches of 100.
    #
    # Possible options:
    #   mailbox: mailbox to search the email(s) in. The default is 'INBOX'.
    #   read_only: will ensure that no writes are made to the inbox during the session.  Specifically, if this is
    #              set to true, the code will use the EXAMINE command to retrieve the mail.  If set to false, which
    #              is the default, a SELECT command will be used to retrieve the mail
    #              This is helpful when you don't want your messages to be set to read automatically. Default is false.
    #   delete_after_find: flag for whether to delete each retrieved email after find. Default
    #           is false. Use #find_and_delete if you would like this to default to true.
    #   keys:   are passed as criteria to the SEARCH command.  They can either be a string holding the entire search string,
    #           or a single-dimension array of search keywords and arguments.  Refer to  [IMAP] section 6.4.4 for a full list
    #           The default is 'ALL'
    #   batch_size: size of batches returned
    #
    def find_in_batches(options={}, &block)
      options = validate_options(options)
      batch_size = options.delete(:batch_size) || 100

      start do |imap|
        options[:read_only] ? imap.examine(options[:mailbox]) : imap.select(options[:mailbox])

        uids = imap.uid_search(options[:keys])

        if block_given?
          uids.each_slice(batch_size) do |batch|
            emails = []
            batch.each do |uid|
              fetchdata = imap.uid_fetch(uid, ['RFC822'])[0]
              emails << Mail.new(fetchdata.attr['RFC822'])
              imap.uid_store(uid, "+FLAGS", [Net::IMAP::DELETED]) if options[:delete_after_find]
            end
            yield emails
          end
          imap.expunge if options[:delete_after_find]
        end
      end
    end

    # Find each email in a IMAP mailbox using find_in_batches. Without any options,  emails are found in batches of 100.
    #
    # Possible options:
    #   mailbox: mailbox to search the email(s) in. The default is 'INBOX'.
    #   read_only: will ensure that no writes are made to the inbox during the session.  Specifically, if this is
    #              set to true, the code will use the EXAMINE command to retrieve the mail.  If set to false, which
    #              is the default, a SELECT command will be used to retrieve the mail
    #              This is helpful when you don't want your messages to be set to read automatically. Default is false.
    #   delete_after_find: flag for whether to delete each retrieved email after find. Default
    #           is false. Use #find_and_delete if you would like this to default to true.
    #   keys:   are passed as criteria to the SEARCH command.  They can either be a string holding the entire search string,
    #           or a single-dimension array of search keywords and arguments.  Refer to  [IMAP] section 6.4.4 for a full list
    #           The default is 'ALL'
    #   batch_size: size of batches returned
    #
    def find_each(options = {})
      find_in_batches(options) do |messages|
        messages.each { |messages| yield messages }
      end
    end

    # Find batches of email entries in a mailbox.
    #
    # Possible options:
    #   mailbox: mailbox to search the email(s) in. The default is 'INBOX'.
    #   keys:   are passed as criteria to the SEARCH command.  They can either be a string holding the entire search string,
    #           or a single-dimension array of search keywords and arguments.  Refer to  [IMAP] section 6.4.4 for a full list
    #           The default is 'ALL'
    #   uids:   uid search criteria that is merged with keys and passed to the SEARCH command.  Can be given as a range, array
    #           or string.
    #   batch_size: size of batches returned
    #
    def find_entries_in_batches(options={}, &block)
      options = validate_options(options)
      mailbox = options[:mailbox]
      batch_size = options.delete(:batch_size) || 5000

      start do |imap|
        imap.examine(mailbox)
        validity = imap.responses["UIDVALIDITY"].first
        #next_uid = imap.responses["UIDNEXT"].first
        uids = imap.uid_search(options[:keys])

        if block_given?
          uids.each_slice(batch_size) do |batch|
            results = []
            imap.uid_fetch(batch, "(UID RFC822.SIZE INTERNALDATE BODY.PEEK[HEADER.FIELDS (MESSAGE-ID)] FLAGS)").each do |data|
              uid = data.attr['UID'].to_i
              size = data.attr['RFC822.SIZE'].to_i
              date = Time.parse(data.attr['INTERNALDATE'])
              data.attr['BODY[HEADER.FIELDS (MESSAGE-ID)]'] =~ /.*<(.*)>.*/ ; message_id = $1
              flags = data.attr['FLAGS'].map {|flag| flag.to_s.downcase.to_sym}
              results << Entry.new(mailbox, validity, uid, size, date, message_id, flags)
            end
            yield results
          end
        end
      end
    end

    # Find each email entry in a mailbox using find_entries_in_batches.
    #
    # Possible options:
    #   keys:   are passed as criteria to the SEARCH command.  They can either be a string holding the entire search string,
    #           or a single-dimension array of search keywords and arguments.  Refer to  [IMAP] section 6.4.4 for a full list
    #           The default is 'ALL'
    #   uids:   uid search criteria that is merged with keys and passed to the SEARCH command.  Can be given as a range, array
    #           or string.
    #   batch_size: size of batches used
    #
    def find_each_entry(options={}, &block)
      find_entries_in_batches(options) do |entries|
        entries.each { |entry| yield entry }
      end
    end

    # Find email entries in a mailbox.
    #
    # Possible options:
    #   mailbox: mailbox to search the email(s) in. The default is 'INBOX'.
    #   keys:   are passed as criteria to the SEARCH command.  They can either be a string holding the entire search string,
    #           or a single-dimension array of search keywords and arguments.  Refer to  [IMAP] section 6.4.4 for a full list
    #           The default is 'ALL'
    #   uids:   uid search criteria that is merged with keys and passed to the SEARCH command.  Can be given as a range, array
    #           or string.
    #   batch_size: size of batches used
    #
    def find_entries(options = {}, &block)
      if block_given?
        find_each_entry(options) do |entry|
          yield entry
        end
      else
        results = []
        find_entries_in_batches(options) do |entries|
          results += entries
        end
        results.size == 1 ? results.first : results
      end
    end

    # Delete all emails from a IMAP mailbox
    def delete_all(mailbox='INBOX')
      mailbox ||= 'INBOX'
      mailbox = Net::IMAP.encode_utf7(mailbox)

      start do |imap|
        imap.uid_search(['ALL']).each do |uid|
          imap.uid_store(uid, "+FLAGS", [Net::IMAP::DELETED])
        end
        imap.expunge
      end
    end

    # Returns the connection object of the retrievable (IMAP or POP3)
    def connection(&block)
      raise ArgumentError.new('Mail::Retrievable#connection takes a block') unless block_given?

      start do |imap|
        yield imap
      end
    end

    private

      # Set default options
      def validate_options(options)
        options ||= {}
        options[:mailbox] ||= 'INBOX'
        options[:count]   ||= 10
        options[:order]   ||= :asc
        options[:what]    ||= :first
        options[:keys]    ||= 'ALL'
        options[:uid]     ||= nil
        options[:uids]     ||= nil
        options[:delete_after_find] ||= false
        options[:mailbox] = Net::IMAP.encode_utf7(options[:mailbox])
        options[:read_only] ||= false
        options[:subscribed] ||= false
        options[:keys] = build_keys(options[:uid] || options[:uids]) if options[:uid] || options[:uids]
        options
      end

      # Build search keys from uids
      #
      def build_keys(uids)
        if uids.is_a?(Numeric)
          "UID #{uids}"
        elsif uids.is_a?(Array)
          "UID #{uids.join(',')}"
        elsif uids.is_a?(Range)
          "UID #{Array(uids).join(',')}"
        elsif uids.is_a?(Hash)
          "UID #{uids[:from] ? uids[:from] : 1}:#{uids[:to] ? uids[:to] : '*'}"
        elsif uids.is_a?(String)
          uids.downcase == 'all' ? 'ALL' : "UID #{uids}"
        elsif uids.is_a?(Symbol)
          uids.to_s.downcase == 'all' ? 'ALL' : ''
        else
          ""
        end
      end

      # Start an IMAP session and ensures that it will be closed in any case.
      def start(config=Mail::Configuration.instance, &block)
        raise ArgumentError.new("Mail::Retrievable#imap_start takes a block") unless block_given?

        imap = Net::IMAP.new(settings[:address], settings[:port], settings[:enable_ssl], nil, false)
        if settings[:authentication].nil?
          imap.login(settings[:user_name], settings[:password])
        else
          # Note that Net::IMAP#authenticate('LOGIN', ...) is not equal with Net::IMAP#login(...)!
          # (see also http://www.ensta.fr/~diam/ruby/online/ruby-doc-stdlib/libdoc/net/imap/rdoc/classes/Net/IMAP.html#M000718)
          imap.authenticate(settings[:authentication], settings[:user_name], settings[:password])
        end

        yield imap
      ensure
        if defined?(imap) && imap && !imap.disconnected?
          imap.disconnect
        end
      end

  end
end
