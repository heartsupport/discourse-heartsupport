module HeartSupport
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
        similar_question = body["results"]&.first || nil
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
            user_reply =
              formatted_response(user_question, support_response, tag)
            title =
              "Similar Experience Found for topic: #{topic.title} with id: #{topic.id}"

            admin_usernames =
              User.where(username: %w[NateTriesAgain acaciabengo]).pluck(
                :username
              )

            # send a message to the user
            send_dm(admin_usernames, user_reply, title)
          end
        end
      else
        Rails.logger.error("Failed to get similar experience from AI")
      end
    end

    def self.formatted_response(user_question, support_response, tag)
      text = <<~TEXT
        Hi,
        Thanks so much for opening up. We've received your request, and we've notified our volunteer repliers! In the meantime, we wanted to share a request from a #{tag} fan that was similar to yours. They said:

        #{user_question}

        If it's helpful, here's what one of our repliers wrote in response to them:

        #{support_response}

        Thank you for your courage. We'll reply again soon!

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
  end
end
