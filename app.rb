require 'sinatra'
require 'sinatra/flash'
require 'sinatra/redirect_with_flash'
require 'rack/recaptcha'
require './pcsrestclient'
Dir.glob('./{models,helpers}/*.rb').each { |file| require file }

BASE_URL = "http://fierce-trigger-85-114623.euw1-2.nitrousbox.com"

use Rack::Recaptcha, :public_key => '6LcOlPkSAAAAAMEeG_PmTnsjYLtAcWNqjt-UNCpo', :private_key => '6LcOlPkSAAAAAGKPd9visJnMSgU8q_8Zp_AFAbDd'
helpers Rack::Recaptcha::Helpers
helpers Sinatra::MailHelper

enable :sessions

log_file = File.new("#{Dir.pwd}/log/main.log", "a+")
log_file.sync = true
$stdout.reopen(log_file)
$stderr.reopen(log_file)


# Set port for compatability with nitrous.io
configure :development do
  set :bind, '0.0.0.0'
  set :port, 3000
  set :session_secret, "tcpip123"
  disable :raise_errors
  disable :show_exceptions
  use Rack::CommonLogger, log_file
end

# initialize REST API connection
before do
  initialize_rest
end

# display message
get '/' do
  erb :message
end  

# signup page
get '/signup' do
  erb :signup
end

# create signup token and send email
post '/signup' do
  @email = params[:email]
  if @email.empty?
    redirect '/signup', :error => "Enter a valid email address"
  else
    @token, @url = get_token_and_url
    @activation = Signup.new(:email => @email,:token => @token,:created_at => Time.now)
    if @activation.save
      send_signup_email(@email, @url)
      logger.info "signup email sent to #{@email} with token #{@token}"
      redirect '/', :notice => "Please check your email to complete signup"
    else
      logger.error "failed to save entry for #{@email} with token #{@token}"
      redirect '/signup', :error => @activation.errors.full_messages.join(",")
    end
  end
end

# verify token and complete signup form
get '/verify' do
  @token = params[:token] || session[:token]
  @signup = Signup.first(:token => @token)
  if @signup.nil?
    logger.info "invalid token #{@token}"
    redirect "/not_found", flash[:error] = "Invalid Token" 
  elsif token_expired?
    @signup.destroy
    logger.info "token expired #{@token}"
    redirect "/not_found", flash[:error] = "Token Expired"
  else 
    session[:email] = @signup[:email]
    session[:token] ||= @token
    erb :activation
  end
end

# post signup form after validating passwords and captcha
post '/verify' do
  session[:first_name] = params[:first_name]
  session[:last_name] = params[:last_name]
  if password_valid? && recaptcha_valid? && session[:token]
    @answer = @conn.create_sub(session[:first_name], session[:last_name], session[:email], session[:password])
    send_activation_mail(session[:email], @answer[:firstName], @answer[:conferencePasscode], @answer[:moderatorPasscode])
    @signup = Signup.first(:token => session[:token])
    logger.info "account no. #{@answer[:popdAccountNum]} created for session[:email]"
    @signup.destroy unless @signup.nil?
    session[:token] = nil
    redirect '/', :notice => "Congratulations, signup complete. Please check your email"
  else
    redirect "/verify", flash[:error] = "Please try again"
  end
end

#get '/db' do
  # get the latest 20 posts
#  @entries = Signup.all
 # erb :data
#end

# display error message
not_found do
  status 404
  erb :message
end

# error hnadling, redirect to /not_found and display error message
error do
  logger.error "#{env['sinatra.error'].message}"
  redirect "/not_found", flash[:error] = "#{env['sinatra.error'].message}"
  session[:token] = nil
end

helpers do 
  def get_token_and_url
    token = SecureRandom.urlsafe_base64(n=TOKEN_LENGTH)
    url = "#{BASE_URL}/verify?token=" + token
    return [token, url]
  end
  
  def token_expired?
    age = Date.today - @signup.created_at.to_date
    return nil unless age > 30
  end
  
  def password_valid?
    if params[:password] != params[:password_confirmation] or params[:password].nil?
      session[:password] ||= nil
      return nil
    else
      session[:password] = params[:password]
      return params[:password]
    end
  end
  
  def initialize_rest
    @conn = PCSREST::API.new( :host => 'dev-rsjs.oss.colt.net', 
                              :spid => '1', 
                              :user => "ita||XXXXXX||key-XXXX",
                              :pass => "XXXXX" )
  end
end

