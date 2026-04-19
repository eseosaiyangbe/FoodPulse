#################################################################################
####                           Massimo Re Ferre'                             ####
####                             www.it20.info                               ####
####                    Yelb, a simple web application                       ####
################################################################################# 
  
#################################################################################
####   yelb-appserver.rb is the app (ruby based) component of the Yelb app   ####
####          Yelb connects to a backend database for persistency            ####
#################################################################################

require 'sinatra'
require 'aws-sdk-dynamodb' 
require_relative 'modules/pageviews'
require_relative 'modules/getvotes'
require_relative 'modules/restaurant'
require_relative 'modules/hostname'
require_relative 'modules/getstats'
require_relative 'modules/restaurantsdbupdate'
require_relative 'modules/restaurantsdbread'

# the disabled protection is required when running in production behind an nginx reverse proxy
# without this option, the angular application will spit a `forbidden` error message
disable :protection

# the system variable RACK_ENV controls which environment you are enabling
# if you choose 'custom' with RACK_ENV, all systems variables in the section need to be set before launching the yelb-appserver application
# the DDB/Region variables in test/development are there for convenience (there is no logic to avoid exceptions when reading these variables) 
# there is no expectations to be able to use DDB for test/dev 

# ---------------------------------------------------------------------------
# Environment-specific configuration
# NOTE: these are updated to honor YELB_DB_SERVER / YELB_REDIS_SERVER
#       so we can route through HAProxy (pg-haproxy, redis-haproxy).
# ---------------------------------------------------------------------------

configure :production do
  set :redishost, ENV.fetch('YELB_REDIS_SERVER', 'redis-server')
  set :port, 4567
  set :yelbdbhost => ENV.fetch('YELB_DB_SERVER', 'yelb-db')
  set :yelbdbport => 5432
  set :yelbddbrestaurants => ENV['YELB_DDB_RESTAURANTS']
  set :yelbddbcache => ENV['YELB_DDB_CACHE']
  set :awsregion => ENV['AWS_REGION']
end

configure :test do
  set :redishost, ENV.fetch('YELB_REDIS_SERVER', 'redis-server')
  set :port, 4567
  set :yelbdbhost => ENV.fetch('YELB_DB_SERVER', 'yelb-db')
  set :yelbdbport => 5432
  set :yelbddbrestaurants => ENV['YELB_DDB_RESTAURANTS']
  set :yelbddbcache => ENV['YELB_DDB_CACHE']
  set :awsregion => ENV['AWS_REGION']
end

configure :development do
  set :redishost, ENV.fetch('YELB_REDIS_SERVER', 'localhost')
  set :port, 4567
  set :yelbdbhost => ENV.fetch('YELB_DB_SERVER', 'localhost')
  set :yelbdbport => 5432
  set :yelbddbrestaurants => ENV['YELB_DDB_RESTAURANTS']
  set :yelbddbcache => ENV['YELB_DDB_CACHE']
  set :awsregion => ENV['AWS_REGION']
end

configure :custom do
  # keep “custom” env semantics but align names with the rest
  set :redishost, ENV['YELB_REDIS_SERVER'] || ENV['REDIS_SERVER_ENDPOINT']
  set :port, 4567
  set :yelbdbhost => (ENV['YELB_DB_SERVER'] || ENV['YELB_DB_SERVER_ENDPOINT'])
  set :yelbdbport => 5432
  set :yelbddbrestaurants => ENV['YELB_DDB_RESTAURANTS']
  set :yelbddbcache => ENV['YELB_DDB_CACHE']
  set :awsregion => ENV['AWS_REGION']
end

options "*" do
  response.headers["Allow"] = "HEAD,GET,PUT,DELETE,OPTIONS"

  # Needed for AngularJS
  response.headers["Access-Control-Allow-Headers"] = "X-Requested-With, X-HTTP-Method-Override, Content-Type, Cache-Control, Accept"

  halt HTTP_STATUS_OK
end

# ---------------------------------------------------------------------------
# Global variables used by the modules
# ---------------------------------------------------------------------------

$yelbdbhost = settings.yelbdbhost
$yelbdbport = settings.yelbdbport
$redishost  = settings.redishost

# Optional Redis AUTH support – used when requirepass/masterauth are enabled
$redispassword = ENV['YELB_REDIS_PASSWORD']

