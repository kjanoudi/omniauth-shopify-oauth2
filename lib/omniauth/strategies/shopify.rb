require 'omniauth/strategies/oauth2'

module OmniAuth
  module Strategies
    class Shopify < OmniAuth::Strategies::OAuth2
      # Available scopes: content themes products customers orders script_tags shipping
      # read_*  or write_*
      # DEFAULT_SCOPE = 'read_products'
      MINUTE = 60
      CODE_EXPIRES_AFTER = 10 * MINUTE

      option :client_options, {
        :site => '',
        :authorize_url => '/admin/oauth/authorize',
        :token_url => '/admin/oauth/access_token'
      }

      option :callback_url

      uid { URI.parse(options[:client_options][:site]).host }

      def valid_site?
        !!(/\A(https|http)\:\/\/[a-zA-Z0-9][a-zA-Z0-9\-]*\.myshopify.com[\/]?\z/ =~ options[:client_options][:site])
      end

      def valid_signature?
        return false unless request.POST.empty?

        params = request.GET
        signature = params['hmac']
        timestamp = params['timestamp']
        return false unless signature && timestamp

        return false unless timestamp.to_i > Time.now.to_i - CODE_EXPIRES_AFTER

        calculated_signature = self.class.hmac_sign(self.class.encoded_params_for_signature(params), options.client_secret)
        Rack::Utils.secure_compare(calculated_signature, signature)
      end

      def self.encoded_params_for_signature(params)
        params = params.dup
        params.delete('hmac')
        params.delete('signature') # deprecated signature
        params.map{|k,v| "#{URI.escape(k.to_s, '&=%')}=#{URI.escape(v.to_s, '&%')}"}.sort.join('&')
      end

      def self.hmac_sign(encoded_params, secret)
        OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA256.new, secret, encoded_params)
      end

      def fix_https
        url = options[:client_options][:site]
        return unless url
        url.gsub!('http://', 'https://')
        url = "https://#{url}" unless url.starts_with?('https')
        options[:client_options][:site] = url
      end

      def setup_phase
        options[:client_options][:site] = request.GET['shop']
        fix_https
        super
      end

      def request_phase
        fix_https
        super
      end

      def callback_phase
        fix_https
        return fail!(:invalid_site) unless valid_site?
        return fail!(:invalid_signature) unless valid_signature?
        super
      end

      def callback_url
        options[:callback_url] || full_host + script_name + callback_path
      end
    end
  end
end
