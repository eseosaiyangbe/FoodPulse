require 'redis'

def yelb_redis_client(options = {})
  host = options[:host] || $redishost || ENV['YELB_REDIS_SERVER'] || 'redis-server'
  port = options[:port] || 6379

  # Priority: explicit option > global > env
  password = options.key?(:password) ? options[:password] : ($redispassword || ENV['YELB_REDIS_PASSWORD'])

  Redis.new(
    host: host,
    port: port,
    password: password
  )
end
