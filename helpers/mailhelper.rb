require "mandrill"
ENV['MANDRILL_APIKEY'] = "eFeFUmdrFI5aLBxri4Sruw"
FROM_ADDR = "taylor.rich@gmail.com"
FROM_NAME = "xConferencing"

module Sinatra
  module MailHelper

    def send_signup_email(to_address, signup_url)
      merge_vars = get_merge_vars({"SIGNUP_URL" => signup_url})
      body = File.read("#{Dir.pwd}/templates/signup.html")
      send_mail( to_address, "Welcome to xConferencing...", body, merge_vars)
    end
      
    def send_activation_mail(to_address, first_name, conference_passcode, moderator_passcode)
      merge_vars = get_merge_vars({"FIRST_NAME" => first_name,
                                   "CONFERENCE_PASSCODE" => conference_passcode,
                                   "MODERATOR_PASSCODE" => moderator_passcode})
      body = File.read("#{Dir.pwd}/templates/activation.html")
      send_mail( to_address, "Welcome to xConferencing...", body, merge_vars)
    end  
    
    def get_merge_vars(args={})
      merge_vars = []
      args.each {|k,v| merge_vars << {:name => k, :content => v}}
      merge_vars
    end
        
    def send_mail( to_address, subject, body, merge_vars)
      begin 
        m = Mandrill::API.new
        message = {  
            :global_merge_vars => merge_vars,
            :subject => subject,  
            :from_name => FROM_NAME,  
            :to => [{:email => to_address}], 
            :html => body, 
            :from_email => FROM_ADDR,
          }  
        sending = m.messages.send message  
      rescue Mandrill::Error => e
        puts "#{e.class} / #{e.message}"
      end
    end
  
  end
      

#helpers MailHelper

end