require "net/http"
require "net/http/digest_auth"
require 'openssl'
require 'nokogiri'
require 'date'

class Nokogiri::XML::Document
  def get (str)
    self.at_css(str).content
  end
end

module PCSREST
  VERSION = 0.1
  
  # Some Error Handling for HTTP requests
  class HTTPAuthChal < StandardError; end
  class HTTPAuthFail < StandardError; end
  class HTTPForbidden < StandardError; end
  class HTTPNotAcceptable < StandardError; end
  class HTTPNotFound < StandardError; end
  class UnexpectedError < StandardError; end
  class APIError < StandardError; end
  
  class API
    attr_accessor :host, :spid, :user, :pass
    
    @@default_subscriber = "#{Dir.pwd}/templates/subscriber.xml"
    @@default_return_params = [:popdAccountNum, :firstName, :lastName, :conferencePasscode, :moderatorPasscode]
    
    def initialize args = {}
      @host = args[:host] or raise ArgumentError, "must include :host"
      @spid = args[:spid] or raise ArgumentError, "must include :spid"
      @user = args[:user] or raise ArgumentError, "must include :user"
      @pass = args[:pass] or raise ArgumentError, "must include :pass"
      @base_uri = URI ("https://#{@host}/PcsRESTApi/version")
      @base_uri.user = CGI.escape args[:user]
      @base_uri.password = args[:pass]
      create_http_conn
    end
    
    def get_version
      uri = "/PcsRESTApi/version"
      resp = http_get uri
      xml = Nokogiri::XML resp.body
      version = xml.get('releaseVersion')
      version_date = DateTime.parse xml.get('releaseDate')
      puts "Version: #{version}  Date: #{version_date.strftime("%F")}"
    end
  
    def get_sub (username, optional_args = [])
      uri = "/PcsRESTApi/serviceproviders/#{@spid}/subscribers/username-#{username}"
      return_params = @@default_return_params | optional_args 
      http_resp = http_get uri
      sub = Nokogiri::XML http_resp.body
      root = sub.root
      result = {:id => root["id"]}
      return_params.each do |param|
        result[param] = sub.at_css(param.to_s).nil? ? "null" : sub.at_css(param.to_s).content
      end
      return result
    end

    def create_sub (first_name, last_name, email_address, password, options={})
      input_params = {:firstName => first_name, 
                      :lastName => last_name, 
                      :emailAddress => email_address,
                      :loginUserId => email_address, 
                      :loginPassword => password,
                      :confSubject => "#{first_name} #{last_name}'s Conference"}
      input_params.merge!(options)
      body = build_sub_xml input_params
      uri = "/PcsRESTApi/serviceproviders/#{@spid}/subscribers/"
      http_resp = http_post(uri, body)
      sub = Nokogiri::XML http_resp.body
      root = sub.root
      result = {:id => root["id"]}
      @@default_return_params.each do |param|
        result[param] = sub.at_css(param.to_s).nil? ? "null" : sub.at_css(param.to_s).content
      end
      return result
    end
   
    private
  
    # Create Persistent HTTP Connection and HTTP Digest
    def create_http_conn
      @http = Net::HTTP.new(@base_uri.host, @base_uri.port)
      @http.use_ssl = true
      @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      @digest_auth = Net::HTTP::DigestAuth.new
    end
    
  # Create HTTP Request that handles digest authentication
    def http_req_with_digest_auth (http_req, body = nil)
      digest = nil
      begin
        http_req.add_field 'Authorization', digest unless digest.nil?
        http_resp = @http.request(http_req, body)
        case http_resp
        when Net::HTTPUnauthorized
          raise HTTPAuthChal if digest.nil?
        end
        http_resp
      rescue HTTPAuthChal
        digest = @digest_auth.auth_header @base_uri, http_resp['www-authenticate'], http_req.method
        retry
      end
    end
  
    def handle_error (http_resp)
      case http_resp
      when Net::HTTPUnauthorized
        raise HTTPAuthFail, "HTTP Digest Authentication Failed: #{http_resp.message} - #{http_resp.code}"
      when Net::HTTPForbidden
        raise HTTPForbidden, "The user is not authorised to access the resource: #{http_resp.message} - #{http_resp.code}"
      when Net::HTTPNotAcceptable
        raise HTTPNotAcceptable, "Invalid request: #{http_resp.message} - #{http_resp.code}"
      when Net::HTTPNotFound
         raise HTTPNotFound, "#{http_resp.message} - #{http_resp.code}"
      when Net::HTTPInternalServerError
         raise APIError, "Error code: #{http_resp['errorCode']}, #{http_resp['errorMessage']}"
      else
        raise UnexpectedError, "An unexpected error occured: #{http_resp.message} - #{http_resp.code} - #{http_resp.class}" 
      end
    end
  
    # HTTP GET, POST with Digest Auth
    
    def http_get uri
      http_req = Net::HTTP::Get.new uri
      http_resp = http_req_with_digest_auth http_req
      case http_resp
      when Net::HTTPSuccess
        return http_resp
      else
        handle_error http_resp
      end
    end

    def http_post (uri, body = nil)
      http_req = Net::HTTP::Post.new uri
      if body
        http_req.add_field 'Content-Type', 'application/xml'
        http_req.body = body
      end
      http_resp = http_req_with_digest_auth http_req
      case http_resp
      when Net::HTTPSuccess
        return http_resp
      when Net::HTTPRedirection
        http_get http_resp['location']
      else
        handle_error http_resp
      end
    end

    def build_sub_xml (params)
      xml = Nokogiri::XML(File.open(@@default_subscriber))
      params.each do |attr, value|
        next unless xml.at_css(attr.to_s)
        xml.at_css(attr.to_s).content = value
      end
      return xml.to_s
    end
  
  end
end