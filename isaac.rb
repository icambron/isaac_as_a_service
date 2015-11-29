require 'json'
require 'bundler'
Bundler.require

def twitter
  tweets = []

  Twitter.configure do |config|
    config.consumer_key = ENV['ISAAC_TWITTER_KEY']
    config.consumer_secret = ENV['ISAAC_TWITTER_SECRET']
  end

  puts 'Requesting Twitter'
  Twitter.user_timeline('icambron', exclude_replies: true, count: 30).each do |tweet|
    tweets << {created_at: tweet.created_at, text: tweet.text, url: "https://twitter.com/icambron/status/#{tweet.id}"}
  end
  puts 'Processed Twitter'

  tweets.take 10
end

def github

  activities = []

  Github.configure do |config|
    config.basic_auth = ENV['ISAAC_GITHUB_TOKEN']
  end

  puts 'Requesting Github'
  Github.activity.events.performed('icambron', public: true) do |event|

    summary =
      case event.type
      when 'IssueCommentEvent'
        next unless event.payload.action == 'created'
        {
          issue: {
            number: event.payload.issue.number,
            title: event.payload.issue.title
          },
          url: event.payload.comment.html_url,
          comment: event.payload.comment.body
        }

      when 'PullRequestEvent'
        next unless event.payload.action == 'opened'
        {
          number: event.payload.number,
          url: event.payload.pull_request.html_url,
          comment: event.payload.pull_request.body,
          commits: event.payload.pull_request.commits,
          title: event.payload.pull_request.title
        }

      when 'PushEvent'
        {
           commits: event.payload.commits.size
        }
      else
        next
      end

    summary[:repo] = { name: event.repo.name, url: "https://github.com/#{event.repo.name}" }
    summary[:type] = event.type
    summary[:created_at] = event.created_at
    activities << summary
  end

  puts 'Processed Github'
  activities.take(10)
end

def upload(hash)

  connection = Fog::Storage.new(
    provider: 'AWS',
    aws_access_key_id: ENV['ISAAC_S3_ID'],
    aws_secret_access_key: ENV['ISAAC_S3_KEY']
  )

  dir = connection.directories.get 'isaac-as-a-service'

  puts 'Uploading to S3'
  dir.files.create(
    key: 'isaac.json',
    body: hash.to_json,
    public: true,
    content_type: 'application/json'
  )
  puts 'Finished uploading'
end

results = {}
Parallel.each(['github', 'twitter'], in_threads: 2) do |job|
  results[job] = send job
end

upload results
