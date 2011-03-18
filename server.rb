require 'rubygems'
require 'sinatra'
require 'json'

require 'net/https'
require 'cgi'
require 'yaml'

config_file = File.join('config', 'config.yml')
raise "Config file (#{config_file}) does not exist.  Create it before starting this server." unless File.exists?(config_file)

CONFIG = YAML.load(File.read(config_file))
NET_HTTP_DEBUG = ENV['NET_HTTP_DEBUG']

def querystring(params)
  params.collect { |(key, value)| [key, CGI.escape(value)].join('=') }.join('&')
end

def oauth_user_authentication_uri
  params = {
    :client_id =>    CONFIG[:client][:identifier],
    :redirect_uri => CONFIG[:client][:redirect_uri]
  }
  params.merge!(:scope => CONFIG[:client][:scope]) if CONFIG[:client][:scope]
  [CONFIG[:server][:oauth_authorize_uri], querystring(params)].join('?')
end

def oauth_client_authentication_params(oauth_code)
  {
    :client_id     => CONFIG[:client][:identifier],
    :client_secret => CONFIG[:client][:secret],
    :grant_type    => 'authorization_code',
    :redirect_uri  => CONFIG[:client][:redirect_uri],
    :code          => oauth_code
  }
end

def get_access_token(oauth_code)
  uri        = URI.parse(CONFIG[:server][:oauth_access_token_uri])
  params     = oauth_client_authentication_params(oauth_code)
  
  connection = Net::HTTP.new(uri.host, uri.port)
  connection.set_debug_output $stdout if NET_HTTP_DEBUG
  connection.use_ssl = true
  request    = Net::HTTP::Post.new(uri.path)
  request.set_form_data params
  response   = connection.start { |http| http.request(request) }
  JSON.parse(response.body)
end

def api_request(resource, access_token)
  uri = URI.parse(File.join(CONFIG[:server][:api_uri], resource))
  connection = Net::HTTP.new(uri.host, uri.port)
  connection.use_ssl = true
  connection.set_debug_output $stdout if NET_HTTP_DEBUG
  request = Net::HTTP::Get.new(uri.path, 'Authorization' => ['OAuth', access_token].join(' '))
  response = connection.start { |http| http.request(request) }
  response.body
end

get '/' do
  if $access_token
    <<-EndHtml
    Yay, you're authorized, with the following access token: #{$access_token}<br/>
    View your <a href="/messages">messages</a>.
    EndHtml
  else
    "<a href=\"#{oauth_user_authentication_uri}\">Authorize this client</a>"
  end
end

get '/oauth_callback' do
  if code = params['code']
    $access_token = get_access_token(code)['access_token']
    redirect '/'
  end
end

get '/messages' do
  api_request('messages', $access_token)
end