require 'mail/check_delivery_params'

module Mail
  # == Sending Email with SMTP
  # 
  # Mail allows you to send emails using SMTP.  This is done by wrapping Net::SMTP in
  # an easy to use manner.
  # 
  # === Sending via SMTP server on Localhost
  # 
  # Sending locally (to a postfix or sendmail server running on localhost) requires
  # no special setup.  Just to Mail.deliver &block or message.deliver! and it will
  # be sent in this method.
  # 
  # === Sending via MobileMe
  # 
  #   Mail.defaults do
  #     delivery_method :smtp, { :address              => "smtp.me.com",
  #                              :port                 => 587,
  #                              :domain               => 'your.host.name',
  #                              :user_name            => '<username>',
  #                              :password             => '<password>',
  #                              :authentication       => 'plain',
  #                              :enable_starttls_auto => true  }
  #   end
  # 
  # === Sending via GMail
  #
  #   Mail.defaults do
  #     delivery_method :smtp, { :address              => "smtp.gmail.com",
  #                              :port                 => 587,
  #                              :domain               => 'your.host.name',
  #                              :user_name            => '<username>',
  #                              :password             => '<password>',
  #                              :authentication       => 'plain',
  #                              :enable_starttls_auto => true  }
  #   end
  #
  # === Certificate verification
  #
  # When using TLS, some mail servers provide certificates that are self-signed
  # or whose names do not exactly match the hostname given in the address.
  # OpenSSL will reject these by default. The best remedy is to use the correct
  # hostname or update the certificate authorities trusted by your ruby. If
  # that isn't possible, you can control this behavior with
  # an :openssl_verify_mode setting. Its value may be either an OpenSSL
  # verify mode constant (OpenSSL::SSL::VERIFY_NONE), or a string containing
  # the name of an OpenSSL verify mode (none, peer, client_once,
  # fail_if_no_peer_cert).
  #
  # === Others 
  # 
  # Feel free to send me other examples that were tricky
  # 
  # === Delivering the email
  # 
  # Once you have the settings right, sending the email is done by:
  # 
  #   Mail.deliver do
  #     to 'mikel@test.lindsaar.net'
  #     from 'ada@test.lindsaar.net'
  #     subject 'testing sendmail'
  #     body 'testing sendmail'
  #   end
  # 
  # Or by calling deliver on a Mail message
  # 
  #   mail = Mail.new do
  #     to 'mikel@test.lindsaar.net'
  #     from 'ada@test.lindsaar.net'
  #     subject 'testing sendmail'
  #     body 'testing sendmail'
  #   end
  # 
  #   mail.deliver!
  class SMTP
    include Mail::CheckDeliveryParams

    def initialize(values)
      self.settings = { :address => "localhost",
                        :port => 25,
                        :domain => 'localhost.localdomain',
                        :user_name => nil,
                        :password => nil,
                        :authentication => nil,
                        :enable_starttls_auto => true,
                        :openssl_verify_mode => nil,
                        :ssl => nil,
                        :tls => nil
      }.merge!(values)
      @connection = nil
    end

    attr_accessor :settings

    # Send the message via SMTP.
    # The from and to attributes are optional. If not set, they are retrieve from the Message.
    def deliver!(mail)
      smtp_from, smtp_to, message = check_delivery_params(mail)
      start do |smtp|
        info 'sending message'
        response = smtp.sendmail(message, smtp_from, smtp_to)
        info response.inspect
      end

      if settings[:return_response]
        response
      else
        self
      end
    end
    alias_method :deliver, :'deliver!'

    # Returns the connection object of the delivery method
    def connection(&block)
      raise ArgumentError.new('Mail::Deliverable#connection takes a block') unless block_given?

      start do |smtp|
        info 'connection block'
        yield smtp, self
      end
    end
    private

    # Start an SMTP session and ensures that it will be closed in any case.
    #
    def start(config = Mail::Configuration.instance, &block)
      raise ArgumentError.new('Mail::Deliverable#imap_start takes a block') unless block_given?
      if @connection
        info 'connection already open'
        yield @connection
      else
        begin
          @connection = Net::SMTP.new(settings[:address], settings[:port])
          if settings[:tls] || settings[:ssl]
            if @connection.respond_to?(:enable_tls)
              @connection.enable_tls(ssl_context)
            end
          elsif settings[:enable_starttls_auto]
            if @connection.respond_to?(:enable_starttls_auto)
              @connection.enable_starttls_auto(ssl_context)
            end
          end
          info 'start connection'
          @connection.start(settings[:domain], settings[:user_name], settings[:password], settings[:authentication])
          info 'connection started'
          yield @connection
        ensure # closes connection
          info 'close connection block'
          if defined?(@connection) && @connection && @connection.started?
            info 'close connection'
            @connection.finish
          end
          @connection = nil
        end
      end
    end

    # Allow SSL context to be configured via settings, for Ruby >= 1.9
    # Just returns openssl verify mode for Ruby 1.8.x
    def ssl_context
      openssl_verify_mode = settings[:openssl_verify_mode]

      if openssl_verify_mode.kind_of?(String)
        openssl_verify_mode = "OpenSSL::SSL::VERIFY_#{openssl_verify_mode.upcase}".constantize
      end

      context = Net::SMTP.default_ssl_context
      context.verify_mode = openssl_verify_mode
      context.ca_path = settings[:ca_path] if settings[:ca_path]
      context.ca_file = settings[:ca_file] if settings[:ca_file]
      context
    end

    # Logger
    # @param [Symbol] level
    # @param [String] msg
    # @return [Bool] logged
    def log(level, msg)
      return true if ![:fatal, :error, :warn, :info, :debug, :insane].include?(level) || msg.nil? || msg.empty?
      puts "[mail/#{level}/#{Time.new.strftime('%H:%M:%S')}] #{msg}"
      true
    rescue => e
      false
    end

    def fatal(msg)
      log(:fatal, msg)
    end

    def error(msg)
      log(:error, msg)
    end

    def warn(msg)
      log(:warn, msg)
    end

    def debug(msg)
      log(:debug, msg)
    end

    def info(msg)
      log(:info, msg)
    end

    def insane(msg)
      log(:insane, msg)
    end

  end # SMTP
end # Mail