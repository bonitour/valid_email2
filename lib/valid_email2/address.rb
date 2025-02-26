require "valid_email2"
require "resolv"
require "mail"

module ValidEmail2
  class Address
    attr_accessor :address

    PROHIBITED_DOMAIN_CHARACTERS_REGEX = /[+!_]/
    DEFAULT_RECIPIENT_DELIMITER = '+'.freeze

    def initialize(address)
      @parse_error = false
      @raw_address = address

      begin
        @address = Mail::Address.new(address)
      rescue Mail::Field::ParseError
        @parse_error = true
      end

      @parse_error ||= address_contain_emoticons? @raw_address
    end

    def valid?
      return false if @parse_error

      if address.domain && address.address == @raw_address
        domain = address.domain

        domain !~ PROHIBITED_DOMAIN_CHARACTERS_REGEX &&
          # Domain needs to have at least one dot
          domain =~ /\./ &&
          # Domain may not have two consecutive dots
          domain !~ /\.{2,}/ &&
          # Domain may not start with a dot
          domain !~ /^\./ &&
          # Address may not contain a dot directly before @
          address.address !~ /\.@/
      else
        false
      end
    end

    def subaddressed?
      valid? && address.local.include?(DEFAULT_RECIPIENT_DELIMITER)
    end

    def disposable?
      valid? &&
        (
          domain_is_in?(ValidEmail2.disposable_emails) ||
          mx_server_is_in?(ValidEmail2.disposable_emails)
        )
    end

    def whitelisted?
      domain_is_in?(ValidEmail2.whitelist)
    end

    def blacklisted?
      valid? && domain_is_in?(ValidEmail2.blacklist)
    end

    def valid_mx?
      return false unless valid?

      mx_servers.any?
    end

    private

    def domain_is_in?(domain_list)
      address_domain = address.domain.downcase
      domain_list.any? { |domain|
        address_domain.end_with?(domain) && address_domain =~ /\A(?:.+\.)*?#{domain}\z/
      }
    end

    def mx_server_is_in?(domain_list)
      mx_servers.any? { |mx_server|
        return false unless mx_server.respond_to?(:exchange)
        mx_server = mx_server.exchange.to_s

        domain_list.any? { |domain|
          mx_server.end_with?(domain) && mx_server =~ /\A(?:.+\.)*?#{domain}\z/
        }
      }
    end

    def address_contain_emoticons?(email)
      return false if email.nil?

      email.each_char.any? { |char| char.bytesize > 1 }
    end

    def mx_servers
      @mx_servers ||= Resolv::DNS.open do |dns|
        mx_servers = dns.getresources(address.domain, Resolv::DNS::Resource::IN::MX)
        (mx_servers.any? && mx_servers) ||
          dns.getresources(address.domain, Resolv::DNS::Resource::IN::A)
      end
    end
  end
end
