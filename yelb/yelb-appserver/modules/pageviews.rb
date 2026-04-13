require_relative 'redis_client'
require 'aws-sdk-dynamodb'

def pageviews
  if $yelbddbcache != nil && $yelbddbcache != ""
    dynamodb = Aws::DynamoDB::Client.new(region: $awsregion)

    params = {
      table_name: $yelbddbcache,
      key: { counter: 'pageviews' }
    }

    pageviewsrecord = dynamodb.get_item(params)
    pageviewscount  = pageviewsrecord.item['pageviewscount']
    pageviewscount += 1

    update_params = {
      table_name: $yelbddbcache,
      key: { counter: 'pageviews' },
      update_expression: 'set pageviewscount = :c',
      expression_attribute_values: { ':c' => pageviewscount },
      return_values: 'UPDATED_NEW'
    }

    dynamodb.update_item(update_params)
  else
    redis = yelb_redis_client
    redis.incr('pageviews')
    pageviewscount = redis.get('pageviews')
    redis.quit
  end

  pageviewscount.to_s
end