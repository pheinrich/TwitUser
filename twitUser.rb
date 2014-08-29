#!/usr/bin/ruby

require 'base64'
require 'csv'
require 'json'
require 'net/http'
require 'open-uri'
require 'openssl'
require 'optparse'
require 'ostruct'

options = OpenStruct.new
options.showDetails = true

OptionParser.new do |opts|
  opts.banner = 'Usage: twitUser.rb [options] handle'
  opts.on( '-d', '--[no-]details', 'Show stats for user (default)' ) {|v| options.showDetails = v}
  opts.on( '-f', '--[no-]followers', 'Find followers' ) {|v| options.findFollowers = v}
  opts.on( '-r', '--[no-]friends', 'Find friends' ) {|v| options.findFriends = v}
  opts.on( '-o', '--screenname', 'Show screen names only (no other info)' ) {|v| options.onlyHandle = v} 
  opts.on( '-v', '--[no-]verbose', 'Run verbosely' ) {|v| options.verbose = v}

  opts.on_tail( '-h', '--help', 'Show this message' ) do
    puts opts
    exit
  end
end.parse!
options.user = ARGV.pop

if options.user.nil?
  puts "You must specify a twitter handle."
  exit
end
def bearerTokenCreds
  Base64.encode64( URI::encode( "#{ENV['TWITTER_APIKEY']}:#{ENV['TWITTER_APISECRET']}" ) ).gsub( "\n", "" )
end

def getAccessToken
  uri = URI.parse( 'https://api.twitter.com' )

  http = Net::HTTP.new( uri.host, uri.port )
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  request = Net::HTTP::Post.new( '/oauth2/token' )
  request.add_field( 'Authorization', "Basic #{bearerTokenCreds}" )
  request.add_field( 'Content-Type', 'application/x-www-form-urlencoded;charset=UTF-8' )
  request.add_field( 'Content-Length', '29' )
  request.body = "grant_type=client_credentials"

  response = http.request( request )
  JSON.parse( response.body )['access_token']
end

def getUser( accessToken, userId )
  key = userId.is_a?( String ) ? :screen_name : :user_id 
  uri = URI.parse( 'https://api.twitter.com/1.1/users/lookup.json' )
  uri.query = URI.encode_www_form( {key => userId} )

  http = Net::HTTP.new( uri.host, uri.port )
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  request = Net::HTTP::Get.new( uri )
  request.add_field( 'Authorization', "Bearer #{accessToken}" )

  response = http.request( request )
  JSON.parse( response.body )[0]
end

def getLinkedUsers( accessToken, userId, relationship )
  users = []
  cursor = -1

  uri = URI.parse( "https://api.twitter.com/1.1/#{relationship}/list.json" )
  key = userId.is_a?( String ) ? :screen_name : :user_id

  http = Net::HTTP.new( uri.host, uri.port )
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  until 0 == cursor do
    uri.query = URI.encode_www_form( {key => userId, :cursor => cursor, :count => 200, :skip_status => true, :include_user_entities => true} )

    request = Net::HTTP::Get.new( uri )
    request.add_field( 'Authorization', "Bearer #{accessToken}" )

    json = JSON.parse( http.request( request ).body )
    users.concat( json['users'] )
    cursor = json['next_cursor']
  end

  users
end

def getFollowers( accessToken, userId )
  getLinkedUsers( accessToken, userId, 'followers' )
end

def getFriends( accessToken, userId )
  getLinkedUsers( accessToken, userId, 'friends' )
end

def displayUser( user )
  puts "Name: #{user['name']} (@#{user['screen_name']})"
  puts "  Location: #{user['location']}" unless user['location'].empty?
  puts "  Description: #{user['description']}" unless user['description'].empty?
  puts "  Followers: #{user['followers_count']}"
  puts "  Friends: #{user['friends_count']}"

  urls = user['entities']
  urls = urls['url'] if urls
  urls = urls['urls'] if urls

  if urls
    puts "  URLs:"
    urls.each {|url| puts "    #{url['expanded_url']}"}
  end
end

def displayUsers( users, short )
  keys = ['screen_name']
  keys += %w(name location description followers_count friends_count listed_count statuses_count id) unless short

  puts keys.to_csv
  users.each do |user|
    values = keys.map {|key| user[key]}
    puts values.to_csv
  end
end

accessToken = getAccessToken

if options.showDetails
  puts "User details" if options.verbose
  user = getUser( accessToken, options.user )

  if user
    displayUser( user )
  else
    puts "User #{options.user} doesn't exist"
    exit
  end
end

if options.findFriends
  puts "Friends" if options.verbose
  displayUsers( getFriends( accessToken, options.user ), options.onlyHandle )
end

if options.findFollowers
  puts "Followers" if options.verbose
  displayUsers( getFollowers( accessToken, options.user ), options.onlyHandle )
end
