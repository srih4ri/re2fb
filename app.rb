require "sinatra"
require 'koala'
require 'open-uri'

enable :sessions
set :raise_errors, false
set :show_exceptions, false

module Reddit
  class Reddit
    REDDIT_URL = 'http://reddit.com/'
    require 'open-uri'
    require 'json'

    def self.get_posts(subreddit)
      url = REDDIT_URL+'r/'+subreddit+'.json'
      result = JSON.parse(open("#{REDDIT_URL}r/#{subreddit}.json").read)
      result['data']['children'].map do |child|
        d = child['data']
        RedditPost.new(d['url'],d['thumbnail'],d['title'],d['permalink'])
      end
    end
  end
  class RedditPost
    attr_accessor :url,:link,:thumbnail,:title,:permalink
    def initialize(url,thumbnail,title,permalink)
      if url.include?('imgur') and !url.end_with?('.jpg')
        @url = url + '.jpg'
      else
        @url = url
      end
      @permalink = permalink
      @thumbnail = thumbnail
      @title = title
    end
  end
end

# Scope defines what permissions that we are asking the user to grant.
# In this example, we are asking for the ability to publish stories
# about using the app, access to what the user likes, and to be able
# to use their pictures.  You should rewrite this scope with whatever
# permissions your app needs.
# See https://developers.facebook.com/docs/reference/api/permissions/
# for a full list of permissions
FACEBOOK_SCOPE = 'user_likes,user_photos,user_photo_video_tags,manage_pages,publish_stream'

unless ENV["FACEBOOK_APP_ID"] && ENV["FACEBOOK_SECRET"]
  abort("missing env vars: please set FACEBOOK_APP_ID and FACEBOOK_SECRET with your app credentials")
end

before do
  # HTTPS redirect
  if settings.environment == :production && request.scheme != 'https'
    redirect "https://#{request.env['HTTP_HOST']}"
  end
end

helpers do
  def host
    request.env['HTTP_HOST']
  end

  def scheme
    request.scheme
  end

  def url_no_scheme(path = '')
    "//#{host}#{path}"
  end

  def url(path = '')
    "#{scheme}://#{host}#{path}"
  end

  def authenticator
    @authenticator ||= Koala::Facebook::OAuth.new(ENV["FACEBOOK_APP_ID"], ENV["FACEBOOK_SECRET"], url("/auth/facebook/callback"))
  end

end

# the facebook session expired! reset ours and restart the process
error(Koala::Facebook::APIError) do
  session[:access_token] = nil
  redirect "/auth/facebook"
end

get "/" do
  # Get base API Connection
  @graph  = Koala::Facebook::API.new(session[:access_token])

  # Get public details of current application
  @app  =  @graph.get_object(ENV["FACEBOOK_APP_ID"])

  if session[:access_token]
    @user    = @graph.get_object("me")
  end
  erb :index
end

# used by Canvas apps - redirect the POST to be a regular GET
post "/" do
  redirect "/"
end

# used to close the browser window opened to post to wall/send to friends
get "/close" do
  "<body onload='window.close();'/>"
end

get "/sign_out" do
  session[:access_token] = nil
  redirect '/'
end

get "/auth/facebook" do
  session[:access_token] = nil
  redirect authenticator.url_for_oauth_code(:permissions => FACEBOOK_SCOPE)
end

get '/auth/facebook/callback' do
  session[:access_token] = authenticator.get_access_token(params[:code])
  redirect '/'
end

get '/authorize_page' do

  @graph  = Koala::Facebook::API.new(session[:access_token])
  @pages  =  @graph.get_connections('me', 'accounts')
  # Get public details of current application
  if params[:page_id].nil?
    erb :authorize_page
  else
    page = @pages[params[:page_id].to_i]
    session[:page_token] = page['access_token']
    redirect '/reddit_list'
  end
end

get '/reddit_list' do
  if session[:access_token].nil? or session[:page_token].nil?
    redirect 'authorize_page'
  end
  @graph  = Koala::Facebook::API.new(session[:access_token])
  @posts = Reddit::Reddit.get_posts('funny').select{|p| p.url.end_with? 'jpg'}
  erb :reddit_list
end

post '/fb_submit' do
  @graph = Koala::Facebook::API.new(session[:page_token])
  options = {
    :message => params[:title],
    :picture => params[:url]
  }
  id = @graph.put_picture(open(params[:url]),'image/jpeg',{:message => params[:title]})
  {:url => id}.to_json
end
