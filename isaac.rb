require 'json'
require 'bundler'
Bundler.require

def twitter
  tweets = []

  Twitter.configure do |config|
    config.consumer_key = ENV['ISAAC_TWITTER_KEY']
    config.consumer_secret = ENV['ISAAC_TWITTER_SECRET']
  end

  Twitter.user_timeline('icambron', count: 5).each do |tweet|
    tweets << {created_at: tweet.created_at, text: tweet.text}
  end

  tweets
end

def github

  activities = []

  Github.configure do |config|
    config.oauth_token = ENV['ISAAC_GITHUB_TOKEN']
  end

  Github.activity.events.performed('icambron', public: true) do |event|

    summary =
      case event.type
      when 'IssueCommentEvent'
        {
          action: event.payload.action,
          issue: {
            number: event.payload.issue.number,
            title: event.payload.issue.title
          },
          url: event.payload.comment.html_url,
          comment: event.payload.comment.body
        }

      when 'PullRequestEvent'
        {
          repo: { name: event.repo.name, url: "https://github.com/#{event.repo.name}" },
          number: event.payload.number,
          url: event.payload.pull_request.html_url,
          comment: event.payload.pull_request.body,
          commits: event.payload.pull_request.commits
        }

      when 'PushEvent'
        {
           repo: { name: event.repo.name, url: "https://github.com/#{event.repo.name}" },
           commits: event.payload.commits.size
        }
      else
        next
      end

    summary[:type] = event.type
    summary[:created_at] = event.created_at
    activities << summary
  end

  activities
end

def upload(hash)
  connection = Fog::Storage.new({
    provider: 'AWS',
    aws_access_key_id: ENV['ISAAC_S3_ID'],
    aws_secret_access_key: ENV['ISAAC_S3_KEY']
  })

  dir = connection.directories.get('isaac-as-a-service')
  dir.files.create({
    key: 'isaac.json',
    body: hash.to_json,
    public: true
  })
end

results = {}
Parallel.each(['github', 'twitter'], in_threads: 2) do |job|
  results[job] = send job
end

upload results
