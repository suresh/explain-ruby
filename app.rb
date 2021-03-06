require 'sinatra'
require 'sass'
require 'pp'
require 'code'
require 'mongo'

set :sass, { :cache_location => File.join(ENV['TMPDIR'], '.sass-cache') }

configure :development do
  connection = Mongo::Connection.from_uri 'mongodb://localhost'
  db = connection.db('explainruby')
  ExplainRuby::Code.mongo = db.collection('results')
end

configure :production do
  connection = Mongo::Connection.from_uri ENV['MONGOHQ_URL']
  db = connection.db(connection.auths.last['db_name'])
  ExplainRuby::Code.mongo = db.collection('results')
end

require 'mustache/sinatra'
set :mustache, { :templates => './templates', :views => './views' }

require 'rocco_ext'

helpers do
  def redirect_to(code)
    redirect "/#{code.slug}"
  end
  
  def rocco(options = {}, &block)
    options = settings.rocco.merge(options)
    Rocco.new(default_title, [], options, &block).to_html
  rescue Racc::ParseError
    status 500
    @message = "There was a parse error when trying to process Ruby code"
    mustache :error
  end
  
  def default_title
    "Explain Ruby"
  end
  
  def sass_with_caching(name)
    time = ::File.mtime ::File.join(settings.views, "#{name}.sass")
    expires 500, :public, :must_revalidate if settings.environment == :production
    last_modified time
    content_type 'text/css'
    sass name
  end
end

get '/' do
  if request.host == 'explainruby.heroku.com'
    redirect 'http://explainruby.net'
  else
    mustache :home
  end
end

get '/url/*' do
  code = ExplainRuby::Code.from_url params[:splat].join('')
  redirect_to code
end

post '/' do
  if not params[:url].empty?
    code = ExplainRuby::Code.from_url params[:url]
    redirect_to code
  elsif not params[:code].empty?
    code = ExplainRuby::Code.create params[:code]
    redirect_to code
  else
    status "400 Not Chunky"
    @message = "Please paste some code or enter a URL"
    mustache :error
  end
end

get '/f/:name' do
  code = ExplainRuby::Code.from_test_fixture(params[:name])
  rocco(:url => code.url) { code.to_s }
end

get '/f/:name/sexp' do
  content_type 'text/plain'
  code = ExplainRuby::Code.from_test_fixture(params[:name])
  code.pretty_inspect
end

get '/explain.css' do
  sass_with_caching :explain
end

get '/docco.css' do
  sass_with_caching :docco
end

get %r!^/([a-z0-9]{3,})$! do
  code = ExplainRuby::Code.find params[:captures][0]
  halt 404 unless code
  etag code.md5
  rocco(:url => code.url) { code.to_s }
end