# the yelbddbcache, yelbdbrestaurants and the awsregion variables are only
# intended to use in the serverless scenario (DDB)
if settings.yelbddbcache     != nil then $yelbddbcache     = settings.yelbddbcache     end 
if settings.yelbddbrestaurants != nil then $yelbddbrestaurants = settings.yelbddbrestaurants end 
if settings.awsregion        != nil then $awsregion        = settings.awsregion        end 

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

get '/api/pageviews' do
  headers 'Access-Control-Allow-Origin'  => '*'
  headers 'Access-Control-Allow-Headers' => 'Authorization,Accepts,Content-Type,X-CSRF-Token,X-Requested-With'
  headers 'Access-Control-Allow-Methods' => 'GET,POST,PUT,DELETE,OPTIONS'
  content_type 'application/json'
  @pageviews = pageviews()
end #get /api/pageviews

get '/api/hostname' do
  headers 'Access-Control-Allow-Origin'  => '*'
  headers 'Access-Control-Allow-Headers' => 'Authorization,Accepts,Content-Type,X-CSRF-Token,X-Requested-With'
  headers 'Access-Control-Allow-Methods' => 'GET,POST,PUT,DELETE,OPTIONS'
  content_type 'application/json'
  @hostname = hostname()
end #get /api/hostname

get '/api/getstats' do
  headers 'Access-Control-Allow-Origin'  => '*'
  headers 'Access-Control-Allow-Headers' => 'Authorization,Accepts,Content-Type,X-CSRF-Token,X-Requested-With'
  headers 'Access-Control-Allow-Methods' => 'GET,POST,PUT,DELETE,OPTIONS'
  content_type 'application/json'
  @stats = getstats()
end #get /api/getstats

get '/api/getvotes' do
  headers 'Access-Control-Allow-Origin'  => '*'
  headers 'Access-Control-Allow-Headers' => 'Authorization,Accepts,Content-Type,X-CSRF-Token,X-Requested-With'
  headers 'Access-Control-Allow-Methods' => 'GET,POST,PUT,DELETE,OPTIONS'
  content_type 'application/json'
  @votes = getvotes()
end #get /api/getvotes 

get '/api/ihop' do
  headers 'Access-Control-Allow-Origin'  => '*'
  headers 'Access-Control-Allow-Headers' => 'Authorization,Accepts,Content-Type,X-CSRF-Token,X-Requested-With'
  headers 'Access-Control-Allow-Methods' => 'GET,POST,PUT,DELETE,OPTIONS'
  @ihop = restaurantsupdate("ihop")
end #get /api/ihop 

get '/api/chipotle' do
  headers 'Access-Control-Allow-Origin'  => '*'
  headers 'Access-Control-Allow-Headers' => 'Authorization,Accepts,Content-Type,X-CSRF-Token,X-Requested-With'
  headers 'Access-Control-Allow-Methods' => 'GET,POST,PUT,DELETE,OPTIONS' 
  @chipotle = restaurantsupdate("chipotle")
end #get /api/chipotle 

get '/api/outback' do
  headers 'Access-Control-Allow-Origin'  => '*'
  headers 'Access-Control-Allow-Headers' => 'Authorization,Accepts,Content-Type,X-CSRF-Token,X-Requested-With'
  headers 'Access-Control-Allow-Methods' => 'GET,POST,PUT,DELETE,OPTIONS'
  @outback = restaurantsupdate("outback")
end #get /api/outback 

get '/api/bucadibeppo' do
  headers 'Access-Control-Allow-Origin'  => '*'
  headers 'Access-Control-Allow-Headers' => 'Authorization,Accepts,Content-Type,X-CSRF-Token,X-Requested-With'
  headers 'Access-Control-Allow-Methods' => 'GET,POST,PUT,DELETE,OPTIONS' 
  @bucadibeppo = restaurantsupdate("bucadibeppo")
end #get /api/bucadibeppo 

# Generic vote endpoint – compatible with future UI changes and curl tests
get '/api/vote' do
  headers 'Access-Control-Allow-Origin'  => '*'
  headers 'Access-Control-Allow-Headers' => 'Authorization,Accepts,Content-Type,X-CSRF-Token,X-Requested-With'
  headers 'Access-Control-Allow-Methods' => 'GET,POST,PUT,DELETE,OPTIONS'
  content_type 'application/json'

  restaurant = params['restaurant']

  # Basic input validation – keep list in sync with restaurantsupdate()
  allowed = %w[ihop chipotle outback bucadibeppo]
  halt 400, "unknown restaurant" unless allowed.include?(restaurant)

  # Reuse the existing restaurantsupdate() logic
  restaurantsupdate(restaurant)
end
# get /api/vote added by Eseosa
