require "net/http"
require "json"
require "uri"

module HsAi
  def self.share_similar_experience(topic)
    post_text =
      topic
        .first_post
        .raw
        &.gsub(/<[^>]*>/, "")
        .gsub(/\n/, " ")
        .gsub(/\s+/, " ")
        &.strip

    post_text = clean_text(post_text)

    # make a request to the vector db
    url = URI("http://34.45.99.81:8080/search")
    http = Net::HTTP.new(url.host, url.port)
    request = Net::HTTP::Get.new(url)
    request["Content-Type"] = "application/json"
    request.body = { text: post_text }.to_json
    response = http.request(request)
    status = response.code
    body = JSON.parse(response.body)

    if status == 200 || status == "200"
      # select one where post is not the same
      results =
        body["results"].select do |result|
          result["post_id"] != topic.posts.first.id
        end
      similar_question = results&.first || nil
      if similar_question
        user_question = similar_question["message"] || nil
        support_response = similar_question["support"][0]["message"] || nil

        if user_question && support_response
          tag =
            topic
              .tags
              .where(id: TagGroup.find_by(id: 19)&.tags&.select(:id) || [])
              &.limit(1)
              &.pluck(:name)
              &.first
          # send a formatted response
          user_reply = formatted_response(user_question, support_response, tag)

          # post a reply to the topic
          user = User.find_by(id: 13_733)

          if user
            post_params = { topic_id: topic.id, raw: user_reply }
            PostCreator.create(user, post_params)
            # Post.create!(topic_id: topic.id, user_id: user.id, raw: user_reply)
          end
        end
      end
    else
      Rails.logger.error("Failed to get similar experience from AI")
    end
  end

  def self.formatted_response(user_question, support_response, tag)
    text = <<~TEXT
        Hi,
        Thanks so much for opening up. We wanted to share a request from a #{tag} fan that was similar to yours. They said:

        #{user_question}

        If it's helpful, here's what one of our repliers wrote in response to them:

        #{support_response}

        Thank you for your courage.

        -HeartSupport
      TEXT

    return text
  end

  def self.send_dm(usernames, text, title)
    system_user = User.find_by(username: "system")
    dm_params = {
      title: title,
      raw: text,
      archetype: Archetype.private_message,
      target_usernames: usernames
    }
    # send DM to repliers
    PostCreator.create!(system_user, dm_params)
    # puts "DM sent to #{usernames} with post id: #{post.id}"
  end

  def self.clean_text(text)
    # Define patterns to remove
    phrases_to_remove = [
      /this is a topic from instagram. reply as normal, and we will post it to the user on instagram./i,
      /this is a topic from facebook. reply as normal, and we will post it to the user on instagram./i,
      /this is a topic from facebook. reply as normal, and we will post it to the user on facebook./i,
      /this is a topic from twitter. reply as normal, and we will post it to the user on twitter./i,
      /this is a topic from facebook. reply as normal, and we will post it to the user on youtube./i,
      /this is a topic from instagram. in order to participate in these conversations you need to/i,
      /this is a topic from youtube. reply as normal, and we will post it to the user on youtube./i,
      /belongs to:/i
    ]

    # Remove all defined phrases
    phrases_to_remove.each { |pattern| text = text.gsub(pattern, "") }

    # Remove HTTP links
    text = text.gsub(%r{https?://\S+|www\.\S+}, " ")
    text = text.gsub(/\s+/, " ")
    test = text&.strip
    text
  end
end
