require 'data_mapper'
require 'dm-validations'

TOKEN_LENGTH = 64

DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/signup.db")

class Signup
  include DataMapper::Resource
  property :id, Serial
  property :email, String, :format => :email_address
  property :token, String, :length => TOKEN_LENGTH + 22
  property :created_at, DateTime
  property :expired, Boolean, :default => false
end

DataMapper.finalize
Signup.auto_upgrade!